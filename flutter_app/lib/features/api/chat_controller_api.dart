import 'dart:convert';
import 'dart:developer' as developer;

import 'package:final_assignment_front/features/model/agent_skill_info.dart';
import 'package:final_assignment_front/features/model/agent_stream_event.dart';
import 'package:final_assignment_front/features/model/chat_action_response.dart';
import 'package:final_assignment_front/i18n/api_error_localizers.dart';
import 'package:final_assignment_front/utils/helpers/api_exception.dart';
import 'package:final_assignment_front/utils/services/api_client.dart';
import 'package:final_assignment_front/utils/services/auth_token_store.dart';
import 'package:http/http.dart' as http;

final ApiClient defaultApiClient = ApiClient();

class ChatControllerApi {
  final ApiClient apiClient;

  ChatControllerApi([ApiClient? apiClient])
      : apiClient = apiClient ?? defaultApiClient;

  String _errorMessageOrHttpStatus(int statusCode, String body) {
    return body.isNotEmpty ? body : localizeHttpStatusError(statusCode);
  }

  Future<List<AgentSkillInfo>> apiAiSkillsGet() async {
    final response = await apiClient.invokeAPI(
      '/api/ai/skills',
      'GET',
      const [],
      null,
      await _authHeaders(),
      const {},
      null,
      const [],
    );

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessageOrHttpStatus(response.statusCode, decodedBody),
      );
    }

    final raw = jsonDecode(decodedBody);
    if (raw is! List) {
      return const [];
    }

    return raw
        .whereType<Map<String, dynamic>>()
        .map(AgentSkillInfo.fromJson)
        .toList();
  }

  Future<ChatActionResponse?> apiAiChatActionsGet(
    String message,
    bool webSearch,
  ) async {
    final response = await apiClient.invokeAPI(
      '/api/ai/chat/actions',
      'GET',
      [
        QueryParam('message', message),
        QueryParam('webSearch', webSearch.toString()),
      ],
      null,
      await _authHeaders(),
      const {},
      null,
      const [],
    );

    final decodedBody = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        _errorMessageOrHttpStatus(response.statusCode, decodedBody),
      );
    }

    if (decodedBody.isEmpty) {
      return null;
    }

    final raw = jsonDecode(decodedBody);
    return raw is Map<String, dynamic>
        ? ChatActionResponse.fromJson(raw)
        : null;
  }

  Stream<AgentStreamEvent> apiAiChatStream(
    String message,
    bool webSearch,
  ) async* {
    final base = apiClient.basePath.endsWith('/')
        ? apiClient.basePath.substring(0, apiClient.basePath.length - 1)
        : apiClient.basePath;

    final uri = Uri.parse(
      '$base/api/ai/chat?message=${Uri.encodeQueryComponent(message)}'
      '&webSearch=$webSearch',
    );

    final request = http.Request('GET', uri)
      ..headers.addAll({
        'Accept': 'text/event-stream',
        'Cache-Control': 'no-cache',
        ...await _authHeaders(),
      });

    final client = http.Client();
    try {
      final response = await client.send(request);
      if (response.statusCode >= 400) {
        throw ApiException(
          response.statusCode,
          localizeHttpStatusError(response.statusCode),
        );
      }

      final buffer = StringBuffer();
      await for (final chunk in response.stream.transform(utf8.decoder)) {
        buffer.write(chunk);
        var normalized = buffer.toString().replaceAll('\r\n', '\n');
        int separatorIndex = normalized.indexOf('\n\n');

        while (separatorIndex >= 0) {
          final rawEvent = normalized.substring(0, separatorIndex).trim();
          if (rawEvent.isNotEmpty) {
            final parsed = _parseEventBlock(rawEvent);
            if (parsed != null) {
              yield parsed;
            }
          }
          normalized = normalized.substring(separatorIndex + 2);
          separatorIndex = normalized.indexOf('\n\n');
        }

        buffer
          ..clear()
          ..write(normalized);
      }

      final trailing = buffer.toString().trim();
      if (trailing.isNotEmpty) {
        final parsed = _parseEventBlock(trailing);
        if (parsed != null) {
          yield parsed;
        }
      }
    } finally {
      client.close();
    }
  }

  AgentStreamEvent? _parseEventBlock(String block) {
    String eventName = 'message';
    final dataLines = <String>[];

    for (final rawLine in block.split('\n')) {
      final line = rawLine.trim();
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
      } else if (line.startsWith('data:')) {
        dataLines.add(line.substring(5).trim());
      }
    }

    if (dataLines.isEmpty) {
      return null;
    }

    final joinedData = dataLines.join('\n');
    try {
      final raw = jsonDecode(joinedData);
      if (raw is Map<String, dynamic>) {
        final parsed = AgentStreamEvent.fromJson(raw);
        return parsed.type.isEmpty
            ? AgentStreamEvent(
                type: eventName,
                content: parsed.content,
                searchResults: parsed.searchResults,
                actions: parsed.actions,
              )
            : parsed;
      }
    } catch (error) {
      developer.log(
        'Failed to parse SSE block: $joinedData, error: $error',
        name: 'ChatControllerApi',
      );
    }
    return null;
  }

  Future<Map<String, String>> _authHeaders() async {
    final headers = <String, String>{};
    final jwtToken = await AuthTokenStore.instance.getJwtToken();
    if (jwtToken != null && jwtToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $jwtToken';
    }
    return headers;
  }
}
