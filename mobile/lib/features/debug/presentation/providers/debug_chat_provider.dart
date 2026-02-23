import 'dart:async';
import 'dart:math' show min;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';
import 'package:linkless/features/debug/data/services/debug_chat_service.dart';

// ---------------------------------------------------------------------------
// Chat status enum
// ---------------------------------------------------------------------------

/// Lifecycle states for a single AI debug chat exchange.
enum ChatStatus {
  /// No message sent yet, or previous exchange has been cleared.
  idle,

  /// Message sent, waiting for the first SSE event from the backend.
  waiting,

  /// Receiving token events; the AI response is being assembled.
  streaming,

  /// The stream completed successfully with a `done` event.
  done,

  /// An error occurred (network, backend, or stream-level).
  error,
}

// ---------------------------------------------------------------------------
// Chat state
// ---------------------------------------------------------------------------

/// Immutable snapshot of the debug chat exchange.
///
/// Holds the user's message, the accumulated AI response (built from
/// individual `token` SSE events), status metadata from the `done` event,
/// and any error information.
class ChatState {
  final ChatStatus status;
  final String userMessage;
  final String aiResponse;
  final String? errorMessage;
  final int? tokenCount;
  final int? latencyMs;
  final String? modelId;

  const ChatState({
    this.status = ChatStatus.idle,
    this.userMessage = '',
    this.aiResponse = '',
    this.errorMessage,
    this.tokenCount,
    this.latencyMs,
    this.modelId,
  });

  ChatState copyWith({
    ChatStatus? status,
    String? userMessage,
    String? aiResponse,
    String? errorMessage,
    int? tokenCount,
    int? latencyMs,
    String? modelId,
  }) {
    return ChatState(
      status: status ?? this.status,
      userMessage: userMessage ?? this.userMessage,
      aiResponse: aiResponse ?? this.aiResponse,
      errorMessage: errorMessage ?? this.errorMessage,
      tokenCount: tokenCount ?? this.tokenCount,
      latencyMs: latencyMs ?? this.latencyMs,
      modelId: modelId ?? this.modelId,
    );
  }
}

// ---------------------------------------------------------------------------
// Chat notifier
// ---------------------------------------------------------------------------

/// Manages the debug chat state machine and stream lifecycle.
///
/// Transitions: idle -> waiting -> streaming -> done | error
///
/// Calling [sendMessage] while streaming cancels the in-flight stream
/// and starts a new exchange. Calling [cancel] returns to idle.
class ChatNotifier extends StateNotifier<ChatState> {
  final DebugChatService _chatService;
  StreamSubscription<Map<String, dynamic>>? _subscription;

  ChatNotifier(this._chatService) : super(const ChatState());

  /// Sends [message] to the AI debug chat endpoint.
  ///
  /// Cancels any in-flight stream before starting. Resets accumulated
  /// response and metadata, then subscribes to the SSE event stream.
  void sendMessage(String message) {
    _subscription?.cancel();
    _subscription = null;

    state = ChatState(
      status: ChatStatus.waiting,
      userMessage: message,
    );

    _subscription = _chatService.sendMessage(message).listen(
      (event) {
        final eventType = event['_event'] as String? ?? 'message';

        switch (eventType) {
          case 'token':
            final content = event['content'] as String? ?? '';
            state = state.copyWith(
              status: ChatStatus.streaming,
              aiResponse: state.aiResponse + content,
            );
          case 'done':
            state = state.copyWith(
              status: ChatStatus.done,
              tokenCount: event['token_count'] as int?,
              latencyMs: event['latency_ms'] as int?,
              modelId: event['model_id'] as String?,
            );
          case 'error':
            state = state.copyWith(
              status: ChatStatus.error,
              errorMessage: event['error'] as String? ?? 'Unknown stream error',
            );
        }
      },
      onError: (Object error) {
        state = state.copyWith(
          status: ChatStatus.error,
          errorMessage: _mapDioError(error),
        );
      },
    );
  }

  /// Cancels any in-flight stream and resets to idle.
  void cancel() {
    _subscription?.cancel();
    _subscription = null;
    state = const ChatState();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }

  /// Maps [error] to a human-readable message.
  ///
  /// Handles common Dio exception types without exposing raw HTTP status
  /// codes or stack traces to the UI.
  static String _mapDioError(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;

      if (statusCode == 404) {
        return 'AI chat unavailable (backend not in debug mode)';
      }

      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.receiveTimeout:
        case DioExceptionType.sendTimeout:
          return 'Connection timed out';
        case DioExceptionType.connectionError:
          return 'Cannot reach server';
        default:
          break;
      }
    }

    final message = error.toString();
    final truncated = message.substring(0, min(100, message.length));
    return 'Unexpected error: $truncated';
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Provides a [DebugChatService] backed by the authenticated Dio instance.
final debugChatServiceProvider = Provider<DebugChatService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return DebugChatService(dio);
});

/// Provides [ChatNotifier] with auto-dispose so the stream subscription
/// is cleaned up when the debug panel widget tree is unmounted.
final debugChatProvider =
    StateNotifierProvider.autoDispose<ChatNotifier, ChatState>((ref) {
  final chatService = ref.watch(debugChatServiceProvider);
  return ChatNotifier(chatService);
});
