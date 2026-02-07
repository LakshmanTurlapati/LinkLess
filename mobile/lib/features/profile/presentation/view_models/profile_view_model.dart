import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';
import 'package:linkless/features/profile/data/repositories/profile_repository.dart';
import 'package:linkless/features/profile/data/services/photo_upload_service.dart';
import 'package:linkless/features/profile/data/services/profile_api_service.dart';
import 'package:linkless/features/profile/domain/models/social_link.dart';
import 'package:linkless/features/profile/domain/models/user_profile.dart';

// ---------------------------------------------------------------------------
// Profile state
// ---------------------------------------------------------------------------

/// Immutable state for the profile feature.
class ProfileState {
  final UserProfile? profile;
  final bool isLoading;
  final bool isUploading;
  final bool isSaving;
  final String? error;

  const ProfileState({
    this.profile,
    this.isLoading = false,
    this.isUploading = false,
    this.isSaving = false,
    this.error,
  });

  ProfileState copyWith({
    UserProfile? profile,
    bool? isLoading,
    bool? isUploading,
    bool? isSaving,
    String? error,
  }) {
    return ProfileState(
      profile: profile ?? this.profile,
      isLoading: isLoading ?? this.isLoading,
      isUploading: isUploading ?? this.isUploading,
      isSaving: isSaving ?? this.isSaving,
      error: error,
    );
  }
}

// ---------------------------------------------------------------------------
// Profile notifier
// ---------------------------------------------------------------------------

/// Manages profile state and coordinates with [ProfileRepository].
class ProfileNotifier extends StateNotifier<ProfileState> {
  final ProfileRepository _repository;

  ProfileNotifier(this._repository) : super(const ProfileState());

  /// Loads the current user's profile from the backend.
  Future<void> loadProfile() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final profile = await _repository.loadProfile();
      state = state.copyWith(profile: profile, isLoading: false);
    } on DioException catch (e) {
      final message = _extractErrorMessage(e) ?? 'Failed to load profile';
      state = state.copyWith(isLoading: false, error: message);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to load profile',
      );
    }
  }

  /// Creates a new profile with the given display name.
  Future<bool> createProfile(String displayName) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final profile = await _repository.createProfile(displayName);
      state = state.copyWith(profile: profile, isLoading: false);
      return true;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e) ?? 'Failed to create profile';
      state = state.copyWith(isLoading: false, error: message);
      return false;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: 'Failed to create profile',
      );
      return false;
    }
  }

  /// Updates the display name.
  Future<bool> updateDisplayName(String name) async {
    state = state.copyWith(isSaving: true, error: null);
    try {
      final profile = await _repository.updateProfile(displayName: name);
      state = state.copyWith(profile: profile, isSaving: false);
      return true;
    } on DioException catch (e) {
      final message = _extractErrorMessage(e) ?? 'Failed to update name';
      state = state.copyWith(isSaving: false, error: message);
      return false;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        error: 'Failed to update name',
      );
      return false;
    }
  }

  /// Toggles anonymous mode and updates the profile.
  Future<void> toggleAnonymousMode() async {
    final current = state.profile;
    if (current == null) return;

    final newValue = !current.isAnonymous;

    // Optimistic update: flip the toggle immediately
    state = state.copyWith(
      profile: current.copyWith(isAnonymous: newValue),
    );

    try {
      final profile = await _repository.updateProfile(isAnonymous: newValue);
      state = state.copyWith(profile: profile);
    } on DioException catch (e) {
      // Revert optimistic update on failure
      final message =
          _extractErrorMessage(e) ?? 'Failed to toggle anonymous mode';
      state = state.copyWith(
        profile: current.copyWith(isAnonymous: !newValue),
        error: message,
      );
    } catch (e) {
      // Revert optimistic update on failure
      state = state.copyWith(
        profile: current.copyWith(isAnonymous: !newValue),
        error: 'Failed to toggle anonymous mode',
      );
    }
  }

  /// Picks, crops, compresses, and uploads a profile photo.
  Future<void> uploadPhoto(ImageSource source) async {
    state = state.copyWith(isUploading: true, error: null);
    try {
      final profile = await _repository.uploadPhoto(source);
      if (profile != null) {
        state = state.copyWith(profile: profile, isUploading: false);
      } else {
        // User cancelled the pick/crop flow
        state = state.copyWith(isUploading: false);
      }
    } on DioException catch (e) {
      final message = _extractErrorMessage(e) ?? 'Failed to upload photo';
      state = state.copyWith(isUploading: false, error: message);
    } catch (e) {
      state = state.copyWith(
        isUploading: false,
        error: 'Failed to upload photo',
      );
    }
  }

  /// Saves the provided social links to the backend.
  Future<bool> saveSocialLinks(List<SocialLink> links) async {
    state = state.copyWith(isSaving: true, error: null);
    try {
      final savedLinks = await _repository.saveSocialLinks(links);
      final current = state.profile;
      if (current != null) {
        state = state.copyWith(
          profile: current.copyWith(socialLinks: savedLinks),
          isSaving: false,
        );
      } else {
        state = state.copyWith(isSaving: false);
      }
      return true;
    } on DioException catch (e) {
      final message =
          _extractErrorMessage(e) ?? 'Failed to save social links';
      state = state.copyWith(isSaving: false, error: message);
      return false;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        error: 'Failed to save social links',
      );
      return false;
    }
  }

  /// Clears the current error.
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// Extracts a user-facing error message from a Dio exception.
  String? _extractErrorMessage(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic> && data.containsKey('detail')) {
      return data['detail'] as String?;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Provides [ProfileApiService] using the authenticated Dio client.
final profileApiServiceProvider = Provider<ProfileApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return ProfileApiService(dio);
});

/// Provides [PhotoUploadService] using the authenticated Dio client.
final photoUploadServiceProvider = Provider<PhotoUploadService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  final apiService = ref.watch(profileApiServiceProvider);
  return PhotoUploadService(dio: dio, apiService: apiService);
});

/// Provides [ProfileRepository].
final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final apiService = ref.watch(profileApiServiceProvider);
  final photoService = ref.watch(photoUploadServiceProvider);
  return ProfileRepository(apiService: apiService, photoService: photoService);
});

/// The main profile state provider.
///
/// Manages the full profile lifecycle: load, create, update, photo upload,
/// social links, and anonymous mode toggle.
final profileProvider =
    StateNotifierProvider<ProfileNotifier, ProfileState>((ref) {
  final repository = ref.watch(profileRepositoryProvider);
  return ProfileNotifier(repository);
});
