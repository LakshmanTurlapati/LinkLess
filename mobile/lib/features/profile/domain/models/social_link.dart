import 'package:flutter/material.dart';

/// Supported social media platforms for user profiles.
///
/// Only these four platforms are allowed. The backend enforces
/// the same whitelist at the schema and service layers.
enum SocialPlatform {
  instagram,
  linkedin,
  x,
  snapchat;

  /// Human-readable name for display in the UI.
  String get displayName {
    switch (this) {
      case SocialPlatform.instagram:
        return 'Instagram';
      case SocialPlatform.linkedin:
        return 'LinkedIn';
      case SocialPlatform.x:
        return 'X';
      case SocialPlatform.snapchat:
        return 'Snapchat';
    }
  }

  /// Icon for the platform, shown in social link tiles.
  IconData get iconData {
    switch (this) {
      case SocialPlatform.instagram:
        return Icons.camera_alt_outlined;
      case SocialPlatform.linkedin:
        return Icons.business_center_outlined;
      case SocialPlatform.x:
        return Icons.alternate_email;
      case SocialPlatform.snapchat:
        return Icons.chat_bubble_outline;
    }
  }

  /// URL prefix for deep linking to user profiles on each platform.
  String get urlPrefix {
    switch (this) {
      case SocialPlatform.instagram:
        return 'https://instagram.com/';
      case SocialPlatform.linkedin:
        return 'https://linkedin.com/in/';
      case SocialPlatform.x:
        return 'https://x.com/';
      case SocialPlatform.snapchat:
        return 'https://snapchat.com/add/';
    }
  }

  /// Converts a string from the API to the corresponding enum value.
  static SocialPlatform fromString(String value) {
    switch (value.toLowerCase()) {
      case 'instagram':
        return SocialPlatform.instagram;
      case 'linkedin':
        return SocialPlatform.linkedin;
      case 'x':
        return SocialPlatform.x;
      case 'snapchat':
        return SocialPlatform.snapchat;
      default:
        throw ArgumentError('Unknown social platform: $value');
    }
  }
}

/// A social media link associated with a user profile.
///
/// Each link has a platform (from [SocialPlatform]) and a handle string.
/// The [id] is assigned by the backend and may be null for new links.
class SocialLink {
  final String? id;
  final SocialPlatform platform;
  final String handle;

  const SocialLink({
    this.id,
    required this.platform,
    required this.handle,
  });

  /// Creates a [SocialLink] from a JSON map returned by the API.
  factory SocialLink.fromJson(Map<String, dynamic> json) {
    return SocialLink(
      id: json['id'] as String?,
      platform: SocialPlatform.fromString(json['platform'] as String),
      handle: json['handle'] as String,
    );
  }

  /// Converts this link to a JSON map for sending to the API.
  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'platform': platform.name,
      'handle': handle,
    };
  }

  /// Creates a copy with optional field overrides.
  SocialLink copyWith({
    String? id,
    SocialPlatform? platform,
    String? handle,
  }) {
    return SocialLink(
      id: id ?? this.id,
      platform: platform ?? this.platform,
      handle: handle ?? this.handle,
    );
  }
}
