import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Circular avatar widget with a camera/gallery picker.
///
/// Displays the user's profile photo (from [photoUrl]) or falls back
/// to showing [initials] or a camera icon placeholder.
///
/// Tapping the avatar opens a bottom sheet with options to take a photo
/// or choose from the gallery. The selected [ImageSource] is passed
/// to [onPhotoSelected] for the parent to handle the upload.
class AvatarPicker extends StatelessWidget {
  /// Current profile photo URL, or null if no photo.
  final String? photoUrl;

  /// User initials to display when no photo is available.
  final String? initials;

  /// Whether a photo upload is in progress.
  final bool isUploading;

  /// Called when the user selects a photo source (camera or gallery).
  final ValueChanged<ImageSource> onPhotoSelected;

  /// Diameter of the avatar circle.
  final double size;

  const AvatarPicker({
    super.key,
    this.photoUrl,
    this.initials,
    this.isUploading = false,
    required this.onPhotoSelected,
    this.size = 120,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: isUploading ? null : () => _showSourcePicker(context),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Main avatar circle
          CircleAvatar(
            radius: size / 2,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            backgroundImage: photoUrl != null
                ? CachedNetworkImageProvider(photoUrl!)
                : null,
            child: _buildAvatarContent(theme),
          ),

          // Upload progress indicator
          if (isUploading)
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: theme.colorScheme.primary,
              ),
            ),

          // Camera badge (bottom-right corner)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: theme.colorScheme.surface,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.camera_alt,
                size: 18,
                color: theme.colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the inner content of the avatar (initials or placeholder icon).
  Widget? _buildAvatarContent(ThemeData theme) {
    // If there is a photo, backgroundImage handles display
    if (photoUrl != null) return null;

    // Show initials if available
    if (initials != null && initials!.isNotEmpty) {
      return Text(
        initials!,
        style: TextStyle(
          fontSize: size * 0.3,
          fontWeight: FontWeight.w600,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    // Fallback: camera placeholder icon
    return Icon(
      Icons.person,
      size: size * 0.4,
      color: theme.colorScheme.onSurfaceVariant,
    );
  }

  /// Shows a bottom sheet with camera and gallery options.
  void _showSourcePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (bottomSheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.of(bottomSheetContext).pop();
                  onPhotoSelected(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.of(bottomSheetContext).pop();
                  onPhotoSelected(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
