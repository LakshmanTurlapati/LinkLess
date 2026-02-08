import 'package:linkless/features/profile/domain/models/social_link.dart';

/// A social link exchanged as part of a mutual connection.
///
/// Contains the platform name and handle. Unlike [SocialLink], this does not
/// have an id because it represents a read-only snapshot of the peer's shared
/// links at connection time.
class ExchangedSocialLink {
  final String platform;
  final String handle;

  const ExchangedSocialLink({
    required this.platform,
    required this.handle,
  });

  /// Creates an [ExchangedSocialLink] from a JSON map.
  factory ExchangedSocialLink.fromJson(Map<String, dynamic> json) {
    return ExchangedSocialLink(
      platform: json['platform'] as String,
      handle: json['handle'] as String,
    );
  }

  /// Returns the full URL for the social platform profile.
  ///
  /// Uses the same URL prefixes as [SocialPlatform.urlPrefix]:
  /// - instagram: https://instagram.com/{handle}
  /// - linkedin: https://linkedin.com/in/{handle}
  /// - x: https://x.com/{handle}
  /// - snapchat: https://snapchat.com/add/{handle}
  String get platformUrl {
    switch (platform.toLowerCase()) {
      case 'instagram':
        return 'https://instagram.com/$handle';
      case 'linkedin':
        return 'https://linkedin.com/in/$handle';
      case 'x':
        return 'https://x.com/$handle';
      case 'snapchat':
        return 'https://snapchat.com/add/$handle';
      default:
        return 'https://$platform.com/$handle';
    }
  }

  /// Returns the [SocialPlatform] enum for icon/display name lookup.
  ///
  /// Returns null if the platform string is not recognized.
  SocialPlatform? get socialPlatform {
    try {
      return SocialPlatform.fromString(platform);
    } catch (_) {
      return null;
    }
  }
}

/// An established connection between the current user and a peer.
///
/// Created when both users have mutually accepted a connection request
/// for a shared conversation. Contains the peer's display info and their
/// exchanged social links.
class Connection {
  final String id;
  final String peerId;
  final String? peerDisplayName;
  final String? peerInitials;
  final String? peerPhotoUrl;
  final bool peerIsAnonymous;
  final List<ExchangedSocialLink> socialLinks;
  final String conversationId;
  final DateTime connectedAt;

  const Connection({
    required this.id,
    required this.peerId,
    this.peerDisplayName,
    this.peerInitials,
    this.peerPhotoUrl,
    this.peerIsAnonymous = false,
    required this.socialLinks,
    required this.conversationId,
    required this.connectedAt,
  });

  /// Creates a [Connection] from a JSON map returned by the API.
  factory Connection.fromJson(Map<String, dynamic> json) {
    final linksJson = json['social_links'] as List<dynamic>? ?? [];
    final links = linksJson
        .map((e) => ExchangedSocialLink.fromJson(e as Map<String, dynamic>))
        .toList();

    return Connection(
      id: json['id'] as String,
      peerId: json['peer_id'] as String,
      peerDisplayName: json['peer_display_name'] as String?,
      peerInitials: json['peer_initials'] as String?,
      peerPhotoUrl: json['peer_photo_url'] as String?,
      peerIsAnonymous: json['peer_is_anonymous'] as bool? ?? false,
      socialLinks: links,
      conversationId: json['conversation_id'] as String,
      connectedAt: DateTime.parse(json['connected_at'] as String),
    );
  }

  /// Display name for the peer, falling back to initials or 'Anonymous'.
  String get displayName {
    if (peerIsAnonymous) {
      return peerInitials ?? 'Anonymous';
    }
    return peerDisplayName ?? peerInitials ?? 'Unknown';
  }
}
