import 'chat_message.dart';

class MessagePage {
  final List<ChatMessage> messages;
  final String? nextCursor;
  final bool hasMore;
  final int limit;

  MessagePage({
    required this.messages,
    this.nextCursor,
    required this.hasMore,
    required this.limit,
  });

  factory MessagePage.fromJson(Map<String, dynamic> json) {
    final rawMessages = json['messages'] ?? json['items'] ?? json['data'];
    final messageList = rawMessages is List ? rawMessages : const [];
    return MessagePage(
      messages: messageList
          .whereType<Map>()
          .map((e) => ChatMessage.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
      limit: json['limit'] as int? ?? 25,
    );
  }
}
