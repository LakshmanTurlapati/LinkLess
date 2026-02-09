import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';
import 'package:linkless/features/profile/domain/models/user_profile.dart';

/// Fetches another user's profile by their userId.
///
/// Returns a [UserProfile] for the given peer. Uses the authenticated Dio
/// client to call GET /profile/:userId on the backend.
final peerProfileProvider =
    FutureProvider.family<UserProfile, String>((ref, userId) async {
  final dio = ref.watch(authenticatedDioProvider);
  final response = await dio.get('/profile/$userId');
  return UserProfile.fromJson(response.data as Map<String, dynamic>);
});
