import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:linkless/features/recording/data/database/conversation_dao.dart';
import 'package:linkless/features/sync/data/services/upload_service.dart';

/// Connectivity-aware engine that automatically uploads pending conversations.
///
/// Monitors network connectivity via connectivity_plus and processes the upload
/// queue whenever a connection becomes available. Handles individual upload
/// failures gracefully without blocking the rest of the queue.
///
/// Lifecycle:
/// - [initialize] subscribes to connectivity changes and triggers initial sync
/// - [retryFailed] resets failed uploads back to pending for re-processing
/// - [dispose] cancels the connectivity subscription
class SyncEngine {
  final ConversationDao _dao;
  final UploadService _uploadService;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  SyncEngine({
    required ConversationDao dao,
    required UploadService uploadService,
  })  : _dao = dao,
        _uploadService = uploadService;

  /// Starts monitoring connectivity and processes any pending uploads.
  ///
  /// Called once during provider initialization (fire-and-forget pattern
  /// matching RecordingService).
  Future<void> initialize() async {
    // Subscribe to connectivity changes
    _connectivitySub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      // If any connectivity result is not "none", we have a connection
      final hasConnection =
          results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) {
        _processPendingUploads();
      }
    });

    // Process any pending uploads immediately (we may already be online)
    await _processPendingUploads();
  }

  /// Processes all pending conversation uploads sequentially.
  ///
  /// Prevents concurrent runs via [_isSyncing] flag. Individual upload
  /// failures are caught and logged without stopping the queue -- the
  /// conversation is marked as 'failed' and processing continues.
  Future<void> _processPendingUploads() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final pendingConversations = await _dao.getPendingUploads();

      if (pendingConversations.isEmpty) {
        debugPrint('SyncEngine: no pending uploads');
        return;
      }

      debugPrint(
        'SyncEngine: processing ${pendingConversations.length} pending uploads',
      );

      for (final conversation in pendingConversations) {
        await _dao.updateSyncStatus(conversation.id, 'uploading');

        try {
          await _uploadService.uploadConversation(conversation);
          await _dao.updateSyncStatus(conversation.id, 'uploaded');
          debugPrint(
            'SyncEngine: uploaded conversation ${conversation.id}',
          );
        } on DioException catch (e) {
          await _dao.updateSyncStatus(conversation.id, 'failed');
          debugPrint(
            'SyncEngine: upload failed for ${conversation.id} '
            '-- ${e.message}',
          );
        } on Exception catch (e) {
          await _dao.updateSyncStatus(conversation.id, 'failed');
          debugPrint(
            'SyncEngine: upload failed for ${conversation.id} '
            '-- $e',
          );
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Resets all failed uploads back to pending and re-processes the queue.
  ///
  /// Call this to manually retry conversations that previously failed to
  /// upload (e.g., due to transient network errors or server issues).
  Future<void> retryFailed() async {
    final allConversations = await _dao.getAllConversations();
    final failedConversations = allConversations
        .where((c) => c.syncStatus == 'failed')
        .toList();

    for (final conversation in failedConversations) {
      await _dao.updateSyncStatus(conversation.id, 'pending');
    }

    debugPrint(
      'SyncEngine: reset ${failedConversations.length} failed uploads to '
      'pending',
    );

    await _processPendingUploads();
  }

  /// Cancels the connectivity subscription and stops monitoring.
  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    debugPrint('SyncEngine: disposed');
  }
}
