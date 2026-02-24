import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'ai_provider.dart';

/// FitRoom AI Provider for virtual try-on
/// API Documentation: https://developer.fitroom.app/
class FitRoomProvider implements AIProvider {
  final Dio _dio;
  final String _apiKey;

  static const String _baseUrl = 'https://platform.fitroom.app';
  static const String _tryOnEndpoint = '/api/tryon/v2/tasks';

  FitRoomProvider({
    required Dio dio,
    required String apiKey,
  })  : _dio = dio,
        _apiKey = apiKey {
    _dio.options = BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 180),
      headers: {
        'X-API-KEY': _apiKey,
      },
    );
  }

  @override
  AIProviderType get type => AIProviderType.fitroom;

  @override
  Future<bool> isConfigured() async {
    return _apiKey.isNotEmpty;
  }

  @override
  Future<void> validateInputs({
    required File personImage,
    required String garmentImage,
  }) async {
    if (!await personImage.exists()) {
      throw Exception('Person image file does not exist');
    }

    final fileSize = await personImage.length();
    if (fileSize > 10 * 1024 * 1024) {
      throw Exception('Person image must be less than 10MB');
    }
  }

  @override
  Future<TryOnResult> tryOn({
    required File personImage,
    required String garmentImage,
    required String category,
    TryOnProgressCallback? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    try {
      onProgress?.call(0.1, 'Preparing images...');

      // FitRoom uses multipart form data
      final formData = FormData();

      // Add model (person) image
      formData.files.add(MapEntry(
        'model_image',
        await MultipartFile.fromFile(
          personImage.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      ));

      // Handle garment image - download if URL
      if (garmentImage.startsWith('http')) {
        onProgress?.call(0.15, 'Downloading garment image...');
        final downloadDio = Dio();
        final response = await downloadDio.get<List<int>>(
          garmentImage,
          options: Options(responseType: ResponseType.bytes),
        );
        formData.files.add(MapEntry(
          'cloth_image',
          MultipartFile.fromBytes(
            response.data!,
            filename: 'garment.jpg',
            contentType: MediaType('image', 'jpeg'),
          ),
        ));
      } else {
        formData.files.add(MapEntry(
          'cloth_image',
          await MultipartFile.fromFile(
            garmentImage,
            contentType: MediaType('image', 'jpeg'),
          ),
        ));
      }

      // Add cloth type
      formData.fields.add(MapEntry('cloth_type', _mapCategory(category)));

      // Enable HD mode for better quality
      formData.fields.add(const MapEntry('hd_mode', 'true'));

      onProgress?.call(0.2, 'Uploading images...');

      // Create try-on task
      final response = await _dio.post(
        _tryOnEndpoint,
        data: formData,
        options: Options(
          contentType: 'multipart/form-data',
        ),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data;
        final taskId = data['task_id'] as String;

        onProgress?.call(0.3, 'Creating your look...');

        // Poll for result
        final resultUrl = await _pollForResult(taskId, onProgress);

        onProgress?.call(1.0, 'Complete!');
        stopwatch.stop();

        return TryOnResult(
          resultImageUrl: resultUrl,
          provider: 'FitRoom',
          processingTime: stopwatch.elapsed,
          metadata: {
            'category': category,
            'taskId': taskId,
          },
        );
      } else {
        throw Exception('FitRoom request failed: ${response.statusCode}');
      }
    } catch (e) {
      stopwatch.stop();
      if (e is DioException) {
        throw _handleDioError(e);
      }
      rethrow;
    }
  }

  Future<String> _pollForResult(
    String taskId,
    TryOnProgressCallback? onProgress,
  ) async {
    const maxAttempts = 90;
    const pollInterval = Duration(milliseconds: 2000);
    var attempts = 0;

    while (attempts < maxAttempts) {
      await Future.delayed(pollInterval);
      attempts++;

      final progress = 0.3 + (attempts / maxAttempts) * 0.6;
      onProgress?.call(progress, 'Generating... (${attempts * 2}s)');

      final response = await _dio.get('$_tryOnEndpoint/$taskId');

      if (response.statusCode != 200) {
        throw Exception('Failed to get task status');
      }

      final data = response.data;
      final status = data['status'] as String;

      if (status == 'COMPLETED') {
        final resultUrl = data['download_signed_url'] as String?;
        if (resultUrl != null) {
          return resultUrl;
        }
        throw Exception('No result image in response');
      } else if (status == 'FAILED') {
        final error = data['error'] ?? 'Task failed';
        throw Exception(error.toString());
      }
      // status == 'PROCESSING' or 'CREATED' - continue polling
    }

    throw Exception('Task timed out after ${maxAttempts * 2} seconds');
  }

  String _mapCategory(String category) {
    // FitRoom uses: 'upper', 'lower', 'full_set', 'combo'
    return switch (category) {
      'upper_body' => 'upper',
      'lower_body' => 'lower',
      'full_body' => 'full_set',
      _ => 'upper',
    };
  }

  Exception _handleDioError(DioException e) {
    if (e.response != null) {
      final statusCode = e.response!.statusCode;
      final responseData = e.response!.data;

      String? message;
      if (responseData is Map) {
        message = responseData['message']?.toString() ??
                  responseData['error']?.toString() ??
                  responseData['detail']?.toString();
      }

      switch (statusCode) {
        case 401:
          return Exception('Invalid API key. Please check your FitRoom configuration.');
        case 402:
          return Exception('Insufficient credits. Please add more credits to your FitRoom account.');
        case 422:
          return Exception('Invalid input: ${message ?? 'Check image format'}');
        case 429:
          return Exception('Rate limit exceeded. Please try again later.');
        case 500:
        case 502:
        case 503:
          return Exception('FitRoom service temporarily unavailable.');
        default:
          return Exception('FitRoom error ($statusCode): ${message ?? e.response!.statusMessage}');
      }
    }

    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout) {
      return Exception('Request timed out. Please try again.');
    }

    return Exception('Network error: ${e.message}');
  }
}
