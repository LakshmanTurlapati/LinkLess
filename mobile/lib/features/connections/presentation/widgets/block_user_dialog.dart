import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/connections/presentation/providers/block_provider.dart';

/// Confirmation dialog for blocking a user.
///
/// Shows a warning message explaining the consequences of blocking,
/// with Cancel and Block buttons. The block action calls the backend
/// API, updates the local Drift cache, and refreshes the BLE filter.
class BlockUserDialog extends StatelessWidget {
  /// The user ID to block.
  final String userId;

  /// The display name of the user to block (shown in the dialog).
  final String displayName;

  /// The WidgetRef used to call the block action.
  final WidgetRef ref;

  const BlockUserDialog({
    super.key,
    required this.userId,
    required this.displayName,
    required this.ref,
  });

  /// Show the block user confirmation dialog.
  static Future<void> show({
    required BuildContext context,
    required String userId,
    required String displayName,
    required WidgetRef ref,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => BlockUserDialog(
        userId: userId,
        displayName: displayName,
        ref: ref,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text('Block $displayName?'),
      content: const Text(
        'They will not be able to connect with you and will not '
        'trigger proximity detection.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: theme.colorScheme.error,
            foregroundColor: theme.colorScheme.onError,
          ),
          onPressed: () async {
            Navigator.of(context).pop();
            await blockUser(ref, userId);
          },
          child: const Text('Block'),
        ),
      ],
    );
  }
}
