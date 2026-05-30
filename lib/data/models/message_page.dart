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
    return MessagePage(
      messages: (json['messages'] as List)
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
      hasMore: json['has_more'] as bool? ?? false,
      limit: json['limit'] as int? ?? 25,
    );
  }
}
