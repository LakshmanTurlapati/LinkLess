import 'package:flutter/material.dart';

import 'package:linkless/core/theme/app_colors.dart';
import 'package:linkless/features/profile/domain/models/social_link.dart';

/// A single row for editing a social media handle.
///
/// Displays the platform icon and name on the left, with a text field
/// for the handle on the right. Automatically strips leading @ from input.
class SocialLinkTile extends StatelessWidget {
  /// The social platform this tile represents.
  final SocialPlatform platform;

  /// The current handle value, or null if not set.
  final String? currentHandle;

  /// Called when the handle text changes.
  final ValueChanged<String> onChanged;

  /// Optional text editing controller for external form management.
  final TextEditingController? controller;

  const SocialLinkTile({
    super.key,
    required this.platform,
    this.currentHandle,
    required this.onChanged,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // Platform icon
          SizedBox(
            width: 40,
            child: Icon(
              platform.iconData,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),

          // Platform name and handle input
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                labelText: platform.displayName,
                hintText: '@username',
                prefixText: '@ ',
                filled: true,
                fillColor: AppColors.backgroundCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(
                    color: AppColors.accentBlue,
                    width: 2,
                  ),
                ),
                isDense: true,
              ),
              onChanged: (value) {
                // Strip leading @ in case user types it
                final cleaned = value.startsWith('@')
                    ? value.substring(1)
                    : value;
                onChanged(cleaned);
              },
            ),
          ),
        ],
      ),
    );
  }
}
