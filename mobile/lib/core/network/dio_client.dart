import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:linkless/core/config/app_config.dart';

/// Creates and configures a Dio HTTP client instance.
///
/// Base URL comes from [AppConfig.apiBaseUrl].
/// Logging interceptor is added in debug mode only.
/// Auth token interceptors will be added in Phase 2.
Dio createDioClient() {
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiBaseUrl,
      connectTimeout: const Duration(milliseconds: AppConfig.connectTimeoutMs),
      receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeoutMs),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ),
  );

  if (kDebugMode) {
    dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        logPrint: (object) => debugPrint(object.toString()),
      ),
    );
  }

  return dio;
}
