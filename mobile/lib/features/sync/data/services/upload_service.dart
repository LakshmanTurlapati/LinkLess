import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:linkless/features/recording/data/database/app_database.dart';
import 'package:linkless/features/sync/data/services/conversation_api_service.dart';

/// Handles uploading conversation audio files to Tigris via presigned URLs.
///
/// Upload flow:
/// 1. Create conversation on backend (receives presigned upload URL)
/// 2. PUT audio file directly to Tigris presigned URL
/// 3. Confirm upload to trigger backend transcription pipeline
///
/// Follows the same presigned URL upload pattern as [PhotoUploadService]:
/// Stream.fromIterable for data, content-length header for Tigris compatibility.
class UploadService {
  final Dio _plainDio;
  final ConversationApiService _apiService;

  UploadService({
    required Dio plainDio,
    required ConversationApiService apiService,
  })  : _plainDio = plainDio,
        _apiService = apiService;

  /// Uploads a conversation's audio file to Tigris and confirms the upload.
  ///
  /// Throws [DioException] on network failures for retry logic in SyncEngine.
  /// Throws [FileSystemException] if the audio file does not exist.
  Future<void> uploadConversation(ConversationEntry conversation) async {
    // Step 1: Create conversation on backend to get presigned upload URL
    final createResponse = await _apiService.createConversation(
      localId: conversation.id,
      peerId: conversation.peerId,
      latitude: conversation.latitude,
      longitude: conversation.longitude,
      startedAt: conversation.startedAt,
      endedAt: conversation.endedAt,
      durationSeconds: conversation.durationSeconds,
    );

    // Step 2: Extract upload URL and conversation ID from response
    final uploadData = createResponse['upload'] as Map<String, dynamic>;
    final uploadUrl = uploadData['upload_url'] as String;
    final conversationData =
        createResponse['conversation'] as Map<String, dynamic>;
    final conversationId = conversationData['id'] as String;

    // Step 3: Read audio file bytes
    final audioFile = File(conversation.audioFilePath!);
    final fileBytes = await audioFile.readAsBytes();

    debugPrint(
      'UploadService: uploading ${fileBytes.length} bytes for conversation '
      '$conversationId',
    );

    // Step 4: PUT audio file to presigned Tigris URL
    // Uses Stream.fromIterable pattern matching PhotoUploadService
    await _plainDio.put(
      uploadUrl,
      data: Stream.fromIterable([fileBytes]),
      options: Options(
        headers: {
          Headers.contentLengthHeader: fileBytes.length,
          Headers.contentTypeHeader: 'audio/aac',
        },
      ),
    );

    // Step 5: Confirm upload to trigger transcription pipeline
    await _apiService.confirmUpload(conversationId);

    debugPrint(
      'UploadService: upload confirmed for conversation $conversationId',
    );
  }
}
