import 'package:flutter/material.dart';

/// Toggle switch for anonymous mode with explanation text.
///
/// When anonymous mode is enabled, the user's display name is hidden
/// and only their initials are shown to others. The profile photo
/// always remains visible.
class AnonymousModeToggle extends StatelessWidget {
  /// Whether anonymous mode is currently enabled.
  final bool isAnonymous;

  /// Called when the toggle is flipped.
  final ValueChanged<bool> onToggled;

  const AnonymousModeToggle({
    super.key,
    required this.isAnonymous,
    required this.onToggled,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      title: const Text('Anonymous Mode'),
      subtitle: const Text(
        'When enabled, your name is hidden and only your initials '
        'are shown to others. Your photo remains visible.',
      ),
      value: isAnonymous,
      onChanged: onToggled,
    );
  }
}
