import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:linkless/core/theme/app_colors.dart';

/// Renders circular face-pin marker images as PNG [Uint8List] for use as
/// Mapbox PointAnnotation icons.
///
/// Uses [dart:ui] Canvas rendering directly (no mounted widget required).
/// For known non-anonymous peers with a photo URL, the photo is downloaded
/// and drawn clipped to a circle. For anonymous peers or when photo download
/// fails, initials are rendered in a colored circle instead.
class MarkerImageService {
  MarkerImageService._();

  /// Extra padding around the pin for the glow effect.
  static const double _glowPadding = 12.0;

  /// Renders a circular face-pin marker image with a glow effect.
  ///
  /// Returns a PNG-encoded [Uint8List] suitable for Mapbox PointAnnotation
  /// image data. The image is ([size] + glow padding) x ([size] + glow padding) pixels.
  ///
  /// - [photoUrl]: URL to the peer's profile photo (downloaded and cropped).
  /// - [initials]: Fallback text rendered when no photo is available.
  /// - [isAnonymous]: When true, forces initials rendering even if photoUrl
  ///   is provided.
  /// - [size]: Diameter of the circular pin in logical pixels.
  static Future<Uint8List> renderFacePin({
    String? photoUrl,
    String? initials,
    bool isAnonymous = false,
    double size = 64.0,
  }) async {
    final totalSize = size + _glowPadding;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, totalSize, totalSize));
    final center = Offset(totalSize / 2, totalSize / 2);
    final radius = size / 2;

    // Border width
    const borderWidth = 3.0;
    final innerRadius = radius - borderWidth;

    // Draw glow ring
    canvas.drawCircle(
      center,
      radius + 6,
      Paint()
        ..color = const Color(0x80FFFFFF)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );

    // Try to load photo for non-anonymous peers
    ui.Image? photo;
    if (!isAnonymous && photoUrl != null && photoUrl.isNotEmpty) {
      photo = await _downloadImage(photoUrl);
    }

    if (photo != null) {
      // Draw white background circle
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = const Color(0xFFFFFFFF),
      );

      // Draw photo clipped to inner circle
      canvas.save();
      final clipPath = Path()
        ..addOval(Rect.fromCircle(center: center, radius: innerRadius));
      canvas.clipPath(clipPath);

      // Scale and center the photo to fill the circle
      final srcSize = math.min(photo.width, photo.height).toDouble();
      final srcOffset = Offset(
        (photo.width - srcSize) / 2,
        (photo.height - srcSize) / 2,
      );
      final srcRect = Rect.fromLTWH(srcOffset.dx, srcOffset.dy, srcSize, srcSize);
      final dstRect = Rect.fromCircle(center: center, radius: innerRadius);
      canvas.drawImageRect(photo, srcRect, dstRect, Paint());
      canvas.restore();

      // Draw colored border
      canvas.drawCircle(
        center,
        radius - borderWidth / 2,
        Paint()
          ..color = AppColors.accentBlue
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );
    } else {
      // Initials fallback rendering
      final isUnknown = isAnonymous || (initials == null || initials.isEmpty);
      final bgColor = isUnknown
          ? const Color(0xFF9E9E9E) // Grey for unknown/anonymous
          : AppColors.accentBlue; // Blue for known peers

      // Draw filled background circle
      canvas.drawCircle(
        center,
        radius,
        Paint()..color = const Color(0xFFFFFFFF),
      );
      canvas.drawCircle(
        center,
        innerRadius,
        Paint()..color = bgColor,
      );

      // Draw initials text
      final displayText = (initials != null && initials.isNotEmpty)
          ? initials
          : '?';
      final textStyle = ui.TextStyle(
        color: const Color(0xFFFFFFFF),
        fontSize: size * 0.35,
        fontWeight: FontWeight.bold,
      );
      final paragraphBuilder = ui.ParagraphBuilder(
        ui.ParagraphStyle(
          textAlign: TextAlign.center,
          maxLines: 1,
        ),
      )
        ..pushStyle(textStyle)
        ..addText(displayText);

      final paragraph = paragraphBuilder.build()
        ..layout(ui.ParagraphConstraints(width: totalSize));

      final textOffset = Offset(
        0,
        center.dy - paragraph.height / 2,
      );
      canvas.drawParagraph(paragraph, textOffset);

      // Draw border
      canvas.drawCircle(
        center,
        radius - borderWidth / 2,
        Paint()
          ..color = bgColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = borderWidth,
      );
    }

    // Convert to PNG bytes
    final picture = recorder.endRecording();
    final image = await picture.toImage(totalSize.toInt(), totalSize.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    if (byteData == null) {
      throw StateError('Failed to encode marker image to PNG');
    }

    return byteData.buffer.asUint8List();
  }

  /// Downloads an image from [url] and decodes it to a [ui.Image].
  ///
  /// Returns null if the download or decode fails for any reason.
  static Future<ui.Image?> _downloadImage(String url) async {
    try {
      final completer = Completer<ui.Image?>();

      // Use ImmutableBuffer and ImageDescriptor for network image loading
      final uri = Uri.parse(url);
      final httpClient = HttpClient();
      final request = await httpClient.getUrl(uri);
      final response = await request.close();

      if (response.statusCode != 200) {
        httpClient.close();
        return null;
      }

      final bytes = await _consolidateResponse(response);
      httpClient.close();

      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      completer.complete(frame.image);

      return completer.future;
    } catch (_) {
      // Any failure (network, decode, etc.) returns null to trigger
      // initials fallback
      return null;
    }
  }

  /// Consolidates an [HttpClientResponse] stream into a single [Uint8List].
  static Future<Uint8List> _consolidateResponse(
    HttpClientResponse response,
  ) async {
    final chunks = <List<int>>[];
    await for (final chunk in response) {
      chunks.add(chunk);
    }
    final totalLength = chunks.fold<int>(0, (sum, chunk) => sum + chunk.length);
    final result = Uint8List(totalLength);
    var offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }
}
