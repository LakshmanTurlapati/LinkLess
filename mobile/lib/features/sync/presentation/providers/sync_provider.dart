import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:linkless/features/auth/presentation/providers/auth_provider.dart';
import 'package:linkless/features/recording/presentation/providers/database_provider.dart';
import 'package:linkless/features/sync/data/services/conversation_api_service.dart';
import 'package:linkless/features/sync/data/services/sync_engine.dart';
import 'package:linkless/features/sync/data/services/upload_service.dart';

/// Provides the [ConversationApiService] using the authenticated Dio instance.
final conversationApiServiceProvider = Provider<ConversationApiService>((ref) {
  final dio = ref.watch(authenticatedDioProvider);
  return ConversationApiService(dio);
});

/// Provides the [UploadService] with a plain Dio (no base URL) for direct
/// Tigris uploads and the API service for conversation creation/confirmation.
final uploadServiceProvider = Provider<UploadService>((ref) {
  final apiService = ref.watch(conversationApiServiceProvider);
  // Plain Dio with no base URL for direct presigned URL uploads to Tigris
  final plainDio = Dio();
  return UploadService(
    plainDio: plainDio,
    apiService: apiService,
  );
});

/// Provides the [SyncEngine] that automatically uploads pending conversations.
///
/// Initialization is fire-and-forget (matching RecordingService pattern).
/// The engine monitors connectivity and processes the upload queue when
/// a connection becomes available.
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final dao = ref.watch(conversationDaoProvider);
  final uploadService = ref.watch(uploadServiceProvider);

  final syncEngine = SyncEngine(
    dao: dao,
    uploadService: uploadService,
  );

  // Fire-and-forget initialization (matching RecordingService pattern)
  syncEngine.initialize();

  ref.onDispose(() => syncEngine.dispose());

  return syncEngine;
});
