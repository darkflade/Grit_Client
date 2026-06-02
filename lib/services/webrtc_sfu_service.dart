import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../data/api/event_transport.dart';

class WebRtcSfuService {
  final String roomId;
  final EventTransport transport;
  final bool isPolite;
  String? sessionId;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  final Map<String, RTCRtpSender> _sendersByKind = {};
  bool _makingOffer = false;
  bool _ignoreOffer = false;
  bool _hasRemoteDescription = false;
  final List<RTCIceCandidate> _pendingRemoteCandidates = [];

  final _onTrackController = StreamController<RTCTrackEvent>.broadcast();
  Stream<RTCTrackEvent> get onTrack => _onTrackController.stream;

  final _connectionStateController =
      StreamController<RTCPeerConnectionState>.broadcast();
  Stream<RTCPeerConnectionState> get connectionState =>
      _connectionStateController.stream;
  final _connectionStateValue = ValueNotifier<RTCPeerConnectionState>(
    RTCPeerConnectionState.RTCPeerConnectionStateNew,
  );
  ValueListenable<RTCPeerConnectionState> get connectionStateListenable =>
      _connectionStateValue;

  final _localStreamController = StreamController<MediaStream?>.broadcast();
  Stream<MediaStream?> get localStream => _localStreamController.stream;

  final _isMicMuted = ValueNotifier<bool>(false);
  ValueListenable<bool> get isMicMuted => _isMicMuted;

  final _isCameraOff = ValueNotifier<bool>(false);
  ValueListenable<bool> get isCameraOff => _isCameraOff;

  final _participants = ValueNotifier<Map<String, Map<String, dynamic>>>({});
  ValueListenable<Map<String, Map<String, dynamic>>> get participants => _participants;

  final _activeSpeakers = ValueNotifier<Set<String>>({});
  ValueListenable<Set<String>> get activeSpeakers => _activeSpeakers;

  final _remoteAudioTrackCount = ValueNotifier<int>(0);
  ValueListenable<int> get remoteAudioTrackCount => _remoteAudioTrackCount;
  final Set<String> _seenRemoteAudioTrackIds = <String>{};

  final _mediaDevices = ValueNotifier<List<MediaDeviceInfo>>([]);
  ValueListenable<List<MediaDeviceInfo>> get mediaDevices => _mediaDevices;

  final _selectedAudioInputId = ValueNotifier<String?>(null);
  ValueListenable<String?> get selectedAudioInputId => _selectedAudioInputId;

  final _selectedVideoInputId = ValueNotifier<String?>(null);
  ValueListenable<String?> get selectedVideoInputId => _selectedVideoInputId;

  final _videoQuality = ValueNotifier<String>('1080p');
  ValueListenable<String> get videoQuality => _videoQuality;

  final _stereoAudio = ValueNotifier<bool>(false);
  ValueListenable<bool> get stereoAudio => _stereoAudio;

  bool _disposed = false;

  WebRtcSfuService({
    required this.roomId,
    required this.transport,
    this.isPolite = true,
  });

  Future<void> initialize() async {
    // Request permissions before anything else
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (statuses[Permission.camera] != PermissionStatus.granted ||
        statuses[Permission.microphone] != PermissionStatus.granted) {
      debugPrint("SFU: Permissions not granted. Camera: ${statuses[Permission.camera]}, Mic: ${statuses[Permission.microphone]}");
      // We proceed but getUserMedia will likely fail, which is handled below.
    }

    final configuration = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
      'sdpSemantics': 'unified-plan',
    };

    _peerConnection = await createPeerConnection(configuration);
    await _configureMobileAudio();

    _peerConnection!.onSignalingState = (RTCSignalingState state) {
      debugPrint("SFU[$roomId]: Signaling State: $state");
    };

    _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
      debugPrint("SFU[$roomId]: ICE Gathering State: $state");
    };

    // Get local media
    final addedKinds = <String>{};
    try {
      _localStream = await _acquireLocalMedia();
      if (_localStream != null) {
        _isMicMuted.value = _localStream!.getAudioTracks().isEmpty;
        _isCameraOff.value = _localStream!.getVideoTracks().isEmpty;
      }
      _localStreamController.add(_localStream);
      for (var track in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
        final kind = track.kind;
        if (kind != null) {
          addedKinds.add(kind);
        }
        final sender = await _peerConnection!.addTrack(track, _localStream!);
        if (kind != null) {
          _sendersByKind[kind] = sender;
        }
      }
    } catch (e) {
      debugPrint("SFU: Failed to get local media: $e");
    }
    await _ensureReceiverTransceivers(addedKinds);
    await refreshMediaDevices();

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      debugPrint(
        "SFU[$roomId]: Local ICE candidate: ${candidate.candidate == null ? 'end' : candidate.sdpMid}",
      );
      transport.sfuSendIceCandidate(roomId, candidate.toMap());
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      debugPrint("SFU[$roomId]: ICE Connection State: $state");
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        debugPrint("SFU[$roomId]: Network drop detected (ICE $state), requesting ICE restart...");
        restartIce();
      }
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      debugPrint("SFU[$roomId]: Connection State: $state");
      if (_disposed) return;
      _connectionStateValue.value = state;
      _connectionStateController.add(state);
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) async {
      final trackKind = event.track.kind;
      debugPrint(
        "SFU[$roomId]: Received remote track kind=$trackKind id=${event.track.id} streams=${event.streams.map((s) => s.id).join(',')}",
      );
      if (trackKind == 'audio') {
        event.track.enabled = true;
        final trackId = event.track.id;
        if (trackId != null) {
          _seenRemoteAudioTrackIds.add(trackId);
        }
        _remoteAudioTrackCount.value = _seenRemoteAudioTrackIds.length;
        try {
          await Helper.setVolume(1.0, event.track);
        } catch (e) {
          debugPrint("SFU: Failed to set remote audio volume: $e");
        }
        await _configureMobileAudio();
      }
      _onTrackController.add(event);
    };

    _peerConnection!.onRenegotiationNeeded = () async {
      await _negotiate("renegotiation-needed");
    };
  }

  Future<void> _negotiate(String reason) async {
    final peerConnection = _peerConnection;
    if (peerConnection == null) return;

    if (sessionId == null) {
      debugPrint("SFU[$roomId]: Delaying negotiation until sfu_joined ($reason)");
      return;
    }

    final signalingState =
        await peerConnection.getSignalingState() ??
        RTCSignalingState.RTCSignalingStateStable;

    if (_makingOffer ||
        signalingState != RTCSignalingState.RTCSignalingStateStable) {
      debugPrint(
        "SFU[$roomId]: Delaying negotiation, signaling state is $signalingState ($reason)",
      );
      return;
    }

    try {
      _makingOffer = true;
      debugPrint("SFU[$roomId]: Creating offer ($reason)");
      final offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);
      final sdpLength = offer.sdp?.length ?? 0;
      debugPrint(
        "SFU[$roomId]: Sending offer type=${offer.type} sdpLength=$sdpLength",
      );
      transport.sfuSendOffer(roomId, offer.sdp!, offer.type!);
    } catch (e) {
      debugPrint("SFU[$roomId]: Negotiation error ($reason): $e");
    } finally {
      _makingOffer = false;
    }
  }

  Future<MediaStream?> _acquireLocalMedia() async {
    final audioConstraints = _audioConstraints(_selectedAudioInputId.value);
    final videoConstraints = _videoConstraints(_selectedVideoInputId.value);
    final attempts = <Map<String, dynamic>>[
      {
        'audio': audioConstraints,
        'video': videoConstraints,
      },
      {
        'audio': audioConstraints,
        'video': false,
      },
    ];

    Object? lastError;
    for (final constraints in attempts) {
      try {
        final stream = await navigator.mediaDevices.getUserMedia(constraints);
        debugPrint("SFU: Acquired local media with constraints $constraints");
        return stream;
      } catch (e) {
        lastError = e;
        debugPrint("SFU: getUserMedia failed for $constraints: $e");
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    return null;
  }

  Map<String, dynamic> _audioConstraints(String? deviceId) {
    return {
      'mandatory': {},
      'optional': [
        if (deviceId != null) {'sourceId': deviceId},
        {'echoCancellation': true},
        {'noiseSuppression': true},
        {'autoGainControl': true},
        if (_stereoAudio.value) {'googAudioMirroring': false},
      ],
      if (_stereoAudio.value) 'channelCount': 2,
      if (_stereoAudio.value) 'sampleRate': 48000,
    };

  }

  Map<String, dynamic> _videoConstraints(String? deviceId) {
    final size = switch (_videoQuality.value) {
      '720p' => (width: 1280, height: 720),
      '480p' => (width: 854, height: 480),
      _ => (width: 1920, height: 1080),
    };
    return {
      'facingMode': 'user',
      if (deviceId != null) 'optional': [{'sourceId': deviceId}],
      'width': {'ideal': size.width},
      'height': {'ideal': size.height},
      'frameRate': {'ideal': 30},
    };
  }

  Future<void> refreshMediaDevices() async {
    try {
      _mediaDevices.value = await navigator.mediaDevices.enumerateDevices();
    } catch (e) {
      debugPrint("SFU[$roomId]: Failed to enumerate media devices: $e");
    }
  }

  Future<void> selectAudioInput(String? deviceId) async {
    _selectedAudioInputId.value = deviceId;
    await _replaceLocalTrack('audio');
    if (deviceId != null && !kIsWeb) {
      try {
        await Helper.selectAudioInput(deviceId);
      } catch (e) {
        debugPrint("SFU[$roomId]: Failed to select native audio input: $e");
      }
    }
  }

  Future<void> selectVideoInput(String? deviceId) async {
    _selectedVideoInputId.value = deviceId;
    await _replaceLocalTrack('video');
  }

  Future<void> setVideoQuality(String quality) async {
    if (_videoQuality.value == quality) return;
    _videoQuality.value = quality;
    await _replaceLocalTrack('video');
  }

  Future<void> setStereoAudio(bool enabled) async {
    if (_stereoAudio.value == enabled) return;
    _stereoAudio.value = enabled;
    await _replaceLocalTrack('audio');
  }

  Future<void> _replaceLocalTrack(String kind) async {
    final peerConnection = _peerConnection;
    final localStream = _localStream;
    if (peerConnection == null || localStream == null) return;

    final constraints = kind == 'audio'
        ? {'audio': _audioConstraints(_selectedAudioInputId.value), 'video': false}
        : {'audio': false, 'video': _videoConstraints(_selectedVideoInputId.value)};

    debugPrint("SFU[$roomId]: Replacing $kind track with constraints $constraints");
    final newStream = await navigator.mediaDevices.getUserMedia(constraints);
    final newTrack = kind == 'audio'
        ? newStream.getAudioTracks().firstOrNull
        : newStream.getVideoTracks().firstOrNull;
    if (newTrack == null) {
      await newStream.dispose();
      return;
    }

    final oldTracks = kind == 'audio'
        ? List<MediaStreamTrack>.from(localStream.getAudioTracks())
        : List<MediaStreamTrack>.from(localStream.getVideoTracks());

    var sender = _sendersByKind[kind];
    if (sender == null) {
      final senders = await peerConnection.getSenders();
      for (final item in senders) {
        if (item.track?.kind == kind) {
          sender = item;
          break;
        }
      }
    }

    if (sender != null) {
      await sender.replaceTrack(newTrack);
      _sendersByKind[kind] = sender;
      if (kind == 'video') {
        final params = sender.parameters;
        params.degradationPreference = RTCDegradationPreference.MAINTAIN_RESOLUTION;
        await sender.setParameters(params);
      }
    } else {
      _sendersByKind[kind] = await peerConnection.addTrack(newTrack, localStream);
      unawaited(_negotiate("replace-$kind-track"));
    }

    for (final track in oldTracks) {
      await localStream.removeTrack(track);
      track.stop();
    }
    await localStream.addTrack(newTrack);
    _localStreamController.add(localStream);

    if (kind == 'audio') {
      _isMicMuted.value = false;
    } else {
      _isCameraOff.value = false;
    }

    await refreshMediaDevices();
  }

  Future<void> _ensureReceiverTransceivers(Set<String> addedKinds) async {
    if (!addedKinds.contains('audio')) {
      await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.RecvOnly,
        ),
      );
    }
    if (!addedKinds.contains('video')) {
      await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(
          direction: TransceiverDirection.RecvOnly,
        ),
      );
    }
  }

  Future<void> _configureMobileAudio() async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await Helper.setAndroidAudioConfiguration(AndroidAudioConfiguration.media);
        await Helper.setSpeakerphoneOn(true);
        return;
      }
      if (Platform.isIOS) {
        await Helper.ensureAudioSession();
        await Helper.setSpeakerphoneOn(true);
      }
    } catch (e) {
      debugPrint("SFU: Failed to configure mobile audio route: $e");
    }
  }

  Future<void> handleSfuOffer(String sdp, String type) async {
    debugPrint("SFU[$roomId]: Handling remote offer type=$type sdpLength=${sdp.length}");
    final description = RTCSessionDescription(sdp, type);
    final signalingState =
        await _peerConnection!.getSignalingState() ??
        RTCSignalingState.RTCSignalingStateStable;
    final offerCollision =
        (description.type == 'offer') &&
        (_makingOffer ||
            signalingState != RTCSignalingState.RTCSignalingStateStable);

    _ignoreOffer = !isPolite && offerCollision;
    if (_ignoreOffer) {
      debugPrint("SFU[$roomId]: Ignoring impolite offer due to collision");
      return;
    }

    if (offerCollision) {
      debugPrint("SFU[$roomId]: Rolling back local offer for polite peer");
      await _peerConnection!.setLocalDescription(
        RTCSessionDescription(null, 'rollback'),
      );
    }

    await _peerConnection!.setRemoteDescription(description);
    _hasRemoteDescription = true;
    await _flushPendingRemoteCandidates();
    if (description.type == 'offer') {
      final answer = await _peerConnection!.createAnswer();
      await _peerConnection!.setLocalDescription(answer);
      debugPrint(
        "SFU[$roomId]: Sending answer type=${answer.type} sdpLength=${answer.sdp?.length ?? 0}",
      );
      transport.sfuSendAnswer(roomId, answer.sdp!, answer.type!);
    }
  }

  Future<void> handleSfuAnswer(String sdp, String type) async {
    final signalingState =
        await _peerConnection!.getSignalingState() ??
        RTCSignalingState.RTCSignalingStateClosed;
    debugPrint(
      "SFU[$roomId]: Handling remote answer type=$type sdpLength=${sdp.length} signalingState=$signalingState",
    );
    if (signalingState !=
        RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      debugPrint(
        "SFU[$roomId]: Ignoring answer outside have-local-offer: $signalingState",
      );
      return;
    }
    final description = RTCSessionDescription(sdp, type);
    await _peerConnection!.setRemoteDescription(description);
    _hasRemoteDescription = true;
    await _flushPendingRemoteCandidates();
  }

  Future<void> handleSfuIceCandidate(Map<String, dynamic>? candidateData) async {
    try {
      if (candidateData == null) {
        // End of candidates
        debugPrint("SFU[$roomId]: Received end-of-candidates");
        return;
      }

      debugPrint(
        "SFU[$roomId]: Handling remote ICE candidate mid=${candidateData['sdpMid']} mLine=${candidateData['sdpMLineIndex']}",
      );
      final candidate = RTCIceCandidate(
        candidateData['candidate'],
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex'],
      );

      if (!_hasRemoteDescription) {
        _pendingRemoteCandidates.add(candidate);
        debugPrint("SFU[$roomId]: Queued remote ICE candidate until remote description");
        return;
      }

      await _peerConnection!.addCandidate(candidate);
      debugPrint("SFU[$roomId]: Added remote ICE candidate");
    } catch (e) {
      if (!_ignoreOffer) {
        rethrow;
      }
    }
  }

  Future<void> _flushPendingRemoteCandidates() async {
    if (!_hasRemoteDescription || _pendingRemoteCandidates.isEmpty) return;

    final candidates = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in candidates) {
      await _peerConnection!.addCandidate(candidate);
    }
    debugPrint("SFU[$roomId]: Flushed ${candidates.length} remote ICE candidates");
  }

  void handleSfuJoined(String sid) {
    if (_disposed) return;
    sessionId = sid;
    debugPrint("SFU[$roomId]: Session ID set to $sid");
    
    // Send initial media state to server
    sendMediaState({
      'microphone_enabled': !_isMicMuted.value,
      'camera_enabled': !_isCameraOff.value,
    });

    unawaited(_negotiate("sfu-joined"));
  }

  void handleRtcRoomParticipants(Map<String, dynamic> data) {
    if (_disposed) return;
    final participantsList = data['participants'];
    if (participantsList is! List) return;

    final newParticipants = Map<String, Map<String, dynamic>>.from(_participants.value);
    for (var p in participantsList) {
      if (p is! Map) continue;
      final userId = p['user_id'];
      if (userId == null) continue;

      final userState = Map<String, dynamic>.from(newParticipants[userId] ?? {});
      userState['online'] = p['online'] == true;
      userState['connection_state'] = p['connection_state'];
      
      // If the participant has tracks, we can assume they are not fully muted 
      // unless sfu_media_state says otherwise later.
      final trackCount = p['track_count'] ?? 0;
      if (trackCount > 0 && userState['mic_muted'] == null) {
        userState['mic_muted'] = false;
      }

      newParticipants[userId] = userState;
    }
    _participants.value = newParticipants;
  }

  void handleRemoteMediaState(String userId, Map<String, dynamic> state) {
    if (_disposed) return;
    final newParticipants = Map<String, Map<String, dynamic>>.from(_participants.value);
    final userState = Map<String, dynamic>.from(newParticipants[userId] ?? {});
    userState.addAll(state);
    newParticipants[userId] = userState;
    _participants.value = newParticipants;
  }

  void handleParticipantMuted(String userId, String kind) {
    handleRemoteMediaState(userId, {kind == 'audio' ? 'mic_muted' : 'camera_off': true});
  }

  void handleParticipantUnmuted(String userId, String kind) {
    handleRemoteMediaState(userId, {kind == 'audio' ? 'mic_muted' : 'camera_off': false});
  }

  void handleActiveSpeakers(List<String> userIds) {
    if (_disposed) return;
    _activeSpeakers.value = userIds.toSet();
  }

  void handleParticipantLeft(String userId) {
    if (_disposed) return;
    debugPrint("SFU[$roomId]: Participant left: $userId");
    final newParticipants = Map<String, Map<String, dynamic>>.from(_participants.value);
    newParticipants.remove(userId);
    _participants.value = newParticipants;
    
    final newSpeakers = Set<String>.from(_activeSpeakers.value);
    newSpeakers.remove(userId);
    _activeSpeakers.value = newSpeakers;
  }

  Future<void> addTrack(MediaStreamTrack track, MediaStream stream) async {
    await _peerConnection!.addTrack(track, stream);
  }

  Future<void> removeTrack(RTCRtpSender sender) async {
    await _peerConnection!.removeTrack(sender);
  }

  void restartIce() {
    debugPrint("SFU[$roomId]: Requesting ICE restart...");
    transport.sfuSendIceRestart(roomId);
  }

  /// Sends the current media state (e.g., mute status) to the server.
  void sendMediaState(Map<String, dynamic> state) {
    transport.sfuSendMediaState(roomId, state);
  }

  /// Sets the mute state for a specific track type.
  Future<void> setMuted(String kind, bool muted) async {
    if (_localStream == null) return;
    for (var track in _localStream!.getTracks()) {
      if (track.kind == kind) {
        track.enabled = !muted;
      }
    }

    if (kind == 'audio') {
      _isMicMuted.value = muted;
    } else if (kind == 'video') {
      _isCameraOff.value = muted;
    }

    sendMediaState({
      kind == 'audio' ? 'microphone_enabled' : 'camera_enabled': !muted,
    });
  }

  void toggleMic() {
    setMuted('audio', !_isMicMuted.value);
  }

  void toggleCamera() {
    setMuted('video', !_isCameraOff.value);
  }

  Future<void> dispose() async {
    _disposed = true;
    for (var track in _localStream?.getTracks() ?? []) {
      track.stop();
    }
    await _localStream?.dispose();
    _localStream = null;

    await _peerConnection?.close();
    _peerConnection = null;
    await _onTrackController.close();
    await _connectionStateController.close();
    await _localStreamController.close();
    _connectionStateValue.dispose();
    _isMicMuted.dispose();
    _isCameraOff.dispose();
    _remoteAudioTrackCount.dispose();
    _mediaDevices.dispose();
    _selectedAudioInputId.dispose();
    _selectedVideoInputId.dispose();
    _videoQuality.dispose();
    _stereoAudio.dispose();
  }
}
