import 'package:linkless/features/profile/domain/models/social_link.dart';

/// Represents the user's profile data as returned by the backend.
///
/// Fields match the backend ProfileResponse schema:
/// - [displayName] is null when [isAnonymous] is true (masked by backend)
/// - [initials] are always available (derived from the stored name)
/// - [photoUrl] is the full URL to the profile photo on Tigris
/// - [socialLinks] contains up to 4 links (instagram, linkedin, x, snapchat)
class UserProfile {
  final String id;
  final String? displayName;
  final String? initials;
  final String? photoUrl;
  final bool isAnonymous;
  final List<SocialLink> socialLinks;

  const UserProfile({
    required this.id,
    this.displayName,
    this.initials,
    this.photoUrl,
    this.isAnonymous = false,
    this.socialLinks = const [],
  });

  /// Creates a [UserProfile] from a JSON map returned by the API.
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final linksJson = json['social_links'] as List<dynamic>?;
    return UserProfile(
      id: json['id'] as String,
      displayName: json['display_name'] as String?,
      initials: json['initials'] as String?,
      photoUrl: json['photo_url'] as String?,
      isAnonymous: json['is_anonymous'] as bool? ?? false,
      socialLinks: linksJson
              ?.map((e) => SocialLink.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  /// Converts this profile to a JSON map for serialization.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'display_name': displayName,
      'initials': initials,
      'photo_url': photoUrl,
      'is_anonymous': isAnonymous,
      'social_links': socialLinks.map((e) => e.toJson()).toList(),
    };
  }

  /// Creates a copy with optional field overrides.
  UserProfile copyWith({
    String? id,
    String? displayName,
    String? initials,
    String? photoUrl,
    bool? isAnonymous,
    List<SocialLink>? socialLinks,
  }) {
    return UserProfile(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      initials: initials ?? this.initials,
      photoUrl: photoUrl ?? this.photoUrl,
      isAnonymous: isAnonymous ?? this.isAnonymous,
      socialLinks: socialLinks ?? this.socialLinks,
    );
  }
}
