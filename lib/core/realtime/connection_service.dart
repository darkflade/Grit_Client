import 'dart:async';
import 'dart:convert';

import '../../data/api/rest.dart';
import '../../features/calls/application/webrtc_sfu_service.dart';
import '../logging/app_logger.dart';
import 'event_transport.dart';

class ConnectionService {
  static const _log = AppLogger('ConnectionService');

  EventTransport eventTransport;
  final ApiClient apiClient;

  final _messageController = StreamController<dynamic>.broadcast();
  Stream<dynamic> get messageStream => _messageController.stream;

  bool _isConnected = false;
  bool get isConnected => _isConnected;

  bool _manualDisconnect = false;
  bool _isConnecting = false;
  bool _reconnectScheduled = false;
  int _reconnectAttempt = 0;
  Timer? _reconnectTimer;
  static const _connectTimeout = Duration(seconds: 10);

  final Set<String> _subscribedServerIds = {};
  final Map<String, String> _joinedRooms = {};
  final Map<String, WebRtcSfuService> _sfuSessions = {};

  ConnectionService(this.eventTransport, {required this.apiClient});

  Future<void> setTransport(EventTransport transport) async {
    final shouldReconnect = _isConnected || _isConnecting;
    final oldTransport = eventTransport;
    _cancelReconnect();
    _manualDisconnect = true;
    oldTransport.disconnect();
    eventTransport = transport;
    _isConnected = false;
    _isConnecting = false;
    _manualDisconnect = false;

    if (shouldReconnect) {
      await connect();
    } else {
      oldTransport.close();
    }
  }

  Future<void> connect() async {
    if (_isConnected || _isConnecting) return;
    _manualDisconnect = false;
    _isConnecting = true;
    try {
      await eventTransport.connect().timeout(_connectTimeout);
      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempt = 0;
      eventTransport.listen(
        (message) {
          _handleSfuSignaling(message);
          _messageController.add(message);
        },
        onDone: _handleTransportDone,
        onError: _handleTransportError,
      );
      _restoreSubscriptions();
    } catch (e) {
      _log.error('connect failed', error: e);
      _isConnected = false;
      _isConnecting = false;
      _scheduleReconnect();
    }
  }

  void disconnect() {
    _manualDisconnect = true;
    _cancelReconnect();
    eventTransport.disconnect();
    _isConnected = false;
    _isConnecting = false;
  }

  void sendCommand(String type, Map<String, dynamic> data, {String? nonce}) {
    if (!_isConnected) {
      _log.warn('cannot send command while disconnected', data: {'type': type});
      return;
    }
    eventTransport.sendCommand(type, data, nonce: nonce);
  }

  Future<Map<String, dynamic>> getRtcConfig({
    bool forceRelay = false,
    bool bypassCache = false,
  }) async {
    if (!_isConnected) {
      return apiClient.getRtcConfig();
    }

    final nonce =
        'ice:${DateTime.now().microsecondsSinceEpoch}:$_reconnectAttempt';
    final completer = Completer<Map<String, dynamic>>();
    late final StreamSubscription<dynamic> subscription;
    Timer? timeout;

    subscription = messageStream.listen((message) {
      try {
        final decoded = message is String ? jsonDecode(message) : message;
        if (decoded is! Map) return;
        if (decoded['nonce'] != nonce) return;
        final type = decoded['type'];
        if (type == 'error') {
          final data = decoded['data'];
          final error = data is Map
              ? (data['message'] ?? data['code'] ?? 'RTC config request failed')
              : 'RTC config request failed';
          if (!completer.isCompleted) {
            completer.completeError(Exception(error.toString()));
          }
          return;
        }
        if (type != 'ice_servers') return;
        final data = decoded['data'];
        if (data is Map) {
          if (!completer.isCompleted) {
            completer.complete(Map<String, dynamic>.from(data));
          }
        }
      } catch (e) {
        if (!completer.isCompleted) completer.completeError(e);
      }
    });

    timeout = Timer(const Duration(seconds: 3), () {
      if (!completer.isCompleted) {
        completer.completeError(Exception('RTC config realtime timeout'));
      }
    });

    sendCommand('get_ice_servers', {}, nonce: nonce);

    try {
      return await completer.future;
    } catch (e) {
      _log.warn(
        'RTC config over event transport failed, using REST',
        data: '$e',
      );
      return apiClient.getRtcConfig();
    } finally {
      timeout.cancel();
      await subscription.cancel();
    }
  }

  // Common commands abstracted
  void subscribeServer(String serverId) {
    _subscribedServerIds.add(serverId);
    eventTransport.subscribeServer(serverId);
  }

  void getServerParticipants(String serverId) {
    eventTransport.getServerParticipants(serverId);
  }

  void getServerRooms(String serverId) {
    eventTransport.getServerRooms(serverId);
  }

  void unsubscribeServer(String serverId) {
    _subscribedServerIds.remove(serverId);
    eventTransport.unsubscribeServer(serverId);
  }

  void joinRoom(String serverId, String roomId) {
    _joinedRooms[roomId] = serverId;
    eventTransport.joinRoom(serverId, roomId);
  }

  void leaveRoom(String roomId) {
    _joinedRooms.remove(roomId);
    eventTransport.leaveRoom(roomId);
  }

  void chat(
    String serverId,
    String roomId,
    String content, {
    String? nonce,
    List<String>? attachmentIds,
  }) {
    eventTransport.chat(
      serverId,
      roomId,
      content,
      nonce: nonce,
      attachmentIds: attachmentIds,
    );
  }

  void directMessage(
    String roomId,
    String content, {
    String? nonce,
    List<String>? attachmentIds,
  }) {
    eventTransport.directMessage(
      roomId,
      content,
      nonce: nonce,
      attachmentIds: attachmentIds,
    );
  }

  void directCallStart(String roomId) {
    eventTransport.directCallStart(roomId);
  }

  void directCallEnd(String roomId, String callId) {
    eventTransport.directCallEnd(roomId, callId);
  }

  void directCallDecline(String roomId, String callId) {
    eventTransport.directCallDecline(roomId, callId);
  }

  void sendTypingIndicator(
    String roomId,
    bool isTyping, {
    required String scope,
  }) {
    eventTransport.sendTypingIndicator(roomId, isTyping, scope: scope);
  }

  void pinMessage(String roomId, String messageId, {bool isDirect = false}) {
    eventTransport.pinMessage(roomId, messageId, isDirect: isDirect);
  }

  void unpinMessage(String roomId, String messageId, {bool isDirect = false}) {
    eventTransport.unpinMessage(roomId, messageId, isDirect: isDirect);
  }

  void markMessageRead(
    String roomId,
    String messageId, {
    bool isDirect = false,
  }) {
    eventTransport.markMessageRead(roomId, messageId, isDirect: isDirect);
  }

  // SFU Methods
  Future<WebRtcSfuService> joinSfuRoom(
    String roomId, {
    String? localUserId,
    bool useCommunicationAudio = false,
  }) async {
    if (_sfuSessions.containsKey(roomId)) {
      return _sfuSessions[roomId]!;
    }

    final sfu = WebRtcSfuService(
      roomId: roomId,
      transport: eventTransport,
      loadRtcConfig: getRtcConfig,
      localUserId: localUserId,
      useCommunicationAudio: useCommunicationAudio,
    );
    _sfuSessions[roomId] = sfu;
    await sfu.initialize();
    eventTransport.sfuJoin(roomId);
    return sfu;
  }

  Future<void> leaveSfuRoom(String roomId, String sessionId) async {
    final sfu = _sfuSessions.remove(roomId);
    final sid = sessionId.isNotEmpty ? sessionId : (sfu?.sessionId ?? "");
    eventTransport.sfuLeave(roomId, sid);
    await sfu?.dispose();
  }

  void _handleSfuSignaling(dynamic message) {
    try {
      final decoded = message is String ? jsonDecode(message) : message;
      final type = decoded['type'];
      final data = decoded['data'];

      if (type == null) return;

      // Filter messages that should be routed to an active SFU session
      const sfuSignalingTypes = {
        'sfu_joined',
        'sfu_offer',
        'sfu_answer',
        'sfu_ice_candidate',
        'sfu_media_state',
        'sfu_participant_muted',
        'sfu_participant_unmuted',
        'sfu_active_speakers',
        'sfu_left',
        'rtc_room_participants',
      };

      if (!sfuSignalingTypes.contains(type)) {
        // This is a room/direct event, not SFU signaling.
        return;
      }

      final roomId = _resolveSfuRoomId(decoded, data);
      if (roomId == null) {
        _log.warn(
          'cannot route SFU message without room_id',
          data: AppLogger.summarizeEventPayload(decoded),
        );
        return;
      }

      if (type != 'sfu_active_speakers' && type != 'sfu_ice_candidate') {
        _log.debug(
          'SFU <= $type',
          data: {'room_id': roomId, 'payload': _summarizeSfuData(data)},
        );
      }

      final sfu = _sfuSessions[roomId];
      if (sfu == null) {
        _log.warn('no active SFU session', data: {'room_id': roomId});
        return;
      }

      switch (type) {
        case 'sfu_joined':
          if (data is! Map) return;
          // For direct calls, session_id might be missing or in room_id.
          // We ensure we call handleSfuJoined to trigger negotiation.
          final sid = data['session_id'] ?? data['room_id'] ?? "";
          sfu.handleSfuJoined(sid.toString());
          break;
        case 'rtc_room_participants':
          if (data is! Map) return;
          sfu.handleRtcRoomParticipants(Map<String, dynamic>.from(data));
          break;
        case 'sfu_offer':
          if (data is! Map) return;
          final sdp = data['sdp'];
          final sdpType = data['type'];
          if (sdp is String && sdpType is String) {
            _runSfuFuture(sfu.handleSfuOffer(sdp, sdpType), type);
          } else {
            _log.warn('bad sfu_offer payload', data: _summarizeSfuData(data));
          }
          break;
        case 'sfu_answer':
          if (data is! Map) return;
          final sdp = data['sdp'];
          final sdpType = data['type'];
          if (sdp is String && sdpType is String) {
            _runSfuFuture(sfu.handleSfuAnswer(sdp, sdpType), type);
          } else {
            _log.warn('bad sfu_answer payload', data: _summarizeSfuData(data));
          }
          break;
        case 'sfu_ice_candidate':
          _runSfuFuture(
            sfu.handleSfuIceCandidate(
              data is Map ? Map<String, dynamic>.from(data) : null,
            ),
            type,
          );
          break;
        case 'sfu_media_state':
          if (data is! Map) return;
          final userId = data['user_id'];
          if (userId != null) {
            sfu.handleRemoteMediaState(userId, Map<String, dynamic>.from(data));
          }
          break;
        case 'sfu_participant_muted':
          if (data is! Map) return;
          final userId = data['user_id'];
          final kind = data['kind'];
          if (userId != null && kind != null) {
            sfu.handleParticipantMuted(userId, kind);
          }
          break;
        case 'sfu_participant_unmuted':
          if (data is! Map) return;
          final userId = data['user_id'];
          final kind = data['kind'];
          if (userId != null && kind != null) {
            sfu.handleParticipantUnmuted(userId, kind);
          }
          break;
        case 'sfu_active_speakers':
          if (data is! Map) return;
          final speakers = data['active_speakers'] ?? data['speakers'];
          if (speakers is List) {
            sfu.handleActiveSpeakers(
              speakers
                  .map((speaker) {
                    if (speaker is Map && speaker['user_id'] != null) {
                      return speaker['user_id'].toString();
                    }
                    return speaker.toString();
                  })
                  .where((userId) => userId.isNotEmpty)
                  .toList(),
            );
          }
          break;
        case 'sfu_left':
          if (data is! Map) return;
          final userId = data['user_id'];
          if (userId != null) {
            sfu.handleParticipantLeft(userId);
          }
          break;
      }
    } catch (e, stackTrace) {
      _log.error(
        'error handling SFU signaling',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  void _runSfuFuture(Future<void> future, String type) {
    unawaited(
      future.catchError((Object error, StackTrace stackTrace) {
        _log.error(
          'SFU handler failed',
          error: error,
          stackTrace: stackTrace,
          data: {'type': type},
        );
      }),
    );
  }

  String _summarizeSfuData(dynamic data) {
    if (data == null) return 'null';
    if (data is! Map) return data.toString();

    final type = data['type'];
    final sdp = data['sdp'];
    final candidate = data['candidate'];
    if (sdp is String) {
      return '{type=$type, sdpLength=${sdp.length}}';
    }
    if (candidate is String) {
      return '{candidateLength=${candidate.length}, sdpMid=${data['sdpMid']}, sdpMLineIndex=${data['sdpMLineIndex']}}';
    }
    return data.toString();
  }

  String? _resolveSfuRoomId(Map<dynamic, dynamic> decoded, dynamic data) {
    final topLevelRoomId = decoded['room_id'];
    if (topLevelRoomId is String && topLevelRoomId.isNotEmpty) {
      return topLevelRoomId;
    }

    if (data is Map) {
      final nestedRoomId = data['room_id'];
      if (nestedRoomId is String && nestedRoomId.isNotEmpty) {
        return nestedRoomId;
      }
    }

    if (_sfuSessions.length == 1) {
      return _sfuSessions.keys.single;
    }

    return null;
  }

  void _handleTransportDone() {
    _log.warn('transport closed');
    _isConnected = false;
    if (!_manualDisconnect) {
      _scheduleReconnect();
    }
  }

  void _handleTransportError(Object error) {
    _log.error('transport error', error: error);
    _isConnected = false;
    if (!_manualDisconnect) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_manualDisconnect ||
        _messageController.isClosed ||
        _reconnectScheduled) {
      return;
    }
    _reconnectScheduled = true;
    final seconds = _reconnectDelaySeconds();
    _log.info('reconnect scheduled', data: {'delay_seconds': seconds});
    _reconnectTimer = Timer(Duration(seconds: seconds), () {
      _reconnectScheduled = false;
      _reconnectAttempt++;
      unawaited(connect());
    });
  }

  int _reconnectDelaySeconds() {
    const delays = [1, 2, 5, 10, 20, 30];
    final index = _reconnectAttempt.clamp(0, delays.length - 1);
    return delays[index];
  }

  void _cancelReconnect() {
    _reconnectScheduled = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _reconnectAttempt = 0;
  }

  void _restoreSubscriptions() {
    for (final serverId in _subscribedServerIds) {
      eventTransport.subscribeServer(serverId);
    }
    for (final entry in _joinedRooms.entries) {
      eventTransport.joinRoom(entry.value, entry.key);
    }
    for (final entry in _sfuSessions.entries) {
      _log.info(
        'restoring SFU session after reconnect',
        data: {'room_id': entry.key},
      );
      entry.value.handleSignalingReconnected();
      eventTransport.sfuJoin(entry.key);
    }
  }

  void dispose() {
    _manualDisconnect = true;
    _cancelReconnect();
    final sessions = Map<String, WebRtcSfuService>.from(_sfuSessions);
    _sfuSessions.clear();
    for (final entry in sessions.entries) {
      eventTransport.sfuLeave(entry.key, entry.value.sessionId ?? "");
      unawaited(entry.value.dispose());
    }
    _messageController.close();
    disconnect();
  }
}
