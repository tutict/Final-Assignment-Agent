import 'package:final_assignment_front/features/model/chat_action.dart';

class AgentStreamEvent {
  final String type;
  final String? content;
  final List<String> searchResults;
  final List<ChatAction> actions;

  const AgentStreamEvent({
    required this.type,
    this.content,
    this.searchResults = const [],
    this.actions = const [],
  });

  factory AgentStreamEvent.fromJson(Map<String, dynamic> json) {
    final rawSearchResults = json['searchResults'];
    final rawActions = json['actions'];

    return AgentStreamEvent(
      type: json['type'] as String? ?? 'message',
      content: json['content'] as String?,
      searchResults: rawSearchResults is List
          ? rawSearchResults.map((item) => item.toString()).toList()
          : const [],
      actions: rawActions is List
          ? rawActions
              .whereType<Map<String, dynamic>>()
              .map(ChatAction.fromJson)
              .toList()
          : const [],
    );
  }
}
