import 'package:image_picker/image_picker.dart';

import 'package:linkless/features/profile/data/services/photo_upload_service.dart';
import 'package:linkless/features/profile/data/services/profile_api_service.dart';
import 'package:linkless/features/profile/domain/models/social_link.dart';
import 'package:linkless/features/profile/domain/models/user_profile.dart';

/// Orchestrates profile operations across API service and photo upload service.
///
/// This is the single entry point that the view model calls.
/// It does not expose the underlying services directly.
class ProfileRepository {
  final ProfileApiService _apiService;
  final PhotoUploadService _photoService;

  ProfileRepository({
    required ProfileApiService apiService,
    required PhotoUploadService photoService,
  })  : _apiService = apiService,
        _photoService = photoService;

  /// Loads the current user's profile including social links.
  Future<UserProfile> loadProfile() async {
    final profile = await _apiService.getProfile();
    return profile;
  }

  /// Creates a new profile with the given display name.
  Future<UserProfile> createProfile(String displayName) async {
    final profile = await _apiService.createProfile(displayName);
    return profile;
  }

  /// Updates the profile with optional display name and anonymous mode changes.
  Future<UserProfile> updateProfile({
    String? displayName,
    bool? isAnonymous,
  }) async {
    final profile = await _apiService.updateProfile(
      displayName: displayName,
      isAnonymous: isAnonymous,
    );
    return profile;
  }

  /// Picks, crops, compresses, and uploads a profile photo.
  ///
  /// After upload, updates the profile with the new photo key.
  /// Returns the updated profile, or null if the user cancelled.
  Future<UserProfile?> uploadPhoto(ImageSource source) async {
    final photoKey = await _photoService.pickAndUploadPhoto(source);
    if (photoKey == null) return null;

    // Update the profile with the new photo key
    final profile = await _apiService.updateProfile(photoKey: photoKey);
    return profile;
  }

  /// Saves (upserts) the given social links.
  ///
  /// Replaces all existing links for the user with the provided list.
  /// Empty handles are filtered out before sending.
  Future<List<SocialLink>> saveSocialLinks(List<SocialLink> links) async {
    // Filter out links with empty handles
    final nonEmptyLinks =
        links.where((l) => l.handle.trim().isNotEmpty).toList();
    final savedLinks = await _apiService.upsertSocialLinks(nonEmptyLinks);
    return savedLinks;
  }

  /// Recovers lost image data after Android activity destruction.
  Future<XFile?> retrieveLostData() async {
    return _photoService.retrieveLostData();
  }
}
