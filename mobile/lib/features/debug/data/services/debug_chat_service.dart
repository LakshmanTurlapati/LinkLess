import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

/// Service that sends messages to the backend AI debug chat endpoint and
/// streams back parsed SSE events.
///
/// Uses the authenticated [Dio] instance so the Bearer token is
/// automatically attached via [AuthInterceptor]. Each yielded map
/// contains an `_event` key (`token`, `done`, or `error`) plus the
/// parsed JSON payload from the SSE `data:` field.
class DebugChatService {
  final Dio _dio;

  /// Creates a [DebugChatService] with the provided authenticated [Dio].
  DebugChatService(this._dio);

  /// Sends [message] to `/debug/chat` and yields parsed SSE event maps.
  ///
  /// The response is consumed as a byte stream (`ResponseType.stream`).
  /// Partial UTF-8 chunks are buffered until a complete SSE event
  /// (delimited by double newline) is available.
  ///
  /// Each yielded map includes:
  /// - `_event`: the SSE event type (`token`, `done`, `error`, or
  ///   `message` if no explicit event type was specified)
  /// - All fields from the JSON `data:` payload
  Stream<Map<String, dynamic>> sendMessage(String message) async* {
    final response = await _dio.post<ResponseBody>(
      '/debug/chat',
      data: {'message': message},
      options: Options(
        responseType: ResponseType.stream,
        headers: {'Accept': 'text/event-stream'},
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    final stream = response.data!.stream;
    String buffer = '';

    await for (final chunk in stream) {
      buffer += const Utf8Decoder(allowMalformed: true).convert(chunk);
      // Normalize \r\n to \n (sse-starlette sends \r\n line endings)
      buffer = buffer.replaceAll('\r', '');

      while (buffer.contains('\n\n')) {
        final index = buffer.indexOf('\n\n');
        final raw = buffer.substring(0, index);
        buffer = buffer.substring(index + 2);

        final parsed = _parseSseEvent(raw);
        if (parsed != null) {
          yield parsed;
        }
      }
    }

    // Handle any trailing event without a final double newline
    if (buffer.trim().isNotEmpty) {
      final parsed = _parseSseEvent(buffer.trim());
      if (parsed != null) {
        yield parsed;
      }
    }
  }

  /// Parses a raw SSE event block into a map.
  ///
  /// Extracts the `event:` type and `data:` payload from newline-separated
  /// fields. Returns null if no data field is present or if JSON decoding
  /// fails.
  Map<String, dynamic>? _parseSseEvent(String raw) {
    String? eventType;
    String? data;

    for (final line in raw.split('\n')) {
      if (line.startsWith('event:')) {
        eventType = line.substring('event:'.length).trim();
      } else if (line.startsWith('data:')) {
        data = line.substring('data:'.length).trim();
      }
    }

    if (data == null) return null;

    try {
      final parsed = jsonDecode(data) as Map<String, dynamic>;
      parsed['_event'] = eventType ?? 'message';
      return parsed;
    } on FormatException {
      return null;
    }
  }
}
