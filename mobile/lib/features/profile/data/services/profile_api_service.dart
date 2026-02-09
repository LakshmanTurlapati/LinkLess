import 'package:dio/dio.dart';

import 'package:linkless/features/profile/domain/models/social_link.dart';
import 'package:linkless/features/profile/domain/models/user_profile.dart';

/// Handles raw HTTP calls to all profile backend endpoints.
///
/// Maps 1:1 to the backend routes registered under /api/v1/profile.
/// Does NOT manage app state -- that is the responsibility of
/// [ProfileRepository] and the view model.
class ProfileApiService {
  final Dio _dio;

  ProfileApiService(this._dio);

  /// Creates a new profile with the given display name.
  ///
  /// POST /profile
  Future<UserProfile> createProfile(String displayName) async {
    final response = await _dio.post(
      '/profile',
      data: {'display_name': displayName},
    );
    return UserProfile.fromJson(response.data as Map<String, dynamic>);
  }

  /// Fetches the current user's profile.
  ///
  /// GET /profile
  Future<UserProfile> getProfile() async {
    final response = await _dio.get('/profile');
    return UserProfile.fromJson(response.data as Map<String, dynamic>);
  }

  /// Updates the current user's profile with the provided fields.
  ///
  /// Only non-null fields are sent in the request body.
  /// PATCH /profile
  Future<UserProfile> updateProfile({
    String? displayName,
    String? photoKey,
    bool? isAnonymous,
  }) async {
    final data = <String, dynamic>{};
    if (displayName != null) data['display_name'] = displayName;
    if (photoKey != null) data['photo_key'] = photoKey;
    if (isAnonymous != null) data['is_anonymous'] = isAnonymous;

    final response = await _dio.patch('/profile', data: data);
    return UserProfile.fromJson(response.data as Map<String, dynamic>);
  }

  /// Requests a presigned URL for uploading a profile photo.
  ///
  /// Returns a map containing 'upload_url' and 'photo_key'.
  /// POST /profile/photo/presign
  Future<Map<String, String>> getPresignedUrl() async {
    final response = await _dio.post('/profile/photo/presign');
    final data = response.data as Map<String, dynamic>;
    return {
      'upload_url': data['upload_url'] as String,
      'photo_key': data['photo_key'] as String,
    };
  }

  /// Replaces all social links for the current user.
  ///
  /// PUT /profile/social-links
  Future<List<SocialLink>> upsertSocialLinks(List<SocialLink> links) async {
    final response = await _dio.put(
      '/profile/social-links',
      data: links.map((l) => l.toJson()).toList(),
    );
    final list = response.data as List<dynamic>;
    return list
        .map((e) => SocialLink.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fetches all social links for the current user.
  ///
  /// GET /profile/social-links
  Future<List<SocialLink>> getSocialLinks() async {
    final response = await _dio.get('/profile/social-links');
    final list = response.data as List<dynamic>;
    return list
        .map((e) => SocialLink.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
