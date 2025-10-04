import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class KieImageService {
  static const String _defaultBaseUrl = 'https://api.kie.ai/api/v1';
  static const String _defaultModel = 'google/nano-banana';

  static String get _apiKey => dotenv.env['KIE_API_KEY']?.trim() ?? '';

  static String get _baseUrl {
    final custom = dotenv.env['KIE_BASE_URL']?.trim();
    return (custom != null && custom.isNotEmpty) ? custom : _defaultBaseUrl;
  }

  static String get _model {
    final custom = dotenv.env['KIE_IMAGE_MODEL']?.trim();
    return (custom != null && custom.isNotEmpty) ? custom : _defaultModel;
  }

  static bool get isConfigured => _apiKey.isNotEmpty;

  static Map<String, String> get _headers => {
    'Authorization': 'Bearer $_apiKey',
    'Content-Type': 'application/json',
  };

  /// Creates an image from the given [prompt].
  /// Returns the base64-encoded PNG once the job is finished.
  static Future<String> generateImage({
    required String prompt,
    Duration pollInterval = const Duration(seconds: 4),
    Duration maxWait = const Duration(minutes: 2),
    String outputFormat = 'png',
    String imageSize = '1:1',
    String? callbackUrl,
  }) async {
    _ensureConfigured();

    final taskId = await _createTask(
      prompt: prompt,
      outputFormat: outputFormat,
      imageSize: imageSize,
      callbackUrl: callbackUrl,
    );

    final result = await _waitForCompletion(
      taskId,
      pollInterval: pollInterval,
      maxWait: maxWait,
    );

    if (result.base64Image == null || result.base64Image!.isEmpty) {
      throw KieImageException(
        'Task $taskId completed but no image data was returned.',
      );
    }

    return result.base64Image!;
  }

  static Future<String> _createTask({
    required String prompt,
    required String outputFormat,
    required String imageSize,
    String? callbackUrl,
  }) async {
    final payload = {
      'model': _model,
      'callBackUrl': callbackUrl ?? 'https://example.com/callback',
      'input': {
        'prompt': prompt,
        'output_format': outputFormat,
        'image_size': imageSize,
      },
    };

    final response = await http.post(
      Uri.parse('$_baseUrl/jobs/createTask'),
      headers: _headers,
      body: jsonEncode(payload),
    );

    final json = _decodeResponse(response);
    final taskId = json['data']?['taskId'] as String?;

    if (taskId == null || taskId.isEmpty) {
      throw KieImageException(
        'createTask response missing taskId. Full payload: ${jsonEncode(json)}',
      );
    }

    return taskId;
  }

  static Future<_KieTaskResult> _waitForCompletion(
    String taskId, {
    required Duration pollInterval,
    required Duration maxWait,
  }) async {
    final deadline = DateTime.now().add(maxWait);

    while (true) {
      final result = await _getTaskInfo(taskId);
      final status = result.status?.toUpperCase();

      if (status == 'SUCCESS' || status == 'COMPLETED' || status == 'DONE') {
        return result;
      }

      if (status == 'FAILED' || status == 'ERROR') {
        throw KieImageException(
          'Task $taskId failed with status ${result.status} and message ${result.message ?? 'unknown'}.',
        );
      }

      if (DateTime.now().isAfter(deadline)) {
        throw KieImageTimeoutException(
          'Task $taskId did not complete within ${maxWait.inSeconds}s.',
        );
      }

      await Future.delayed(pollInterval);
    }
  }

  static Future<_KieTaskResult> _getTaskInfo(String taskId) async {
    final response = await http.get(
      Uri.parse('$_baseUrl/jobs/recordInfo?taskId=$taskId'),
      headers: {'Authorization': 'Bearer $_apiKey'},
    );

    final json = _decodeResponse(response);
    final data = json['data'] as Map<String, dynamic>? ?? {};
    final responseData = data['response'] as Map<String, dynamic>? ?? {};

    String? imageBase64;

    if (responseData['image'] is String) {
      imageBase64 = responseData['image'] as String;
    } else if (responseData['imageBase64'] is String) {
      imageBase64 = responseData['imageBase64'] as String;
    } else if (responseData['images'] is List) {
      final images = responseData['images'] as List;
      if (images.isNotEmpty) {
        final first = images.first;
        if (first is String) {
          imageBase64 = first;
        } else if (first is Map) {
          imageBase64 =
              (first['base64'] ?? first['b64_json'] ?? first['image'])
                  as String?;
        }
      }
    }

    return _KieTaskResult(
      status: data['status'] as String?,
      message: json['msg'] as String?,
      base64Image: imageBase64,
      raw: json,
    );
  }

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw KieImageException('HTTP ${response.statusCode}: ${response.body}');
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw KieImageException('Invalid JSON response: ${response.body}');
    }
  }

  static void _ensureConfigured() {
    if (!isConfigured) {
      throw KieImageConfigException(
        'KIE_API_KEY not configured. Add it to your .env file.',
      );
    }
  }
}

class _KieTaskResult {
  final String? status;
  final String? message;
  final String? base64Image;
  final Map<String, dynamic> raw;

  _KieTaskResult({
    required this.status,
    required this.message,
    required this.base64Image,
    required this.raw,
  });
}

class KieImageException implements Exception {
  final String message;
  KieImageException(this.message);

  @override
  String toString() => 'KieImageException: $message';
}

class KieImageConfigException extends KieImageException {
  KieImageConfigException(String message) : super(message);
}

class KieImageTimeoutException extends KieImageException {
  KieImageTimeoutException(String message) : super(message);
}
