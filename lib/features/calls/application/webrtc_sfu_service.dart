import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/logging/app_logger.dart';
import '../../../core/realtime/event_transport.dart';
import 'ice_restart_controller.dart';

// Unified Plan; Restart ICE; Perfect Negotiation; Trickle ICE; Transceivers; Polite Peer - Client; Server Authority

typedef RtcConfigLoader =
    Future<Map<String, dynamic>> Function({bool forceRelay, bool bypassCache});

const _mediaDeadFallbackDelay = Duration(seconds: 6);
const _rtcCleanupTimeout = Duration(seconds: 3);
const _turnWarmupReuseDelay = Duration(seconds: 30);

class RtcDebugSnapshot {
  final DateTime capturedAt;
  final Map<String, String> values;

  RtcDebugSnapshot({required this.capturedAt, required this.values});
}

class WebRtcSfuService {
  static Map<String, dynamic>? _cachedRtcConfiguration;
  static DateTime? _cachedRtcConfigurationExpiresAt;
  static Future<void>? _turnWarmupInFlight;

  final String roomId;
  final EventTransport transport;
  final RtcConfigLoader? loadRtcConfig;
  final String? localUserId;
  final bool useCommunicationAudio;
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
  final Map<String, MediaStreamTrack> _remoteAudioTracksById = {};
  final Set<String> _seenRemoteTrackIds = <String>{};
  final Set<String> _expectedRemoteTrackIds = <String>{};
  bool _hasRtcParticipantSnapshot = false;
  Map<String, dynamic>? _rtcConfiguration;
  RTCIceConnectionState _iceConnectionState =
      RTCIceConnectionState.RTCIceConnectionStateNew;
  RTCIceGatheringState _iceGatheringState =
      RTCIceGatheringState.RTCIceGatheringStateNew;
  RTCSignalingState _signalingState = RTCSignalingState.RTCSignalingStateStable;
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
    this.localUserId,
    this.useCommunicationAudio = false,
    this.isPolite = true,
  }) : _log = AppLogger('SFU.$roomId'),
       _iceRestartController = IceRestartController(
         roomId: roomId,
         logger: AppLogger('SFU.$roomId'),
       );

  Future<void> initialize() async {
  
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
    }

    final configuration = await _loadRtcConfiguration();
    _rtcConfiguration = configuration;
    unawaited(_warmupTurn(configuration));

    _peerConnection = await createPeerConnection(configuration);
    await _configureMobileAudio();
    _log.info('peer connection created', data: configuration);

    _peerConnection!.onSignalingState = (RTCSignalingState state) {
      _signalingState = state;
      _log.debug('signaling state changed', data: {'state': state.toString()});
    };

    _peerConnection!.onIceGatheringState = (RTCIceGatheringState state) {
      _iceGatheringState = state;
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
      transport.sfuSendIceCandidate(
        roomId,
        rawCandidate == null ? null : candidate.toMap(),
      );
    };

    _peerConnection!.onIceConnectionState = (RTCIceConnectionState state) {
      _iceConnectionState = state;
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
          if (_expectedRemoteTrackIds.isNotEmpty &&
              !_expectedRemoteTrackIds.contains(trackId)) {
            _log.debug(
              'ignoring stale remote audio track',
              data: {'track_id': trackId},
            );
            await _stopTrackQuietly(event.track);
            return;
          }
          final previousTrack = _remoteAudioTracksById[trackId];
          if (previousTrack != null && previousTrack != event.track) {
            await _stopTrackQuietly(previousTrack);
          }
          _remoteAudioTracksById[trackId] = event.track;
          event.track.onEnded = () => _removeRemoteAudioTrack(trackId);
        }
        _syncRemoteAudioTrackCount();
        try {
          await Helper.setVolume(1.0, event.track);
        } catch (e) {
          _log.warn('failed to set remote audio volume', data: e.toString());
        }
      }
      _onTrackController.add(event);
    };

    _peerConnection!.onRenegotiationNeeded = () async {
      await _negotiate("renegotiation-needed");
    };

    await _configureMobileAudio();
  }

  Future<Map<String, dynamic>> _loadRtcConfiguration({
    bool forceRelay = false,
    bool bypassCache = false,
  }) async {
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

    final now = DateTime.now();
    if (!bypassCache &&
        _cachedRtcConfiguration != null &&
        (_cachedRtcConfigurationExpiresAt == null ||
            _cachedRtcConfigurationExpiresAt!.isAfter(now))) {
      return _withIcePolicy(_cachedRtcConfiguration!, forceRelay);
    }

    final loader = loadRtcConfig;
    if (loader == null) return _withIcePolicy(fallback, forceRelay);

    try {
      final config = await loader(
        forceRelay: forceRelay,
        bypassCache: bypassCache,
      );
      final servers = config['iceServers'];
      if (servers is! List) return _withIcePolicy(fallback, forceRelay);
      final normalized = servers
          .whereType<Map>()
          .where((server) {
            final urls = server['urls'];
            return urls is String || (urls is List && urls.isNotEmpty);
          })
          .map((server) {
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
          })
          .toList();
      if (normalized.isEmpty) return _withIcePolicy(fallback, forceRelay);
      final normalizedConfig = {
        'iceServers': normalized,
        'iceTransportPolicy': config['iceTransportPolicy'] == 'relay'
            ? 'relay'
            : 'all',
        'sdpSemantics': 'unified-plan',
      };
      _cachedRtcConfiguration = normalizedConfig;
      _cachedRtcConfigurationExpiresAt = _resolveRtcConfigExpiry(config);
      return _withIcePolicy(normalizedConfig, forceRelay);
    } catch (e) {
      _log.warn('failed to load RTC config, using fallback', data: '$e');
      return _withIcePolicy(fallback, forceRelay);
    }
  }

  Map<String, dynamic> _withIcePolicy(
    Map<String, dynamic> configuration,
    bool forceRelay,
  ) {
    final next = Map<String, dynamic>.from(configuration);
    if (forceRelay) {
      next['iceTransportPolicy'] = 'relay';
    }
    return next;
  }

  DateTime _resolveRtcConfigExpiry(Map<String, dynamic> config) {
    final expiresAt = config['expiresAt'] ?? config['expires_at'];
    if (expiresAt is String) {
      final parsed = DateTime.tryParse(expiresAt);
      if (parsed != null) {
        return parsed.subtract(const Duration(minutes: 1));
      }
    }

    final ttlSeconds = config['ttlSeconds'] ?? config['ttl_seconds'];
    final ttl = ttlSeconds is num ? ttlSeconds.toInt() : 300;
    return DateTime.now().add(Duration(seconds: ttl < 60 ? 60 : ttl));
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
    if (_turnWarmupInFlight != null) return _turnWarmupInFlight;

    _turnWarmupInFlight = () async {
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
        await _closePeerConnectionQuietly(warmupPc);
        Timer(_turnWarmupReuseDelay, () {
          _turnWarmupInFlight = null;
        });
      }
    }();

    return _turnWarmupInFlight;
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
      final relayConfig = await _loadRtcConfiguration(
        forceRelay: true,
        bypassCache: true,
      );
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

    final previousParticipants = _participants.value;
    final newParticipants = <String, Map<String, dynamic>>{};
    final expectedRemoteTrackIds = <String>{};
    for (var p in participantsList) {
      if (p is! Map) continue;
      final userId = p['user_id']?.toString();
      if (userId == null) continue;

      final userState = Map<String, dynamic>.from(
        previousParticipants[userId] ?? {},
      );
      userState['online'] = p['online'] == true;
      userState['connection_state'] = p['connection_state'];
      userState['track_count'] = p['track_count'];
      userState['track_ids'] = p['track_ids'];

      // If the participant has tracks, we can assume they are not fully muted
      // unless sfu_media_state says otherwise later.
      final trackCount = p['track_count'] ?? 0;
      if (trackCount > 0 && userState['mic_muted'] == null) {
        userState['mic_muted'] = false;
      }

      newParticipants[userId] = userState;
      if (localUserId != null && userId == localUserId) continue;
      final trackIds = p['track_ids'];
      if (trackIds is List) {
        expectedRemoteTrackIds.addAll(
          trackIds.map((id) => id.toString()).where((id) => id.isNotEmpty),
        );
      }
    }
    _participants.value = newParticipants;
    _hasRtcParticipantSnapshot = true;
    _expectedRemoteTrackIds
      ..clear()
      ..addAll(expectedRemoteTrackIds);
    _pruneRemoteTracks();
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
    final trackIds = newParticipants[userId]?['track_ids'];
    newParticipants.remove(userId);
    _participants.value = newParticipants;
    if (trackIds is List) {
      for (final trackId in trackIds) {
        _expectedRemoteTrackIds.remove(trackId.toString());
      }
    }

    final newSpeakers = Set<String>.from(_activeSpeakers.value);
    newSpeakers.remove(userId);
    _activeSpeakers.value = newSpeakers;
    _pruneRemoteTracks();
  }

  void _removeRemoteAudioTrack(String trackId) {
    if (_disposed) return;
    _remoteAudioTracksById.remove(trackId);
    _syncRemoteAudioTrackCount();
  }

  void _syncRemoteAudioTrackCount() {
    if (_disposed) return;
    final expectedCount = !_hasRtcParticipantSnapshot
        ? _remoteAudioTracksById.length
        : _remoteAudioTracksById.keys
              .where(_expectedRemoteTrackIds.contains)
              .length;
    _remoteAudioTrackCount.value = expectedCount;
  }

  void _pruneRemoteTracks() {
    if (!_hasRtcParticipantSnapshot) {
      _syncRemoteAudioTrackCount();
      return;
    }
    final staleIds = _remoteAudioTracksById.keys
        .where((trackId) => !_expectedRemoteTrackIds.contains(trackId))
        .toList();
    for (final trackId in staleIds) {
      final track = _remoteAudioTracksById.remove(trackId);
      if (track != null) {
        unawaited(_stopTrackQuietly(track));
      }
    }
    _seenRemoteTrackIds.removeWhere(
      (trackId) => !_expectedRemoteTrackIds.contains(trackId),
    );
    _syncRemoteAudioTrackCount();
  }

  Future<void> addTrack(MediaStreamTrack track, MediaStream stream) async {
    await _peerConnection!.addTrack(track, stream);
  }

  Future<void> removeTrack(RTCRtpSender sender) async {
    await _peerConnection!.removeTrack(sender);
  }

  void restartIce([String reason = 'manual']) {
    if (_disposed) return;
    _log.warn('requesting ICE restart', data: {'reason': reason});
    transport.sfuSendIceRestart(roomId);
  }

  Future<RtcDebugSnapshot> collectDebugSnapshot() async {
    final values = <String, String>{
      'room': roomId,
      'session': sessionId ?? '-',
      'connection': _connectionStateValue.value.name,
      'ice': _iceConnectionState.name,
      'gathering': _iceGatheringState.name,
      'signaling': _signalingState.name,
      'ice policy': _rtcConfiguration?['iceTransportPolicy']?.toString() ?? '-',
      'relay fallback': _relayFallbackUsed ? 'used' : 'not used',
      'remote audio': _remoteAudioTrackCount.value.toString(),
      'expected tracks': _expectedRemoteTrackIds.length.toString(),
      'tracked remote': _remoteAudioTracksById.length.toString(),
      'participants': _participants.value.length.toString(),
      'local tracks': (_localStream?.getTracks().length ?? 0).toString(),
    };

    final peerConnection = _peerConnection;
    if (peerConnection == null || _disposed) {
      values['peer connection'] = 'closed';
      return RtcDebugSnapshot(capturedAt: DateTime.now(), values: values);
    }

    try {
      values['senders'] = (await peerConnection.getSenders()).length.toString();
      values['receivers'] = (await peerConnection.getReceivers()).length
          .toString();
    } catch (e) {
      values['sender/receiver read'] = e.toString();
    }

    try {
      final reports = await peerConnection.getStats().timeout(
        const Duration(seconds: 2),
      );
      final aggregate = _aggregateRtcStats(reports);
      values.addAll(aggregate);
    } catch (e) {
      values['stats error'] = e.toString();
    }

    return RtcDebugSnapshot(capturedAt: DateTime.now(), values: values);
  }

  Map<String, String> _aggregateRtcStats(Iterable<StatsReport> reports) {
    var inboundAudioBytes = 0;
    var inboundAudioPackets = 0;
    var inboundAudioLost = 0;
    double? maxJitterSeconds;
    var outboundBytes = 0;
    var outboundPackets = 0;
    double? rttSeconds;
    double? availableOutgoingBitrate;
    String? localCandidate;
    String? remoteCandidate;
    String? selectedPairState;

    final reportsById = {for (final report in reports) report.id: report};

    for (final report in reports) {
      final values = Map<String, dynamic>.from(report.values);
      if (report.type == 'inbound-rtp' &&
          values['kind']?.toString() == 'audio') {
        inboundAudioBytes += _intStat(values['bytesReceived']);
        inboundAudioPackets += _intStat(values['packetsReceived']);
        inboundAudioLost += _intStat(values['packetsLost']);
        final jitter = _doubleStat(values['jitter']);
        if (jitter != null &&
            (maxJitterSeconds == null || jitter > maxJitterSeconds)) {
          maxJitterSeconds = jitter;
        }
      }
      if (report.type == 'outbound-rtp') {
        outboundBytes += _intStat(values['bytesSent']);
        outboundPackets += _intStat(values['packetsSent']);
      }
      if (report.type == 'candidate-pair' && _isSelectedCandidatePair(values)) {
        selectedPairState = values['state']?.toString();
        rttSeconds =
            _doubleStat(values['currentRoundTripTime']) ??
            _doubleStat(values['totalRoundTripTime']);
        availableOutgoingBitrate = _doubleStat(
          values['availableOutgoingBitrate'],
        );
        localCandidate = _candidateSummary(
          _reportValues(reportsById[values['localCandidateId']?.toString()]),
        );
        remoteCandidate = _candidateSummary(
          _reportValues(reportsById[values['remoteCandidateId']?.toString()]),
        );
      }
    }

    final packetLossPercent = inboundAudioPackets + inboundAudioLost == 0
        ? 0.0
        : (inboundAudioLost / (inboundAudioPackets + inboundAudioLost)) * 100;

    return {
      'rtt': rttSeconds == null
          ? '-'
          : '${(rttSeconds * 1000).toStringAsFixed(0)} ms',
      'jitter': maxJitterSeconds == null
          ? '-'
          : '${(maxJitterSeconds * 1000).toStringAsFixed(1)} ms',
      'packet loss': '${packetLossPercent.toStringAsFixed(1)}%',
      'in audio packets': inboundAudioPackets.toString(),
      'in audio lost': inboundAudioLost.toString(),
      'in audio bytes': inboundAudioBytes.toString(),
      'out packets': outboundPackets.toString(),
      'out bytes': outboundBytes.toString(),
      'out bitrate': availableOutgoingBitrate == null
          ? '-'
          : '${(availableOutgoingBitrate / 1000).toStringAsFixed(0)} kbps',
      'candidate pair': selectedPairState ?? '-',
      'local candidate': localCandidate ?? '-',
      'remote candidate': remoteCandidate ?? '-',
    };
  }

  Map<String, dynamic>? _reportValues(StatsReport? report) {
    if (report == null) return null;
    return Map<String, dynamic>.from(report.values);
  }

  bool _isSelectedCandidatePair(Map<String, dynamic> values) {
    return values['selected'] == true ||
        values['nominated'] == true ||
        values['state']?.toString() == 'succeeded';
  }

  double? _doubleStat(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  String? _candidateSummary(Map<String, dynamic>? values) {
    if (values == null) return null;
    final type =
        values['candidateType'] ??
        values['candidate_type'] ??
        values['type'] ??
        values['relayProtocol'];
    final protocol = values['protocol'] ?? values['transport'];
    final address = values['address'] ?? values['ip'];
    final port = values['port'];
    return [?type, ?protocol, ?address, ?port].join(' ');
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
    if (_disposed) return;
    _disposed = true;
    _iceRestartController.dispose();
    _stopInboundStatsWatch();
    final peerConnection = _peerConnection;
    final localStream = _localStream;
    _peerConnection = null;
    _localStream = null;

    await _detachLocalSenders(peerConnection);
    await _disposeLocalStream(localStream);
    await _disposeRemoteTracks();
    await _closePeerConnectionQuietly(peerConnection);
    await _resetMobileAudioRoute();

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

  Future<void> _detachLocalSenders(RTCPeerConnection? peerConnection) async {
    if (peerConnection == null) return;
    try {
      final senders = await peerConnection.getSenders().timeout(
        _rtcCleanupTimeout,
      );
      for (final sender in senders) {
        try {
          await sender.replaceTrack(null).timeout(_rtcCleanupTimeout);
        } catch (e) {
          _log.warn('failed to detach sender track', data: e.toString());
        }
      }
    } catch (e) {
      _log.warn('failed to list senders during cleanup', data: e.toString());
    } finally {
      _sendersByKind.clear();
    }
  }

  Future<void> _disposeLocalStream(MediaStream? stream) async {
    if (stream == null) return;
    for (final track in List<MediaStreamTrack>.from(stream.getTracks())) {
      await _stopTrackQuietly(track);
    }
    try {
      await stream.dispose().timeout(_rtcCleanupTimeout);
    } catch (e) {
      _log.warn('failed to dispose local stream', data: e.toString());
    }
    if (!_localStreamController.isClosed) {
      _localStreamController.add(null);
    }
  }

  Future<void> _disposeRemoteTracks() async {
    final tracks = List<MediaStreamTrack>.from(_remoteAudioTracksById.values);
    _remoteAudioTracksById.clear();
    _seenRemoteTrackIds.clear();
    _remoteAudioTrackCount.value = 0;
    for (final track in tracks) {
      await _stopTrackQuietly(track);
    }
  }

  Future<void> _stopTrackQuietly(MediaStreamTrack track) async {
    try {
      track.onEnded = null;
      track.onMute = null;
      track.onUnMute = null;
      track.enabled = false;
    } catch (_) {}
    try {
      await track.stop().timeout(_rtcCleanupTimeout);
    } catch (e) {
      _log.warn(
        'failed to stop media track',
        data: {'track_id': track.id, 'kind': track.kind, 'error': e.toString()},
      );
    }
  }

  Future<void> _closePeerConnectionQuietly(
    RTCPeerConnection? peerConnection,
  ) async {
    if (peerConnection == null) return;
    try {
      await peerConnection.close().timeout(_rtcCleanupTimeout);
    } catch (e) {
      _log.warn('failed to close peer connection', data: e.toString());
    }
  }

  Future<void> _resetMobileAudioRoute() async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        await Helper.setSpeakerphoneOn(false).timeout(_rtcCleanupTimeout);
      }
    } catch (e) {
      _log.warn('failed to reset mobile audio route', data: e.toString());
    }
  }
}
