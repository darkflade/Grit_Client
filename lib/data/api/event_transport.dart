abstract class EventTransport {
  Future<void> connect();
  void disconnect();
  void listen(void Function(dynamic message) onMessage);
  void sendCommand(String type, Map<String, dynamic> data, {String? nonce});
  void close();
}
