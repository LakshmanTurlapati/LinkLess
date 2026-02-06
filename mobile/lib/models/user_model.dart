class UserModel {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String? bio;
  final PrivacyMode privacyMode;
  final SocialLinks? socialLinks;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserModel({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    this.bio,
    this.privacyMode = PrivacyMode.public_,
    this.socialLinks,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String,
      photoUrl: json['photo_url'] as String?,
      bio: json['bio'] as String?,
      privacyMode: PrivacyMode.fromString(json['privacy_mode'] as String? ?? 'public'),
      socialLinks: json['social_links'] != null
          ? SocialLinks.fromJson(json['social_links'] as Map<String, dynamic>)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'photo_url': photoUrl,
      'bio': bio,
      'privacy_mode': privacyMode.value,
      'social_links': socialLinks?.toJson(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? displayName,
    String? photoUrl,
    String? bio,
    PrivacyMode? privacyMode,
    SocialLinks? socialLinks,
  }) {
    return UserModel(
      id: id,
      email: email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      bio: bio ?? this.bio,
      privacyMode: privacyMode ?? this.privacyMode,
      socialLinks: socialLinks ?? this.socialLinks,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}

enum PrivacyMode {
  public_('public'),
  anonymous('anonymous');

  final String value;
  const PrivacyMode(this.value);

  static PrivacyMode fromString(String value) {
    return PrivacyMode.values.firstWhere(
      (mode) => mode.value == value,
      orElse: () => PrivacyMode.public_,
    );
  }
}

class SocialLinks {
  final String? instagram;
  final String? twitter;
  final String? linkedin;
  final String? github;
  final String? website;

  const SocialLinks({
    this.instagram,
    this.twitter,
    this.linkedin,
    this.github,
    this.website,
  });

  factory SocialLinks.fromJson(Map<String, dynamic> json) {
    return SocialLinks(
      instagram: json['instagram'] as String?,
      twitter: json['twitter'] as String?,
      linkedin: json['linkedin'] as String?,
      github: json['github'] as String?,
      website: json['website'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (instagram != null) 'instagram': instagram,
      if (twitter != null) 'twitter': twitter,
      if (linkedin != null) 'linkedin': linkedin,
      if (github != null) 'github': github,
      if (website != null) 'website': website,
    };
  }

  bool get hasAny =>
      instagram != null ||
      twitter != null ||
      linkedin != null ||
      github != null ||
      website != null;
}
