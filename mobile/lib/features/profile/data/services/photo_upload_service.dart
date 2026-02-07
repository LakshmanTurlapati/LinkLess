import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

import 'package:linkless/features/profile/data/services/profile_api_service.dart';

/// Handles the full profile photo pipeline: pick, crop, compress, upload.
///
/// Flow: pick image -> crop to 1:1 -> compress to 512x512 JPEG ->
/// request presigned URL -> PUT to Tigris.
///
/// Key design decisions (from research):
/// - Do NOT set maxWidth/maxHeight on image_picker (can increase file size)
/// - Always specify CompressFormat.jpeg to handle iOS HEIC
/// - Request presigned URL AFTER image is ready (avoids expiry race condition)
/// - Handle Android activity destruction via retrieveLostData
class PhotoUploadService {
  final Dio _dio;
  final ProfileApiService _apiService;
  final ImagePicker _picker = ImagePicker();

  PhotoUploadService({
    required Dio dio,
    required ProfileApiService apiService,
  })  : _dio = dio,
        _apiService = apiService;

  /// Picks, crops, compresses, and uploads a profile photo.
  ///
  /// Returns the photo key (server-side object key) on success,
  /// or null if the user cancelled at any step.
  Future<String?> pickAndUploadPhoto(ImageSource source) async {
    // Step 1: Pick image (no maxWidth/maxHeight -- use compressor instead)
    final XFile? picked = await _picker.pickImage(source: source);
    if (picked == null) return null;

    // Step 2: Crop to square with locked 1:1 aspect ratio
    final CroppedFile? cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Profile Photo',
          lockAspectRatio: true,
          toolbarColor: Colors.blue,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: Colors.blue,
        ),
        IOSUiSettings(
          title: 'Crop Profile Photo',
          aspectRatioLockEnabled: true,
        ),
      ],
    );
    if (cropped == null) return null;

    // Step 3: Compress to 512x512 JPEG at quality 80
    // CRITICAL: Always specify format: CompressFormat.jpeg to handle iOS HEIC
    final Uint8List? compressedBytes =
        await FlutterImageCompress.compressWithFile(
      cropped.path,
      minWidth: 512,
      minHeight: 512,
      quality: 80,
      format: CompressFormat.jpeg,
    );
    if (compressedBytes == null) return null;

    // Step 4: Request presigned URL AFTER image is ready (avoids expiry)
    final presignData = await _apiService.getPresignedUrl();
    final uploadUrl = presignData['upload_url']!;
    final photoKey = presignData['photo_key']!;

    // Step 5: PUT compressed bytes to presigned URL on Tigris
    await _dio.put(
      uploadUrl,
      data: Stream.fromIterable([compressedBytes]),
      options: Options(
        headers: {
          Headers.contentLengthHeader: compressedBytes.length,
          Headers.contentTypeHeader: 'image/jpeg',
        },
      ),
    );

    // Step 6: Return the photo key for profile update
    return photoKey;
  }

  /// Recovers a photo that was picked before the Android activity was killed.
  ///
  /// Should be called in initState of screens that use the image picker.
  /// Returns the recovered XFile or null if no lost data.
  Future<XFile?> retrieveLostData() async {
    final LostDataResponse response = await _picker.retrieveLostData();
    if (response.isEmpty || response.file == null) {
      return null;
    }
    return response.file;
  }
}
