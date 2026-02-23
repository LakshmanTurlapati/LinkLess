import 'dart:math' show pi, sin;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/debug/presentation/providers/debug_chat_provider.dart';

/// AI Chat section for the debug panel.
///
/// Shows a single message/response pair at a time. The user types a test
/// message, taps send, and sees the AI response stream token-by-token with
/// a typing indicator while waiting for the first token. Metadata (token
/// count, latency, model) is displayed after the stream completes.
///
/// Tapping send while streaming cancels the current stream and sends the
/// new message. Only the latest exchange is shown -- previous exchanges
/// are cleared on new send.
class AiChatSection extends ConsumerStatefulWidget {
  const AiChatSection({super.key});

  @override
  ConsumerState<AiChatSection> createState() => _AiChatSectionState();
}

class _AiChatSectionState extends ConsumerState<AiChatSection> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _controller.text.trim();
    final notifier = ref.read(debugChatProvider.notifier);
    final status = ref.read(debugChatProvider).status;

    final isActive =
        status == ChatStatus.waiting || status == ChatStatus.streaming;

    if (isActive && text.isNotEmpty) {
      // Cancel current stream and immediately send the new message.
      notifier.cancel();
      notifier.sendMessage(text);
      _controller.clear();
    } else if (isActive && text.isEmpty) {
      // Just cancel the current stream.
      notifier.cancel();
    } else if (text.isNotEmpty) {
      // Normal send.
      notifier.sendMessage(text);
      _controller.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatState = ref.watch(debugChatProvider);
    final isActive = chatState.status == ChatStatus.waiting ||
        chatState.status == ChatStatus.streaming;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.backgroundCard,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            'AI Chat',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),

          // Chat bubbles area
          if (chatState.userMessage.isNotEmpty) ...[
            _UserBubble(text: chatState.userMessage),
            const SizedBox(height: 8),
          ],

          if (chatState.status == ChatStatus.waiting)
            const _TypingIndicator(),

          if (chatState.status == ChatStatus.streaming ||
              chatState.status == ChatStatus.done)
            _AiBubble(text: chatState.aiResponse),

          if (chatState.status == ChatStatus.error)
            _ErrorBubble(
              text: chatState.errorMessage ?? 'Unknown error',
            ),

          // Metadata row (only when done)
          if (chatState.status == ChatStatus.done)
            _MetadataRow(
              tokenCount: chatState.tokenCount,
              latencyMs: chatState.latencyMs,
              modelId: chatState.modelId,
            ),

          const SizedBox(height: 12),

          // Input row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  maxLength: 2000,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.backgroundDarker,
                    hintText: 'Test a message...',
                    hintStyle: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 13,
                    ),
                    counterText: '',
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: const BorderSide(
                        color: AppColors.accentBlue,
                        width: 0.5,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _handleSend(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  isActive ? Icons.stop_circle_outlined : Icons.send,
                  color: isActive ? AppColors.error : AppColors.accentBlue,
                  size: 24,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 40,
                  minHeight: 40,
                ),
                onPressed: _handleSend,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat bubble widgets
// ---------------------------------------------------------------------------

/// User message bubble, right-aligned with accent blue background.
class _UserBubble extends StatelessWidget {
  final String text;

  const _UserBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.accentBlue,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// AI response bubble, left-aligned with dark background and subtle border.
class _AiBubble extends StatelessWidget {
  final String text;

  const _AiBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.backgroundDarker,
          border: Border.all(
            color: AppColors.border,
            width: 0.5,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// Error bubble, left-aligned with red left border for visual emphasis.
class _ErrorBubble extends StatelessWidget {
  final String text;

  const _ErrorBubble({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.backgroundDarker,
          border: const Border(
            left: BorderSide(
              color: AppColors.error,
              width: 3,
            ),
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.error,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Typing indicator
// ---------------------------------------------------------------------------

/// Three animated dots that pulse while waiting for the first AI token.
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.backgroundDarker,
          border: Border.all(
            color: AppColors.border,
            width: 0.5,
          ),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
        ),
        child: AnimatedBuilder(
          animation: _animController,
          builder: (context, _) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                // Stagger each dot by 0.2 in the animation cycle.
                final offset = index * 0.2;
                final t = (_animController.value + offset) % 1.0;
                // Scale pulses between 0.8 and 1.4 using a sine wave.
                final scale = 0.8 + 0.6 * sin(t * pi);
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppColors.textSecondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              }),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Metadata row
// ---------------------------------------------------------------------------

/// Shows token count, latency, and model ID after a completed AI response.
class _MetadataRow extends StatelessWidget {
  final int? tokenCount;
  final int? latencyMs;
  final String? modelId;

  const _MetadataRow({
    this.tokenCount,
    this.latencyMs,
    this.modelId,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = tokenCount != null ? '$tokenCount tokens' : '? tokens';
    final latency = latencyMs != null ? '${latencyMs}ms' : '?ms';
    final model = modelId ?? 'unknown';

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '$tokens  --  $latency  --  $model',
          style: const TextStyle(
            color: AppColors.textTertiary,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
