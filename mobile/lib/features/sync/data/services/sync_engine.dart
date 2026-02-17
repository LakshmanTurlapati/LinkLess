import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:linkless/features/recording/data/database/conversation_dao.dart';
import 'package:linkless/features/sync/data/services/conversation_api_service.dart';
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
  final ConversationApiService _apiService;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _pollTimer;
  bool _isSyncing = false;
  bool _isPolling = false;

  static const _pollInterval = Duration(seconds: 30);

  SyncEngine({
    required ConversationDao dao,
    required UploadService uploadService,
    required ConversationApiService apiService,
  })  : _dao = dao,
        _uploadService = uploadService,
        _apiService = apiService;

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

    // Start periodic polling for pending uploads and transcription completion
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      _processPendingUploads();
      _pollTranscriptionStatus();
    });
    // Run an initial poll immediately
    _pollTranscriptionStatus();
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
          final serverId =
              await _uploadService.uploadConversation(conversation);
          await _dao.updateServerId(conversation.id, serverId);
          await _dao.updateSyncStatus(conversation.id, 'uploaded');
          debugPrint(
            'SyncEngine: uploaded conversation ${conversation.id} '
            '(server: $serverId)',
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

  /// Polls the backend for transcription completion on uploaded conversations.
  ///
  /// Checks each conversation with 'uploaded' status against the backend.
  /// If the backend returns a non-null transcript, updates status to 'completed'.
  /// If the backend indicates failure, updates status to 'failed'.
  /// Network errors are logged and skipped (retried next cycle).
  Future<void> _pollTranscriptionStatus() async {
    if (_isPolling) return;
    _isPolling = true;

    try {
      final uploadedConversations = await _dao.getUploadedConversations();

      if (uploadedConversations.isEmpty) return;

      debugPrint(
        'SyncEngine: polling transcription status for '
        '${uploadedConversations.length} conversation(s)',
      );

      for (final conversation in uploadedConversations) {
        final idForApi = conversation.serverId ?? conversation.id;
        try {
          final detail =
              await _apiService.getConversationDetail(idForApi);
          final transcript = detail['transcript'];
          final status = detail['status'] as String?;

          if (transcript != null &&
              transcript.toString().isNotEmpty &&
              transcript.toString() != '[]') {
            await _dao.updateSyncStatus(conversation.id, 'completed');
            debugPrint(
              'SyncEngine: transcription completed for ${conversation.id}',
            );
          } else if (status == 'failed' || status == 'error') {
            await _dao.updateSyncStatus(conversation.id, 'failed');
            debugPrint(
              'SyncEngine: transcription failed for ${conversation.id}',
            );
          }
        } on DioException catch (e) {
          debugPrint(
            'SyncEngine: poll error for ${conversation.id} -- ${e.message}',
          );
          // Skip this conversation, try again next cycle
        } on Exception catch (e) {
          debugPrint(
            'SyncEngine: poll error for ${conversation.id} -- $e',
          );
        }
      }
    } finally {
      _isPolling = false;
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

  /// Triggers an immediate sync cycle from the debug UI.
  ///
  /// Useful after manually resetting a conversation's status to 'pending'.
  Future<void> syncNow() async {
    await _processPendingUploads();
  }

  /// Polls the backend for a single conversation's transcription status.
  ///
  /// Used by the debug UI to manually check if a transcript is ready
  /// without waiting for the next automatic poll cycle.
  Future<void> pollSingleConversation(String localId) async {
    try {
      final conversation = await _dao.getConversation(localId);
      if (conversation == null) {
        debugPrint('SyncEngine: pollSingle -- conversation $localId not found');
        return;
      }

      final idForApi = conversation.serverId ?? conversation.id;
      final detail = await _apiService.getConversationDetail(idForApi);
      final transcript = detail['transcript'];
      final status = detail['status'] as String?;

      if (transcript != null &&
          transcript.toString().isNotEmpty &&
          transcript.toString() != '[]') {
        await _dao.updateSyncStatus(localId, 'completed');
        debugPrint(
          'SyncEngine: pollSingle -- transcription completed for $localId',
        );
      } else if (status == 'failed' || status == 'error') {
        await _dao.updateSyncStatus(localId, 'failed');
        debugPrint(
          'SyncEngine: pollSingle -- transcription failed for $localId',
        );
      } else {
        debugPrint(
          'SyncEngine: pollSingle -- still processing $localId',
        );
      }
    } catch (e) {
      debugPrint('SyncEngine: pollSingle error for $localId -- $e');
    }
  }

  /// Cancels the connectivity subscription, poll timer, and stops monitoring.
  void dispose() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    debugPrint('SyncEngine: disposed');
  }
}
