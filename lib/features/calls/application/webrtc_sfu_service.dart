import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/realtime/event_transport.dart';
import 'ice_restart_controller.dart';

typedef RtcConfigLoader = Future<Map<String, dynamic>> Function();

const _mediaDeadFallbackDelay = Duration(seconds: 6);

class WebRtcSfuService {
  final String roomId;
  final EventTransport transport;
  final RtcConfigLoader? loadRtcConfig;
  final bool isPolite;
  String? sessionId;
  final AppLogger _log;
  final IceRestartController _iceRestartController;

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
  ValueListenable<Map<String, Map<String, dynamic>>> get participants =>
      _participants;

  final _activeSpeakers = ValueNotifier<Set<String>>({});
  ValueListenable<Set<String>> get activeSpeakers => _activeSpeakers;

  final _remoteAudioTrackCount = ValueNotifier<int>(0);
  ValueListenable<int> get remoteAudioTrackCount => _remoteAudioTrackCount;
  final Set<String> _seenRemoteAudioTrackIds = <String>{};
  final Set<String> _seenRemoteTrackIds = <String>{};
  Map<String, dynamic>? _rtcConfiguration;
  Timer? _inboundStatsTimer;
  DateTime? _connectedAt;
  DateTime? _noInboundSince;
  int? _lastInboundBytes;
  bool _relayFallbackInFlight = false;
  bool _relayFallbackUsed = false;

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
    this.loadRtcConfig,
    this.isPolite = true,
  }) : _log = AppLogger('SFU.$roomId'),
       _iceRestartController = IceRestartController(
         roomId: roomId,
         logger: AppLogger('SFU.$roomId'),
       );

  Future<void> initialize() async {
    // Request permissions before anything else
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    if (statuses[Permission.camera] != PermissionStatus.granted ||
        statuses[Permission.microphone] != PermissionStatus.granted) {
      _log.warn(
        'media permissions not fully granted',
        data: {
          'camera': statuses[Permission.camera].toString(),
          'microphone': statuses[Permission.microphone].toString(),
        },
      );
      // We proceed but getUserMedia will likely fail, which is handled below.
    }

    final configuration = await _loadRtcConfiguration();
    _rtcConfiguration = configuration;
    unawaited(_warmupTurn(configuration));

    _peerConnection = await createPeerConnection(configuration);
    await _configureMobileAudio();
    _log.info('peer connection created', data: configuration);

    _peerConnection!.onSignalingState = (RTCSignalingState state) {
      _log.debug('signaling state changed', data: {'state': state.toString()});
    };

    _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
      _log.debug(
        'ICE gathering state changed',
        data: {'state': state.toString()},
      );
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
      for (var track
          in _localStream?.getTracks() ?? const <MediaStreamTrack>[]) {
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
      _log.error('failed to get local media', error: e);
    }
    await _ensureReceiverTransceivers(addedKinds);
    await refreshMediaDevices();

    _peerConnection!.onIceCandidate = (RTCIceCandidate candidate) {
      final rawCandidate = candidate.candidate;
      _log.debug(
        'local ICE candidate',
        data: {
          'candidate': rawCandidate == null ? 'end' : 'present',
          'candidate_length': rawCandidate?.length,
          'candidate_type': _candidateToken(rawCandidate, 'typ'),
          'protocol': _candidateProtocol(rawCandidate),
          'sdp_mid': candidate.sdpMid,
          'sdp_m_line_index': candidate.sdpMLineIndex,
        },
      );
      transport.sfuSendIceCandidate(
        roomId,
        rawCandidate == null ? null : candidate.toMap(),
      );
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      _log.info(
        'ICE connection state changed',
        data: {'state': state.toString()},
      );
      _iceRestartController.handleState(
        state,
        requestRestart: (reason) => restartIce(reason),
      );
    };

    _peerConnection!.onConnectionState = (RTCPeerConnectionState state) {
      _log.info(
        'peer connection state changed',
        data: {'state': state.toString()},
      );
      if (_disposed) return;
      _connectionStateValue.value = state;
      _connectionStateController.add(state);
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _connectedAt = DateTime.now();
        _noInboundSince = null;
        _lastInboundBytes = null;
        _startInboundStatsWatch();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _connectedAt = null;
        _noInboundSince = null;
        _lastInboundBytes = null;
        _stopInboundStatsWatch();
      }
    };

    _peerConnection!.onTrack = (RTCTrackEvent event) async {
      final trackKind = event.track.kind;
      _log.info(
        'remote track received',
        data: {
          'kind': trackKind,
          'track_id': event.track.id,
          'stream_ids': event.streams.map((s) => s.id).toList(),
        },
      );
      final trackId = event.track.id;
      if (trackId != null) {
        _seenRemoteTrackIds.add(trackId);
      }
      if (trackKind == 'audio') {
        event.track.enabled = true;
        if (trackId != null) {
          _seenRemoteAudioTrackIds.add(trackId);
        }
        _remoteAudioTrackCount.value = _seenRemoteAudioTrackIds.length;
        try {
          await Helper.setVolume(1.0, event.track);
        } catch (e) {
          _log.warn('failed to set remote audio volume', data: e.toString());
        }
        await _configureMobileAudio();
      }
      _onTrackController.add(event);
    };

    _peerConnection!.onRenegotiationNeeded = () async {
      await _negotiate("renegotiation-needed");
    };
  }

  Future<Map<String, dynamic>> _loadRtcConfiguration() async {
    final fallback = <String, dynamic>{
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
          ],
        },
      ],
      'iceTransportPolicy': 'all',
      'sdpSemantics': 'unified-plan',
    };

    final loader = loadRtcConfig;
    if (loader == null) return fallback;

    try {
      final config = await loader();
      final servers = config['iceServers'];
      if (servers is! List) return fallback;
      final normalized = servers.where((server) => server['urls'] != null).map((
        server,
      ) {
        final next = <String, dynamic>{'urls': server['urls']};
        final username = server['username'];
        final credential = server['credential'];
        if (username is String && username.isNotEmpty) {
          next['username'] = username;
        }
        if (credential is String && credential.isNotEmpty) {
          next['credential'] = credential;
        }
        return next;
      }).toList();
      if (normalized.isEmpty) return fallback;
      return {
        'iceServers': normalized,
        'iceTransportPolicy': config['iceTransportPolicy'] == 'relay'
            ? 'relay'
            : 'all',
        'sdpSemantics': 'unified-plan',
      };
    } catch (e) {
      _log.warn('failed to load RTC config, using fallback', data: '$e');
      return fallback;
    }
  }

  Future<void> _warmupTurn(Map<String, dynamic> configuration) async {
    final iceServers = configuration['iceServers'];
    if (iceServers is! List) return;
    final hasTurn = iceServers.any((server) {
      if (server is! Map) return false;
      final urls = server['urls'];
      final list = urls is List ? urls : [urls];
      return list.any((url) => url is String && url.startsWith('turn'));
    });
    if (!hasTurn) return;

    RTCPeerConnection? warmupPc;
    final completed = Completer<void>();
    Timer? timeout;
    try {
      final warmupConfig = Map<String, dynamic>.from(configuration);
      warmupConfig['iceTransportPolicy'] = 'relay';
      warmupPc = await createPeerConnection(warmupConfig);
      warmupPc.onIceCandidate = (candidate) {
        final raw = candidate.candidate ?? '';
        if (!completed.isCompleted &&
            (raw.isEmpty || raw.contains(' typ relay '))) {
          completed.complete();
        }
      };
      await warmupPc.createDataChannel('turn-warmup', RTCDataChannelInit());
      final offer = await warmupPc.createOffer();
      await warmupPc.setLocalDescription(offer);
      timeout = Timer(const Duration(milliseconds: 2500), () {
        if (!completed.isCompleted) completed.complete();
      });
      await completed.future;
    } catch (e) {
      _log.warn('TURN warmup failed', data: '$e');
    } finally {
      timeout?.cancel();
      await warmupPc?.close();
    }
  }

  void _startInboundStatsWatch() {
    _inboundStatsTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_checkInboundStats());
    });
    unawaited(_checkInboundStats());
  }

  void _stopInboundStatsWatch() {
    _inboundStatsTimer?.cancel();
    _inboundStatsTimer = null;
  }

  Future<void> _checkInboundStats() async {
    final peerConnection = _peerConnection;
    if (_disposed || peerConnection == null) return;
    if (_relayFallbackUsed || _relayFallbackInFlight) return;
    if (_rtcConfiguration?['iceTransportPolicy'] == 'relay') return;
    if (!_hasExpectedRemoteMedia()) return;

    try {
      final reports = await peerConnection.getStats();
      var inboundReports = 0;
      var inboundBytes = 0;
      for (final report in reports) {
        if (report.type != 'inbound-rtp') continue;
        inboundReports += 1;
        inboundBytes += _intStat(report.values['bytesReceived']);
      }
      if (inboundReports == 0) return;

      final now = DateTime.now();
      final connectedAt = _connectedAt ?? now;
      if (now.difference(connectedAt) < _mediaDeadFallbackDelay) return;

      final previous = _lastInboundBytes;
      _lastInboundBytes = inboundBytes;
      if (previous == null || inboundBytes > previous) {
        _noInboundSince = null;
        return;
      }

      _noInboundSince ??= now;
      if (now.difference(_noInboundSince!) >= _mediaDeadFallbackDelay) {
        await _switchToRelayAndRestart('inbound-media-stalled');
      }
    } catch (e) {
      _log.warn('failed to inspect inbound stats', data: '$e');
    }
  }

  bool _hasExpectedRemoteMedia() => _seenRemoteTrackIds.isNotEmpty;

  int _intStat(Object? value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  Future<void> _switchToRelayAndRestart(String reason) async {
    final peerConnection = _peerConnection;
    final config = _rtcConfiguration;
    if (peerConnection == null || config == null) return;
    if (_relayFallbackInFlight || _relayFallbackUsed) return;

    _relayFallbackInFlight = true;
    _relayFallbackUsed = true;
    _noInboundSince = null;
    try {
      final relayConfig = Map<String, dynamic>.from(config);
      relayConfig['iceTransportPolicy'] = 'relay';
      _rtcConfiguration = relayConfig;
      await peerConnection.setConfiguration(relayConfig);
      unawaited(_warmupTurn(relayConfig));
      restartIce(reason);
    } catch (e) {
      _log.warn('failed to switch to relay ICE policy', data: '$e');
    } finally {
      _relayFallbackInFlight = false;
    }
  }

  Future<void> _negotiate(String reason) async {
    final peerConnection = _peerConnection;
    if (peerConnection == null) return;

    if (sessionId == null) {
      _log.debug(
        'delaying negotiation until sfu_joined',
        data: {'reason': reason},
      );
      return;
    }

    final signalingState =
        await peerConnection.getSignalingState() ??
        RTCSignalingState.RTCSignalingStateStable;

    if (_makingOffer ||
        signalingState != RTCSignalingState.RTCSignalingStateStable) {
      _log.debug(
        'delaying negotiation',
        data: {
          'reason': reason,
          'making_offer': _makingOffer,
          'signaling_state': signalingState.toString(),
        },
      );
      return;
    }

    try {
      _makingOffer = true;
      _log.info('creating offer', data: {'reason': reason});
      final offer = await peerConnection.createOffer();
      await peerConnection.setLocalDescription(offer);
      final sdpLength = offer.sdp?.length ?? 0;
      _log.info(
        'sending offer',
        data: {'type': offer.type, 'sdp_length': sdpLength},
      );
      transport.sfuSendOffer(roomId, offer.sdp!, offer.type!);
    } catch (e) {
      _log.error('negotiation failed', error: e, data: {'reason': reason});
    } finally {
      _makingOffer = false;
    }
  }

  Future<MediaStream?> _acquireLocalMedia() async {
    final audioConstraints = _audioConstraints(_selectedAudioInputId.value);
    final videoConstraints = _videoConstraints(_selectedVideoInputId.value);
    final attempts = <Map<String, dynamic>>[
      {'audio': audioConstraints, 'video': videoConstraints},
      {'audio': audioConstraints, 'video': false},
    ];

    Object? lastError;
    for (final constraints in attempts) {
      try {
        final stream = await navigator.mediaDevices.getUserMedia(constraints);
        _log.info(
          'acquired local media',
          data: _mediaSummary(stream, constraints),
        );
        return stream;
      } catch (e) {
        lastError = e;
        _log.warn(
          'getUserMedia attempt failed',
          data: {'constraints': constraints, 'error': e.toString()},
        );
      }
    }

    if (lastError != null) {
      throw lastError;
    }
    return null;
  }

  Map<String, dynamic> _mediaSummary(
    MediaStream stream,
    Map<String, dynamic> constraints,
  ) {
    return {
      'stream_id': stream.id,
      'audio_tracks': stream.getAudioTracks().length,
      'video_tracks': stream.getVideoTracks().length,
      'constraints': constraints,
    };
  }

  String? _candidateProtocol(String? candidate) {
    final parts = candidate?.split(RegExp(r'\s+')) ?? const <String>[];
    if (parts.length < 3) return null;
    return parts[2].toLowerCase();
  }

  String? _candidateToken(String? candidate, String marker) {
    final parts = candidate?.split(RegExp(r'\s+')) ?? const <String>[];
    final index = parts.indexOf(marker);
    if (index == -1 || index + 1 >= parts.length) return null;
    return parts[index + 1];
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
      if (deviceId != null)
        'optional': [
          {'sourceId': deviceId},
        ],
      'width': {'ideal': size.width},
      'height': {'ideal': size.height},
      'frameRate': {'ideal': 30},
    };
  }

  Future<void> refreshMediaDevices() async {
    try {
      _mediaDevices.value = await navigator.mediaDevices.enumerateDevices();
    } catch (e) {
      _log.warn('failed to enumerate media devices', data: e.toString());
    }
  }

  Future<void> selectAudioInput(String? deviceId) async {
    _selectedAudioInputId.value = deviceId;
    await _replaceLocalTrack('audio');
    if (deviceId != null && !kIsWeb) {
      try {
        await Helper.selectAudioInput(deviceId);
      } catch (e) {
        _log.warn('failed to select native audio input', data: e.toString());
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
        ? {
            'audio': _audioConstraints(_selectedAudioInputId.value),
            'video': false,
          }
        : {
            'audio': false,
            'video': _videoConstraints(_selectedVideoInputId.value),
          };

    _log.info(
      'replacing local track',
      data: {'kind': kind, 'constraints': constraints},
    );
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
        params.degradationPreference =
            RTCDegradationPreference.MAINTAIN_RESOLUTION;
        await sender.setParameters(params);
      }
    } else {
      _sendersByKind[kind] = await peerConnection.addTrack(
        newTrack,
        localStream,
      );
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
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
    }
    if (!addedKinds.contains('video')) {
      await _peerConnection!.addTransceiver(
        kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
        init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
      );
    }
  }

  Future<void> _configureMobileAudio() async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await Helper.setAndroidAudioConfiguration(
          AndroidAudioConfiguration.communication,
        );
        await Helper.setSpeakerphoneOn(true);
        return;
      }
      if (Platform.isIOS) {
        await Helper.ensureAudioSession();
        await Helper.setSpeakerphoneOn(true);
      }
    } catch (e) {
      _log.warn('failed to configure mobile audio route', data: e.toString());
    }
  }

  Future<void> handleSfuOffer(String sdp, String type) async {
    _log.info(
      'handling remote offer',
      data: {'type': type, 'sdp_length': sdp.length},
    );
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
      _log.warn('ignoring impolite offer due to collision');
      return;
    }

    if (offerCollision) {
      _log.warn('rolling back local offer for polite peer');
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
      _log.info(
        'sending answer',
        data: {'type': answer.type, 'sdp_length': answer.sdp?.length ?? 0},
      );
      transport.sfuSendAnswer(roomId, answer.sdp!, answer.type!);
    }
  }

  Future<void> handleSfuAnswer(String sdp, String type) async {
    final signalingState =
        await _peerConnection!.getSignalingState() ??
        RTCSignalingState.RTCSignalingStateClosed;
    _log.info(
      'handling remote answer',
      data: {
        'type': type,
        'sdp_length': sdp.length,
        'signaling_state': signalingState.toString(),
      },
    );
    if (signalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      _log.warn(
        'ignoring answer outside have-local-offer',
        data: {'signaling_state': signalingState.toString()},
      );
      return;
    }
    final description = RTCSessionDescription(sdp, type);
    await _peerConnection!.setRemoteDescription(description);
    _hasRemoteDescription = true;
    await _flushPendingRemoteCandidates();
  }

  Future<void> handleSfuIceCandidate(
    Map<String, dynamic>? candidateData,
  ) async {
    try {
      if (candidateData == null) {
        // End of candidates
        _log.debug('received remote end-of-candidates');
        return;
      }

      _log.debug(
        'handling remote ICE candidate',
        data: {
          'sdp_mid': candidateData['sdpMid'],
          'sdp_m_line_index': candidateData['sdpMLineIndex'],
          'candidate_length': candidateData['candidate']?.toString().length,
          'candidate_type': _candidateToken(
            candidateData['candidate']?.toString(),
            'typ',
          ),
        },
      );
      final candidate = RTCIceCandidate(
        candidateData['candidate'],
        candidateData['sdpMid'],
        candidateData['sdpMLineIndex'],
      );

      if (!_hasRemoteDescription) {
        _pendingRemoteCandidates.add(candidate);
        _log.debug('queued remote ICE candidate until remote description');
        return;
      }

      await _peerConnection!.addCandidate(candidate);
      _log.debug('added remote ICE candidate');
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
    _log.debug(
      'flushed remote ICE candidates',
      data: {'count': candidates.length},
    );
  }

  void handleSfuJoined(String sid) {
    if (_disposed) return;
    sessionId = sid;
    _log.info('joined SFU session', data: {'session_id': sid});

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

    final newParticipants = Map<String, Map<String, dynamic>>.from(
      _participants.value,
    );
    for (var p in participantsList) {
      if (p is! Map) continue;
      final userId = p['user_id'];
      if (userId == null) continue;

      final userState = Map<String, dynamic>.from(
        newParticipants[userId] ?? {},
      );
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
    final newParticipants = Map<String, Map<String, dynamic>>.from(
      _participants.value,
    );
    final userState = Map<String, dynamic>.from(newParticipants[userId] ?? {});
    userState.addAll(state);
    newParticipants[userId] = userState;
    _participants.value = newParticipants;
  }

  void handleParticipantMuted(String userId, String kind) {
    handleRemoteMediaState(userId, {
      kind == 'audio' ? 'mic_muted' : 'camera_off': true,
    });
  }

  void handleParticipantUnmuted(String userId, String kind) {
    handleRemoteMediaState(userId, {
      kind == 'audio' ? 'mic_muted' : 'camera_off': false,
    });
  }

  void handleActiveSpeakers(List<String> userIds) {
    if (_disposed) return;
    _activeSpeakers.value = userIds.toSet();
  }

  void handleParticipantLeft(String userId) {
    if (_disposed) return;
    _log.info('participant left', data: {'user_id': userId});
    final newParticipants = Map<String, Map<String, dynamic>>.from(
      _participants.value,
    );
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

  void restartIce([String reason = 'manual']) {
    _log.warn('requesting ICE restart', data: {'reason': reason});
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
    _iceRestartController.dispose();
    _stopInboundStatsWatch();
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
    _participants.dispose();
    _activeSpeakers.dispose();
    _remoteAudioTrackCount.dispose();
    _mediaDevices.dispose();
    _selectedAudioInputId.dispose();
    _selectedVideoInputId.dispose();
    _videoQuality.dispose();
    _stereoAudio.dispose();
  }
}
