package grit.os.client.gritos_client

import android.content.Context
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.webrtc.AudioSource
import org.webrtc.AudioTrack
import org.webrtc.IceCandidate
import org.webrtc.MediaConstraints
import org.webrtc.MediaStream
import org.webrtc.MediaStreamTrack
import org.webrtc.PeerConnection
import org.webrtc.PeerConnectionFactory
import org.webrtc.RtpReceiver
import org.webrtc.RtpTransceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.audio.JavaAudioDeviceModule
import java.util.concurrent.atomic.AtomicBoolean

class NativeWebRtcSfuController(
    private val context: Context,
    private val channel: MethodChannel,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "NativeWebRtcSfu"
        private val factoryInitialized = AtomicBoolean(false)
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var factory: PeerConnectionFactory? = null
    private var audioDeviceModule: JavaAudioDeviceModule? = null
    private var peerConnection: PeerConnection? = null
    private var localAudioSource: AudioSource? = null
    private var localAudioTrack: AudioTrack? = null
    private val pendingRemoteCandidates = mutableListOf<IceCandidate>()
    private var roomId: String = ""
    private var makingOffer = false
    private var hasRemoteDescription = false
    private var relayFallbackUsed = false
    private var lastIceState = "new"
    private var lastConnectionState = "new"
    private var lastGatheringState = "new"
    private var lastSignalingState = "stable"

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        runOnMain {
            try {
                when (call.method) {
                    "create" -> create(call, result)
                    "startOffer" -> startOffer(call.argument<String>("reason") ?: "manual", result)
                    "handleRemoteDescription" -> handleRemoteDescription(call, result)
                    "addIceCandidate" -> addIceCandidate(call.argument<Map<String, Any?>>("candidate"), result)
                    "setMuted" -> setMuted(call, result)
                    "switchToRelay" -> switchToRelay(call, result)
                    "getDebugSnapshot" -> getDebugSnapshot(result)
                    "close" -> {
                        close()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                Log.e(TAG, "method ${call.method} failed", error)
                result.error("native_webrtc_failed", error.message, null)
            }
        }
    }

    fun close() {
        pendingRemoteCandidates.clear()
        hasRemoteDescription = false
        makingOffer = false
        relayFallbackUsed = false
        peerConnection?.close()
        peerConnection?.dispose()
        peerConnection = null
        localAudioTrack?.setEnabled(false)
        localAudioTrack?.dispose()
        localAudioTrack = null
        localAudioSource?.dispose()
        localAudioSource = null
        factory?.dispose()
        factory = null
        audioDeviceModule?.release()
        audioDeviceModule = null
        restoreAudioRoute()
    }

    private fun create(call: MethodCall, result: MethodChannel.Result) {
        close()
        roomId = call.argument<String>("roomId") ?: ""
        val configuration = call.argument<Map<String, Any?>>("configuration") ?: emptyMap()
        val useCommunicationAudio = call.argument<Boolean>("useCommunicationAudio") ?: false
        ensureFactory(useCommunicationAudio)

        val pc = requireNotNull(factory).createPeerConnection(
            parseRtcConfiguration(configuration),
            observer(),
        )
        if (pc == null) {
            result.error("create_failed", "PeerConnectionFactory returned null", null)
            return
        }
        peerConnection = pc

        val constraints = MediaConstraints().apply {
            optional.add(MediaConstraints.KeyValuePair("googEchoCancellation", "true"))
            optional.add(MediaConstraints.KeyValuePair("googNoiseSuppression", "true"))
            optional.add(MediaConstraints.KeyValuePair("googAutoGainControl", "true"))
            optional.add(MediaConstraints.KeyValuePair("echoCancellation", "true"))
        }
        localAudioSource = requireNotNull(factory).createAudioSource(constraints)
        localAudioTrack = requireNotNull(factory).createAudioTrack("native-audio-$roomId", localAudioSource)
        localAudioTrack?.setEnabled(true)
        pc.addTrack(localAudioTrack, listOf(roomId))

        try {
            pc.addTransceiver(
                MediaStreamTrack.MediaType.MEDIA_TYPE_VIDEO,
                RtpTransceiver.RtpTransceiverInit(
                    RtpTransceiver.RtpTransceiverDirection.RECV_ONLY,
                ),
            )
        } catch (error: Throwable) {
            emit("onLog", mapOf("level" to "warn", "message" to "video recvonly transceiver failed: ${error.message}"))
        }

        emit("onLog", mapOf("level" to "info", "message" to "native Android PeerConnection created"))
        result.success(null)
    }

    private fun startOffer(reason: String, result: MethodChannel.Result) {
        val pc = peerConnection ?: run {
            result.error("missing_peer", "PeerConnection is not created", null)
            return
        }
        if (makingOffer || pc.signalingState() != PeerConnection.SignalingState.STABLE) {
            emit("onLog", mapOf("level" to "debug", "message" to "native offer delayed", "reason" to reason, "signaling" to pc.signalingState().name))
            result.success(false)
            return
        }
        makingOffer = true
        pc.createOffer(object : SdpObserverAdapter() {
            override fun onCreateSuccess(description: SessionDescription) {
                pc.setLocalDescription(object : SdpObserverAdapter() {
                    override fun onSetSuccess() {
                        makingOffer = false
                        emitLocalDescription(description)
                        result.success(true)
                    }

                    override fun onSetFailure(error: String) {
                        makingOffer = false
                        result.error("set_local_failed", error, null)
                    }
                }, description)
            }

            override fun onCreateFailure(error: String) {
                makingOffer = false
                result.error("create_offer_failed", error, null)
            }
        }, MediaConstraints())
    }

    private fun handleRemoteDescription(call: MethodCall, result: MethodChannel.Result) {
        val pc = peerConnection ?: run {
            result.error("missing_peer", "PeerConnection is not created", null)
            return
        }
        val type = call.argument<String>("type") ?: ""
        val sdp = call.argument<String>("sdp") ?: ""
        val description = SessionDescription(sessionDescriptionType(type), sdp)

        if (description.type == SessionDescription.Type.ANSWER &&
            pc.signalingState() != PeerConnection.SignalingState.HAVE_LOCAL_OFFER
        ) {
            emit("onLog", mapOf("level" to "warn", "message" to "native ignored answer outside have-local-offer", "signaling" to pc.signalingState().name))
            result.success(false)
            return
        }

        if (description.type == SessionDescription.Type.OFFER &&
            (makingOffer || pc.signalingState() != PeerConnection.SignalingState.STABLE)
        ) {
            val rollback = SessionDescription(SessionDescription.Type.ROLLBACK, "")
            pc.setLocalDescription(object : SdpObserverAdapter() {
                override fun onSetSuccess() {
                    setRemoteDescription(pc, description, result)
                }

                override fun onSetFailure(error: String) {
                    result.error("rollback_failed", error, null)
                }
            }, rollback)
            return
        }

        setRemoteDescription(pc, description, result)
    }

    private fun setRemoteDescription(
        pc: PeerConnection,
        description: SessionDescription,
        result: MethodChannel.Result,
    ) {
        pc.setRemoteDescription(object : SdpObserverAdapter() {
            override fun onSetSuccess() {
                hasRemoteDescription = true
                flushPendingCandidates()
                if (description.type == SessionDescription.Type.OFFER) {
                    createAnswer(pc, result)
                } else {
                    result.success(true)
                }
            }

            override fun onSetFailure(error: String) {
                result.error("set_remote_failed", error, null)
            }
        }, description)
    }

    private fun createAnswer(pc: PeerConnection, result: MethodChannel.Result) {
        pc.createAnswer(object : SdpObserverAdapter() {
            override fun onCreateSuccess(description: SessionDescription) {
                pc.setLocalDescription(object : SdpObserverAdapter() {
                    override fun onSetSuccess() {
                        emitLocalDescription(description)
                        result.success(true)
                    }

                    override fun onSetFailure(error: String) {
                        result.error("set_answer_failed", error, null)
                    }
                }, description)
            }

            override fun onCreateFailure(error: String) {
                result.error("create_answer_failed", error, null)
            }
        }, MediaConstraints())
    }

    private fun addIceCandidate(candidate: Map<String, Any?>?, result: MethodChannel.Result) {
        if (candidate == null) {
            emit("onLog", mapOf("level" to "debug", "message" to "native received remote end-of-candidates"))
            result.success(null)
            return
        }
        val ice = IceCandidate(
            candidate["sdpMid"] as? String,
            (candidate["sdpMLineIndex"] as? Number)?.toInt() ?: 0,
            candidate["candidate"] as? String ?: "",
        )
        if (!hasRemoteDescription) {
            pendingRemoteCandidates.add(ice)
            emit("onLog", mapOf("level" to "debug", "message" to "native queued remote ICE candidate"))
            result.success(null)
            return
        }
        peerConnection?.addIceCandidate(ice)
        result.success(null)
    }

    private fun flushPendingCandidates() {
        val pc = peerConnection ?: return
        val candidates = pendingRemoteCandidates.toList()
        pendingRemoteCandidates.clear()
        for (candidate in candidates) {
            pc.addIceCandidate(candidate)
        }
        if (candidates.isNotEmpty()) {
            emit("onLog", mapOf("level" to "debug", "message" to "native flushed remote ICE candidates", "count" to candidates.size))
        }
    }

    private fun setMuted(call: MethodCall, result: MethodChannel.Result) {
        val kind = call.argument<String>("kind") ?: "audio"
        val muted = call.argument<Boolean>("muted") ?: false
        if (kind == "audio") {
            localAudioTrack?.setEnabled(!muted)
        }
        result.success(null)
    }

    private fun switchToRelay(call: MethodCall, result: MethodChannel.Result) {
        val pc = peerConnection ?: run {
            result.error("missing_peer", "PeerConnection is not created", null)
            return
        }
        val configuration = call.argument<Map<String, Any?>>("configuration") ?: emptyMap()
        relayFallbackUsed = true
        pc.setConfiguration(parseRtcConfiguration(configuration + mapOf("iceTransportPolicy" to "relay")))
        pc.restartIce()
        emit("onIceRestartNeeded", mapOf("reason" to (call.argument<String>("reason") ?: "native-relay-fallback")))
        result.success(null)
    }

    private fun getDebugSnapshot(result: MethodChannel.Result) {
        result.success(
            mapOf(
                "implementation" to "android-native-webrtc",
                "room" to roomId,
                "connection" to lastConnectionState,
                "ice" to lastIceState,
                "gathering" to lastGatheringState,
                "signaling" to lastSignalingState,
                "relay fallback" to if (relayFallbackUsed) "used" else "not used",
                "local audio" to if (localAudioTrack?.enabled() == true) "enabled" else "muted",
                "pending candidates" to pendingRemoteCandidates.size.toString(),
            )
        )
    }

    private fun observer(): PeerConnection.Observer {
        return object : PeerConnection.Observer {
            override fun onSignalingChange(state: PeerConnection.SignalingState) {
                lastSignalingState = signalingStateString(state)
                emit("onSignalingState", mapOf("state" to lastSignalingState))
            }

            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
                lastIceState = iceConnectionStateString(state)
                emit("onIceConnectionState", mapOf("state" to lastIceState))
            }

            override fun onConnectionChange(state: PeerConnection.PeerConnectionState) {
                lastConnectionState = connectionStateString(state)
                emit("onConnectionState", mapOf("state" to lastConnectionState))
            }

            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {
                lastGatheringState = iceGatheringStateString(state)
                emit("onIceGatheringState", mapOf("state" to lastGatheringState))
                if (state == PeerConnection.IceGatheringState.COMPLETE) {
                    emit("onIceCandidate", null)
                }
            }

            override fun onIceCandidate(candidate: IceCandidate) {
                emit(
                    "onIceCandidate",
                    mapOf(
                        "candidate" to candidate.sdp,
                        "sdpMid" to candidate.sdpMid,
                        "sdpMLineIndex" to candidate.sdpMLineIndex,
                    ),
                )
            }

            override fun onAddTrack(receiver: RtpReceiver, streams: Array<out MediaStream>) {
                val track = receiver.track() ?: return
                if (track.kind() == "audio") {
                    track.setEnabled(true)
                }
                emit(
                    "onTrack",
                    mapOf(
                        "kind" to track.kind(),
                        "track_id" to track.id(),
                        "stream_ids" to streams.map { it.id },
                    ),
                )
            }

            override fun onRenegotiationNeeded() {
                emit("onRenegotiationNeeded", emptyMap<String, Any>())
            }

            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) = Unit
            override fun onIceConnectionReceivingChange(receiving: Boolean) = Unit
            override fun onAddStream(stream: MediaStream) = Unit
            override fun onRemoveStream(stream: MediaStream) = Unit
            override fun onDataChannel(dataChannel: org.webrtc.DataChannel) = Unit
            override fun onRemoveTrack(receiver: RtpReceiver) = Unit
            override fun onTrack(transceiver: RtpTransceiver) = Unit
        }
    }

    private fun ensureFactory(useCommunicationAudio: Boolean) {
        configureAudioRoute(useCommunicationAudio)
        if (factory == null) {
            if (factoryInitialized.compareAndSet(false, true)) {
                PeerConnectionFactory.initialize(
                    PeerConnectionFactory.InitializationOptions.builder(context)
                        .setEnableInternalTracer(true)
                        .createInitializationOptions(),
                )
            }
            audioDeviceModule = JavaAudioDeviceModule.builder(context)
                .setUseHardwareAcousticEchoCanceler(true)
                .setUseHardwareNoiseSuppressor(true)
                .createAudioDeviceModule()
            factory = PeerConnectionFactory.builder()
                .setAudioDeviceModule(audioDeviceModule)
                .createPeerConnectionFactory()
        }
    }

    private fun parseRtcConfiguration(map: Map<String, Any?>): PeerConnection.RTCConfiguration {
        val iceServers = mutableListOf<PeerConnection.IceServer>()
        val rawServers = map["iceServers"] as? List<*>
        rawServers?.forEach { raw ->
            val server = raw as? Map<*, *> ?: return@forEach
            val urls = when (val rawUrls = server["urls"]) {
                is String -> listOf(rawUrls)
                is List<*> -> rawUrls.filterIsInstance<String>()
                else -> emptyList()
            }
            if (urls.isEmpty()) return@forEach
            val builder = PeerConnection.IceServer.builder(urls)
            (server["username"] as? String)?.takeIf { it.isNotBlank() }?.let(builder::setUsername)
            (server["credential"] as? String)?.takeIf { it.isNotBlank() }?.let(builder::setPassword)
            iceServers.add(builder.createIceServer())
        }

        return PeerConnection.RTCConfiguration(iceServers).apply {
            sdpSemantics = PeerConnection.SdpSemantics.UNIFIED_PLAN
            iceTransportsType = when (map["iceTransportPolicy"] as? String) {
                "relay" -> PeerConnection.IceTransportsType.RELAY
                "none" -> PeerConnection.IceTransportsType.NONE
                "nohost" -> PeerConnection.IceTransportsType.NOHOST
                else -> PeerConnection.IceTransportsType.ALL
            }
            continualGatheringPolicy = PeerConnection.ContinualGatheringPolicy.GATHER_CONTINUALLY
            iceCandidatePoolSize = (map["iceCandidatePoolSize"] as? Number)?.toInt()?.takeIf { it > 0 } ?: 2
            iceConnectionReceivingTimeout = (map["iceConnectionReceivingTimeout"] as? Number)?.toInt() ?: 30000
            iceBackupCandidatePairPingInterval = (map["iceBackupCandidatePairPingInterval"] as? Number)?.toInt() ?: 1000
        }
    }

    private fun configureAudioRoute(useCommunicationAudio: Boolean) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        audioManager.mode = if (useCommunicationAudio) AudioManager.MODE_IN_COMMUNICATION else AudioManager.MODE_NORMAL
        audioManager.isSpeakerphoneOn = true
    }

    private fun restoreAudioRoute() {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        audioManager.isSpeakerphoneOn = false
        audioManager.mode = AudioManager.MODE_NORMAL
    }

    private fun emitLocalDescription(description: SessionDescription) {
        emit(
            "onLocalDescription",
            mapOf(
                "type" to sessionDescriptionTypeString(description.type),
                "sdp" to description.description,
            ),
        )
    }

    private fun emit(method: String, arguments: Any?) {
        runOnMain {
            channel.invokeMethod(method, arguments)
        }
    }

    private fun runOnMain(action: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            action()
        } else {
            mainHandler.post(action)
        }
    }

    private fun sessionDescriptionType(type: String): SessionDescription.Type {
        return when (type.lowercase()) {
            "offer" -> SessionDescription.Type.OFFER
            "answer" -> SessionDescription.Type.ANSWER
            "pranswer" -> SessionDescription.Type.PRANSWER
            "rollback" -> SessionDescription.Type.ROLLBACK
            else -> SessionDescription.Type.OFFER
        }
    }

    private fun sessionDescriptionTypeString(type: SessionDescription.Type): String {
        return when (type) {
            SessionDescription.Type.OFFER -> "offer"
            SessionDescription.Type.ANSWER -> "answer"
            SessionDescription.Type.PRANSWER -> "pranswer"
            SessionDescription.Type.ROLLBACK -> "rollback"
        }
    }

    private fun connectionStateString(state: PeerConnection.PeerConnectionState): String {
        return state.name.lowercase().replace("_", "-")
    }

    private fun iceConnectionStateString(state: PeerConnection.IceConnectionState): String {
        return state.name.lowercase().replace("_", "-")
    }

    private fun iceGatheringStateString(state: PeerConnection.IceGatheringState): String {
        return state.name.lowercase().replace("_", "-")
    }

    private fun signalingStateString(state: PeerConnection.SignalingState): String {
        return when (state) {
            PeerConnection.SignalingState.STABLE -> "stable"
            PeerConnection.SignalingState.HAVE_LOCAL_OFFER -> "have-local-offer"
            PeerConnection.SignalingState.HAVE_LOCAL_PRANSWER -> "have-local-pranswer"
            PeerConnection.SignalingState.HAVE_REMOTE_OFFER -> "have-remote-offer"
            PeerConnection.SignalingState.HAVE_REMOTE_PRANSWER -> "have-remote-pranswer"
            PeerConnection.SignalingState.CLOSED -> "closed"
        }
    }

    open class SdpObserverAdapter : SdpObserver {
        override fun onCreateSuccess(description: SessionDescription) = Unit
        override fun onSetSuccess() = Unit
        override fun onCreateFailure(error: String) = Unit
        override fun onSetFailure(error: String) = Unit
    }
}
