package grit.os.client.gritos_client

import android.content.Context
import android.media.AudioAttributes
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
import org.webrtc.RTCStatsCollectorCallback
import org.webrtc.RTCStatsReport
import org.webrtc.RtpReceiver
import org.webrtc.RtpTransceiver
import org.webrtc.SdpObserver
import org.webrtc.SessionDescription
import org.webrtc.audio.JavaAudioDeviceModule
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToLong

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
    private var localCandidate: String? = null
    private var remoteCandidate: String? = null
    private var selectedPairState: String? = null
    private var useCommunicationAudio = false
    private var audioOutput = "speaker"
    private var currentIcePolicy = "all"
    private var createdAtMs = 0L
    private var lastIceStateChangedAtMs = 0L
    private var lastConnectionStateChangedAtMs = 0L
    private var lastGatheringStateChangedAtMs = 0L
    private var localCandidateCount = 0
    private var remoteCandidateCount = 0
    private var localRelayCandidateCount = 0
    private var remoteRelayCandidateCount = 0
    private var emittedRelayGatheringWarning = false
    private var lastIceTimelineFingerprint: String? = null
    private val iceTimelineRunnable = object : Runnable {
        override fun run() {
            emitIceTimeline("periodic")
            if (peerConnection != null) {
                mainHandler.postDelayed(this, 1000)
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        runOnMain {
            try {
                when (call.method) {
                    "create" -> create(call, result)
                    "startOffer" -> startOffer(call.argument<String>("reason") ?: "manual", result)
                    "handleRemoteDescription" -> handleRemoteDescription(call, result)
                    "addIceCandidate" -> addIceCandidate(call.argument<Map<String, Any?>>("candidate"), result)
                    "setMuted" -> setMuted(call, result)
                    "setAudioOutput" -> setAudioOutput(call, result)
                    "switchToRelay" -> switchToRelay(call, result)
                    "prepareForReconnect" -> {
                        prepareForReconnect()
                        result.success(null)
                    }
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
        stopIceTimeline()
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
        useCommunicationAudio = call.argument<Boolean>("useCommunicationAudio") ?: false
        audioOutput = call.argument<String>("audioOutput") ?: "speaker"
        ensureFactory(useCommunicationAudio, audioOutput)
        currentIcePolicy = configuration["iceTransportPolicy"] as? String ?: "all"
        createdAtMs = nowMs()
        lastIceStateChangedAtMs = createdAtMs
        lastConnectionStateChangedAtMs = createdAtMs
        lastGatheringStateChangedAtMs = createdAtMs
        localCandidateCount = 0
        remoteCandidateCount = 0
        localRelayCandidateCount = 0
        remoteRelayCandidateCount = 0
        emittedRelayGatheringWarning = false
        lastIceTimelineFingerprint = null

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

        try {
            pc.addTransceiver(
                localAudioTrack,
                RtpTransceiver.RtpTransceiverInit(
                    RtpTransceiver.RtpTransceiverDirection.SEND_ONLY,
                    listOf(roomId),
                ),
            )
        } catch (error: Throwable) {
            pc.addTrack(localAudioTrack, listOf(roomId))
            emit("onLog", mapOf("level" to "warn", "message" to "audio transceiver failed, falling back to addTrack: ${error.message}"))
        }

        // We don't pre-allocate transceivers here anymore because the server 
        // will add them on negotiation. Pre-allocating can cause track count mismatch.

        emit("onLog", mapOf("level" to "info", "message" to "native Android PeerConnection created"))
        emit("onLog", iceConfigLogData(configuration))
        warnIfNoUsableRelay(configuration, currentIcePolicy)
        startIceTimeline()
        result.success(null)
    }

    private fun prepareForReconnect() {
        pendingRemoteCandidates.clear()
        hasRemoteDescription = false
        makingOffer = false
        emit("onLog", mapOf("level" to "warn", "message" to "native signaling reconnected; waiting for SFU rejoin"))
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
        emit("onLog", mapOf("level" to "debug", "message" to "native setting remote SDP: ${description.type.name}"))
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
        val summary = summarizeCandidateSdp(ice.sdp)
        remoteCandidateCount += 1
        if (summary["type"] == "relay") {
            remoteRelayCandidateCount += 1
        }
        emit(
            "onLog",
            mapOf(
                "level" to "debug",
                "message" to "native remote ICE candidate",
                "elapsed_ms" to elapsedMs(),
                "mid" to ice.sdpMid,
                "mLine" to ice.sdpMLineIndex,
            ) + summary,
        )
        if (!hasRemoteDescription) {
            pendingRemoteCandidates.add(ice)
            emit("onLog", mapOf("level" to "debug", "message" to "native queued remote ICE candidate"))
            result.success(null)
            return
        }
        peerConnection?.addIceCandidate(ice)
        if (hasRemoteDescription) {
            remoteCandidate = "mid:${ice.sdpMid}, index:${ice.sdpMLineIndex}, ${ice.sdp.take(15)}..."
        }
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

    private fun setAudioOutput(call: MethodCall, result: MethodChannel.Result) {
        audioOutput = call.argument<String>("value") ?: "speaker"
        configureAudioRoute(useCommunicationAudio, audioOutput)
        emit(
            "onLog",
            mapOf("level" to "info", "message" to "native audio output changed", "audio_output" to audioOutput),
        )
        result.success(null)
    }

    private fun switchToRelay(call: MethodCall, result: MethodChannel.Result) {
        val pc = peerConnection ?: run {
            result.error("missing_peer", "PeerConnection is not created", null)
            return
        }
        val configuration = call.argument<Map<String, Any?>>("configuration") ?: emptyMap()
        val reason = call.argument<String>("reason") ?: "native-relay-fallback"
        emit(
            "onLog",
            mapOf(
                "level" to "warn",
                "message" to "native relay fallback: switching ICE policy to relay + restartIce",
                "reason" to reason,
                "elapsed_ms" to elapsedMs(),
                "ice" to lastIceState,
                "connection" to lastConnectionState,
                "previous_policy" to currentIcePolicy,
                "relay_fallback_used" to relayFallbackUsed,
            ) + iceServersDiagnostics(configuration),
        )
        relayFallbackUsed = true
        currentIcePolicy = "relay"
        emittedRelayGatheringWarning = false
        warnIfNoUsableRelay(configuration, "relay")
        pc.setConfiguration(parseRtcConfiguration(configuration + mapOf("iceTransportPolicy" to "relay")))
        pc.restartIce()
        emit("onIceRestartNeeded", mapOf("reason" to reason))
        result.success(null)
    }

    private fun getDebugSnapshot(result: MethodChannel.Result) {
        val pc = peerConnection
        if (pc == null) {
            result.success(
                mapOf(
                    "implementation" to "android-native-webrtc",
                    "status" to "closed"
                )
            )
            return
        }

        pc.getStats(object : RTCStatsCollectorCallback {
            override fun onStatsDelivered(report: RTCStatsReport) {
                val statsMap = mutableMapOf<String, String>()
                statsMap["implementation"] = "android-native-webrtc"
                statsMap["room"] = roomId
                statsMap["connection"] = lastConnectionState
                statsMap["ice"] = lastIceState
                statsMap["gathering"] = lastGatheringState
                statsMap["signaling"] = lastSignalingState
                statsMap["relay fallback"] = if (relayFallbackUsed) "used" else "not used"
                statsMap["local audio"] = if (localAudioTrack?.enabled() == true) "enabled" else "muted"
                statsMap["pending candidates"] = pendingRemoteCandidates.size.toString()

                var rtt = "-"
                var jitter = "-"
                var packetLoss = "-"
                var bytesReceived = 0L
                var bytesSent = 0L

                for (stats in report.statsMap.values) {
                    val members = stats.members
                    when (stats.type) {
                        "inbound-rtp" -> {
                            if (members["kind"] == "audio") {
                                bytesReceived += (members["bytesReceived"] as? Number)?.toLong() ?: 0L
                                jitter = members["jitter"]?.let { String.format("%.1f ms", (it as Number).toDouble() * 1000.0) } ?: jitter
                                val lost = (members["packetsLost"] as? Number)?.toLong() ?: 0L
                                val rec = (members["packetsReceived"] as? Number)?.toLong() ?: 0L
                                if (rec + lost > 0) {
                                    packetLoss = String.format("%.1f%%", (lost.toDouble() / (rec + lost).toDouble()) * 100.0)
                                }
                            }
                        }
                        "outbound-rtp" -> {
                            if (members["kind"] == "audio") {
                                bytesSent += (members["bytesSent"] as? Number)?.toLong() ?: 0L
                            }
                        }
                        "candidate-pair" -> {
                            if (members["selected"] == true || members["nominated"] == true) {
                                rtt = members["currentRoundTripTime"]?.let { String.format("%.0f ms", (it as Number).toDouble() * 1000.0) } ?: rtt
                                selectedPairState = members["state"]?.toString() ?: selectedPairState
                                
                                val localId = members["localCandidateId"] as? String
                                val remoteId = members["remoteCandidateId"] as? String
                                
                                localId?.let { id ->
                                    report.statsMap[id]?.let { s ->
                                        val type = s.members["candidateType"] ?: s.members["type"] ?: "unknown"
                                        val proto = s.members["protocol"] ?: "unknown"
                                        val ip = s.members["ip"] ?: s.members["address"] ?: "unknown"
                                        val port = s.members["port"] ?: "unknown"
                                        localCandidate = "$type $proto $ip:$port"
                                    }
                                }
                                remoteId?.let { id ->
                                    report.statsMap[id]?.let { s ->
                                        val type = s.members["candidateType"] ?: s.members["type"] ?: "unknown"
                                        val proto = s.members["protocol"] ?: "unknown"
                                        val ip = s.members["ip"] ?: s.members["address"] ?: "unknown"
                                        val port = s.members["port"] ?: "unknown"
                                        remoteCandidate = "$type $proto $ip:$port"
                                    }
                                }
                            }
                        }
                    }
                }
                
                statsMap["rtt"] = rtt
                statsMap["jitter"] = jitter
                statsMap["packet loss"] = packetLoss
                statsMap["in audio bytes"] = bytesReceived.toString()
                statsMap["out bytes"] = bytesSent.toString()
                statsMap["local candidate"] = localCandidate ?: "-"
                statsMap["remote candidate"] = remoteCandidate ?: "-"
                statsMap["candidate pair"] = selectedPairState ?: "-"

                runOnMain {
                    result.success(statsMap)
                }
            }
        })
    }

    private fun observer(): PeerConnection.Observer {
        return object : PeerConnection.Observer {
            override fun onSignalingChange(state: PeerConnection.SignalingState) {
                lastSignalingState = signalingStateString(state)
                emit("onSignalingState", mapOf("state" to lastSignalingState))
            }

            override fun onIceConnectionChange(state: PeerConnection.IceConnectionState) {
                lastIceState = iceConnectionStateString(state)
                lastIceStateChangedAtMs = nowMs()
                emitIceTimeline("ice-state-$lastIceState")
                emit("onIceConnectionState", mapOf("state" to lastIceState))
            }

            override fun onConnectionChange(state: PeerConnection.PeerConnectionState) {
                lastConnectionState = connectionStateString(state)
                lastConnectionStateChangedAtMs = nowMs()
                emitIceTimeline("pc-state-$lastConnectionState")
                emit("onConnectionState", mapOf("state" to lastConnectionState))
            }

            override fun onIceGatheringChange(state: PeerConnection.IceGatheringState) {
                lastGatheringState = iceGatheringStateString(state)
                lastGatheringStateChangedAtMs = nowMs()
                emitIceTimeline("gathering-$lastGatheringState")
                emit("onIceGatheringState", mapOf("state" to lastGatheringState))
                if (state == PeerConnection.IceGatheringState.COMPLETE) {
                    if (currentIcePolicy == "relay" && localRelayCandidateCount == 0 && !emittedRelayGatheringWarning) {
                        emittedRelayGatheringWarning = true
                        emit(
                            "onLog",
                            mapOf(
                                "level" to "warn",
                                "message" to "native relay-only gathering completed without relay candidates",
                                "elapsed_ms" to elapsedMs(),
                                "local_candidates" to localCandidateCount,
                                "remote_candidates" to remoteCandidateCount,
                            ),
                        )
                    }
                    emit("onIceCandidate", null)
                }
            }

            override fun onIceCandidate(candidate: IceCandidate) {
                val summary = summarizeCandidateSdp(candidate.sdp)
                localCandidateCount += 1
                if (summary["type"] == "relay") {
                    localRelayCandidateCount += 1
                }
                localCandidate = "mid:${candidate.sdpMid}, index:${candidate.sdpMLineIndex}, ${candidate.sdp.take(15)}..."
                emit(
                    "onLog",
                    mapOf(
                        "level" to "debug",
                        "message" to "native local ICE candidate",
                        "elapsed_ms" to elapsedMs(),
                        "mid" to candidate.sdpMid,
                        "mLine" to candidate.sdpMLineIndex,
                    ) + summary,
                )
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
                    "onLog",
                    mapOf(
                        "level" to "info",
                        "message" to "native remote track received",
                        "elapsed_ms" to elapsedMs(),
                        "kind" to track.kind(),
                        "track_id" to track.id(),
                        "stream_ids" to streams.map { it.id },
                    ),
                )
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
                emit("onLog", mapOf("level" to "debug", "message" to "native renegotiation needed", "elapsed_ms" to elapsedMs()))
                emit("onRenegotiationNeeded", emptyMap<String, Any>())
            }

            override fun onIceCandidatesRemoved(candidates: Array<out IceCandidate>) = Unit
            override fun onIceConnectionReceivingChange(receiving: Boolean) = Unit
            override fun onAddStream(stream: MediaStream) = Unit
            override fun onRemoveStream(stream: MediaStream) = Unit
            override fun onDataChannel(dataChannel: org.webrtc.DataChannel) = Unit
            override fun onRemoveTrack(receiver: RtpReceiver) = Unit
        }
    }

    private fun ensureFactory(useCommunicationAudio: Boolean, audioOutput: String) {
        configureAudioRoute(useCommunicationAudio, audioOutput)
        if (factory == null) {
            if (factoryInitialized.compareAndSet(false, true)) {
                PeerConnectionFactory.initialize(
                    PeerConnectionFactory.InitializationOptions.builder(context)
                        .setEnableInternalTracer(true)
                        .createInitializationOptions(),
                )
            }

            val audioAttributes = AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()

            audioDeviceModule = JavaAudioDeviceModule.builder(context)
                .setAudioAttributes(audioAttributes)
                .setUseHardwareAcousticEchoCanceler(true)
                .setUseHardwareNoiseSuppressor(true)
                .setUseStereoInput(false)
                .setUseStereoOutput(false)
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

    private fun startIceTimeline() {
        mainHandler.removeCallbacks(iceTimelineRunnable)
        mainHandler.postDelayed(iceTimelineRunnable, 1000)
    }

    private fun stopIceTimeline() {
        mainHandler.removeCallbacks(iceTimelineRunnable)
    }

    private fun emitIceTimeline(reason: String) {
        val pc = peerConnection ?: return
        pc.getStats(object : RTCStatsCollectorCallback {
            override fun onStatsDelivered(report: RTCStatsReport) {
                val data = buildIceTimeline(reason, report)
                val fingerprint = listOf(
                    data["reason"],
                    data["ice"],
                    data["connection"],
                    data["gathering"],
                    data["selected_pair"],
                    data["local_candidate"],
                    data["remote_candidate"],
                    data["pair_states"],
                    data["local_candidate_types"],
                    data["remote_candidate_types"],
                    data["out_audio_bytes"],
                    data["in_audio_bytes"],
                ).joinToString("|")
                if (fingerprint != lastIceTimelineFingerprint || reason != "periodic") {
                    lastIceTimelineFingerprint = fingerprint
                    emit("onLog", data)
                }
            }
        })
    }

    private fun buildIceTimeline(reason: String, report: RTCStatsReport): Map<String, Any> {
        val now = nowMs()
        val candidateTypesById = mutableMapOf<String, String>()
        val localCandidateTypeCounts = mutableMapOf<String, Int>()
        val remoteCandidateTypeCounts = mutableMapOf<String, Int>()
        val pairStateCounts = mutableMapOf<String, Int>()
        var selectedLocalId: String? = null
        var selectedRemoteId: String? = null
        var selectedState = "-"
        var selectedWritable = "-"
        var selectedNominated = "-"
        var selectedRttMs = "-"
        var selectedRequestsSent = "-"
        var selectedResponsesReceived = "-"
        var availableOutgoingBitrate = "-"
        var inboundAudioBytes = 0L
        var outboundAudioBytes = 0L
        var inboundAudioPackets = 0L
        var outboundAudioPackets = 0L
        var inboundAudioLost = 0L

        for ((id, stats) in report.statsMap) {
            val members = stats.members
            when (stats.type) {
                "local-candidate", "remote-candidate" -> {
                    val candidateType = members["candidateType"]?.toString()
                        ?: members["type"]?.toString()
                        ?: "unknown"
                    candidateTypesById[id] = candidateType
                    val target = if (stats.type == "local-candidate") localCandidateTypeCounts else remoteCandidateTypeCounts
                    target[candidateType] = (target[candidateType] ?: 0) + 1
                }
                "candidate-pair" -> {
                    val state = members["state"]?.toString() ?: "unknown"
                    pairStateCounts[state] = (pairStateCounts[state] ?: 0) + 1
                    val selected = members["selected"] == true || members["nominated"] == true
                    if (selected) {
                        selectedState = state
                        selectedLocalId = members["localCandidateId"] as? String
                        selectedRemoteId = members["remoteCandidateId"] as? String
                        selectedWritable = members["writable"]?.toString() ?: "-"
                        selectedNominated = members["nominated"]?.toString() ?: "-"
                        selectedRttMs = numberMs(members["currentRoundTripTime"] ?: members["totalRoundTripTime"])
                        selectedRequestsSent = members["requestsSent"]?.toString() ?: "-"
                        selectedResponsesReceived = members["responsesReceived"]?.toString() ?: "-"
                        availableOutgoingBitrate = (members["availableOutgoingBitrate"] as? Number)
                            ?.toDouble()
                            ?.let { "${(it / 1000.0).roundToLong()} kbps" }
                            ?: availableOutgoingBitrate
                    }
                }
                "inbound-rtp" -> if (members["kind"] == "audio") {
                    inboundAudioBytes += (members["bytesReceived"] as? Number)?.toLong() ?: 0L
                    inboundAudioPackets += (members["packetsReceived"] as? Number)?.toLong() ?: 0L
                    inboundAudioLost += (members["packetsLost"] as? Number)?.toLong() ?: 0L
                }
                "outbound-rtp" -> if (members["kind"] == "audio") {
                    outboundAudioBytes += (members["bytesSent"] as? Number)?.toLong() ?: 0L
                    outboundAudioPackets += (members["packetsSent"] as? Number)?.toLong() ?: 0L
                }
            }
        }

        val selectedLocal = selectedLocalId?.let { candidateSummary(report, it) } ?: "-"
        val selectedRemote = selectedRemoteId?.let { candidateSummary(report, it) } ?: "-"
        return mapOf(
            "level" to "debug",
            "message" to "native ICE timeline",
            "reason" to reason,
            "elapsed_ms" to (now - createdAtMs),
            "since_ice_ms" to (now - lastIceStateChangedAtMs),
            "since_pc_ms" to (now - lastConnectionStateChangedAtMs),
            "since_gathering_ms" to (now - lastGatheringStateChangedAtMs),
            "ice" to lastIceState,
            "connection" to lastConnectionState,
            "gathering" to lastGatheringState,
            "signaling" to lastSignalingState,
            "ice_policy" to currentIcePolicy,
            "pair_states" to pairStateCounts,
            "selected_pair" to selectedState,
            "selected_writable" to selectedWritable,
            "selected_nominated" to selectedNominated,
            "selected_rtt_ms" to selectedRttMs,
            "selected_requests_sent" to selectedRequestsSent,
            "selected_responses_received" to selectedResponsesReceived,
            "available_outgoing_bitrate" to availableOutgoingBitrate,
            "local_candidate" to selectedLocal,
            "remote_candidate" to selectedRemote,
            "local_candidate_types" to localCandidateTypeCounts,
            "remote_candidate_types" to remoteCandidateTypeCounts,
            "local_candidate_events" to localCandidateCount,
            "remote_candidate_events" to remoteCandidateCount,
            "local_relay_events" to localRelayCandidateCount,
            "remote_relay_events" to remoteRelayCandidateCount,
            "out_audio_bytes" to outboundAudioBytes,
            "out_audio_packets" to outboundAudioPackets,
            "in_audio_bytes" to inboundAudioBytes,
            "in_audio_packets" to inboundAudioPackets,
            "in_audio_lost" to inboundAudioLost,
        )
    }

    private fun candidateSummary(report: RTCStatsReport, id: String): String {
        val stats = report.statsMap[id] ?: return id
        val members = stats.members
        val type = members["candidateType"] ?: members["type"] ?: "unknown"
        val proto = members["protocol"] ?: "unknown"
        val address = members["ip"] ?: members["address"] ?: "unknown"
        val port = members["port"] ?: "unknown"
        val url = members["url"]?.toString()?.takeIf { it.isNotBlank() }
        return listOfNotNull(type, proto, "$address:$port", url).joinToString(" ")
    }

    private fun summarizeCandidateSdp(candidate: String): Map<String, Any> {
        val parts = candidate.trim().split(Regex("\\s+"))
        fun valueAfter(token: String): String? {
            val index = parts.indexOf(token)
            return if (index >= 0 && index + 1 < parts.size) parts[index + 1] else null
        }
        return mapOf(
            "type" to (valueAfter("typ") ?: "-"),
            "protocol" to (parts.getOrNull(2) ?: "-"),
            "address" to (parts.getOrNull(4) ?: "-"),
            "port" to (parts.getOrNull(5) ?: "-"),
            "related_address" to (valueAfter("raddr") ?: "-"),
            "related_port" to (valueAfter("rport") ?: "-"),
            "candidate_len" to candidate.length,
        )
    }

    private fun iceConfigLogData(configuration: Map<String, Any?>): Map<String, Any> {
        val servers = configuration["iceServers"] as? List<*> ?: emptyList<Any>()
        val summaries = servers.mapNotNull { raw ->
            val server = raw as? Map<*, *> ?: return@mapNotNull null
            val urls = when (val rawUrls = server["urls"]) {
                is String -> listOf(rawUrls)
                is List<*> -> rawUrls.filterIsInstance<String>()
                else -> emptyList()
            }
            mapOf(
                "urls" to urls,
                "hasUsername" to ((server["username"] as? String)?.isNotBlank() == true),
                "hasCredential" to ((server["credential"] as? String)?.isNotBlank() == true),
            )
        }
        return mapOf(
            "level" to "info",
            "message" to "native RTC config",
            "ice_policy" to currentIcePolicy,
            "ice_servers" to summaries,
        ) + iceServersDiagnostics(configuration)
    }

    /// Counts STUN/TURN servers so "relay-only without TURN" situations are
    /// visible in logs (the root cause when relay ICE silently fails).
    private fun iceServersDiagnostics(configuration: Map<String, Any?>): Map<String, Any> {
        val servers = configuration["iceServers"] as? List<*> ?: emptyList<Any>()
        var stunCount = 0
        var turnCount = 0
        var turnWithCreds = 0
        servers.forEach { raw ->
            val server = raw as? Map<*, *> ?: return@forEach
            val urls = when (val rawUrls = server["urls"]) {
                is String -> listOf(rawUrls)
                is List<*> -> rawUrls.filterIsInstance<String>()
                else -> emptyList()
            }
            val hasTurn = urls.any { it.startsWith("turn:") || it.startsWith("turns:") }
            val hasStun = urls.any { it.startsWith("stun:") }
            if (hasTurn) {
                turnCount += 1
                val username = (server["username"] as? String)?.isNotBlank() == true
                val credential = (server["credential"] as? String)?.isNotBlank() == true
                if (username && credential) turnWithCreds += 1
            }
            if (hasStun) stunCount += 1
        }
        return mapOf(
            "stun_count" to stunCount,
            "turn_count" to turnCount,
            "turn_with_creds" to turnWithCreds,
            "has_turn" to (turnCount > 0),
        )
    }

    private fun warnIfNoUsableRelay(configuration: Map<String, Any?>, policy: String) {
        val diagnostics = iceServersDiagnostics(configuration)
        val hasTurn = diagnostics["has_turn"] == true
        val turnWithCreds = (diagnostics["turn_with_creds"] as? Int) ?: 0
        if (policy == "relay" && !hasTurn) {
            emit(
                "onLog",
                mapOf(
                    "level" to "warn",
                    "message" to "native relay-only ICE policy WITHOUT any TURN server — ICE will fail",
                ) + diagnostics,
            )
        } else if ((diagnostics["turn_count"] as? Int ?: 0) != 0 && turnWithCreds == 0) {
            emit(
                "onLog",
                mapOf(
                    "level" to "warn",
                    "message" to "native TURN servers present but NONE have credentials — relay will likely fail",
                ) + diagnostics,
            )
        }
    }

    private fun numberMs(value: Any?): String {
        val seconds = (value as? Number)?.toDouble() ?: return "-"
        return "${(seconds * 1000.0).roundToLong()}"
    }

    private fun nowMs(): Long = System.currentTimeMillis()

    private fun elapsedMs(): Long = if (createdAtMs == 0L) 0L else nowMs() - createdAtMs

    private fun configureAudioRoute(useCommunicationAudio: Boolean, audioOutput: String) {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        val useEarpiece = audioOutput == "earpiece"
        val useVoiceStream = useCommunicationAudio || useEarpiece
        audioManager.mode = if (useVoiceStream) AudioManager.MODE_IN_COMMUNICATION else AudioManager.MODE_NORMAL
        audioManager.isSpeakerphoneOn = !useEarpiece
        
        // Ensure volume is up
        val stream = if (useVoiceStream) AudioManager.STREAM_VOICE_CALL else AudioManager.STREAM_MUSIC
        val maxVolume = audioManager.getStreamMaxVolume(stream)
        audioManager.setStreamVolume(stream, maxVolume / 2, 0)
        emit(
            "onLog",
            mapOf(
                "level" to "info",
                "message" to "native audio route configured",
                "audio_output" to audioOutput,
                "use_communication_audio" to useCommunicationAudio,
                "mode" to (if (useVoiceStream) "in_communication" else "normal"),
                "speakerphone_on" to !useEarpiece,
                "stream" to (if (useVoiceStream) "voice_call" else "music"),
                "volume" to (maxVolume / 2),
                "max_volume" to maxVolume,
            ),
        )
    }

    private fun restoreAudioRoute() {
        val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        audioManager.isSpeakerphoneOn = false
        audioManager.mode = AudioManager.MODE_NORMAL
    }

    private fun emitLocalDescription(description: SessionDescription) {
        emit("onLog", mapOf("level" to "debug", "message" to "native local SDP created: ${description.type.name}"))
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
