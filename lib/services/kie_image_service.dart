import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
    // ignore: avoid_print
    print('🎨 [KIE] Iniciando generación de imagen...');
    // ignore: avoid_print
    print(
      '   Prompt: ${prompt.substring(0, prompt.length > 60 ? 60 : prompt.length)}...',
    );
    // ignore: avoid_print
    print('   Modelo: $_model');
    // ignore: avoid_print
    print('   Formato: $outputFormat, Tamaño: $imageSize');

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

    if (result.imageUrl == null || result.imageUrl!.isEmpty) {
      // ignore: avoid_print
      print('❌ [KIE] Task $taskId completó pero NO retornó URL de imagen');
      throw KieImageException(
        'Task $taskId completed but no image URL was returned.',
      );
    }

    // ignore: avoid_print
    print('🔗 [KIE] URL de imagen recibida: ${result.imageUrl}');
    // ignore: avoid_print
    print('📥 [KIE] Descargando imagen desde URL...');

    final base64Image = await _downloadImageAsBase64(result.imageUrl!);

    // ignore: avoid_print
    print(
      '✅ [KIE] Imagen descargada y convertida! Base64 length: ${base64Image.length} chars',
    );
    return base64Image;
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

    // ignore: avoid_print
    print('📤 [KIE] POST createTask → $_baseUrl/jobs/createTask');
    // ignore: avoid_print
    print('   Payload: ${jsonEncode(payload)}');

    final response = await http.post(
      Uri.parse('$_baseUrl/jobs/createTask'),
      headers: _headers,
      body: jsonEncode(payload),
    );

    // ignore: avoid_print
    print('📥 [KIE] Response status: ${response.statusCode}');
    // ignore: avoid_print
    print(
      '   Body: ${response.body.substring(0, response.body.length > 300 ? 300 : response.body.length)}...',
    );

    final json = _decodeResponse(response);
    final taskId = json['data']?['taskId'] as String?;

    if (taskId == null || taskId.isEmpty) {
      // ignore: avoid_print
      print('❌ [KIE] createTask NO retornó taskId!');
      throw KieImageException(
        'createTask response missing taskId. Full payload: ${jsonEncode(json)}',
      );
    }

    // ignore: avoid_print
    print('🆔 [KIE] Task creado: $taskId');
    return taskId;
  }

  static Future<_KieTaskResult> _waitForCompletion(
    String taskId, {
    required Duration pollInterval,
    required Duration maxWait,
  }) async {
    final deadline = DateTime.now().add(maxWait);
    final startTime = DateTime.now();
    int attempt = 0;

    // ignore: avoid_print
    print(
      '⏳ [KIE] Esperando completado de task $taskId (max ${maxWait.inSeconds}s)...',
    );

    while (true) {
      attempt++;
      final result = await _getTaskInfo(taskId);
      final status = result.status?.toUpperCase();
      final elapsed = DateTime.now().difference(startTime).inSeconds;

      // ignore: avoid_print
      print('🔄 [KIE] Intento #$attempt (${elapsed}s) - Estado: $status');

      if (status == 'SUCCESS' || status == 'COMPLETED' || status == 'DONE') {
        // ignore: avoid_print
        print('✅ [KIE] Task completado exitosamente en ${elapsed}s');
        return result;
      }

      if (status == 'FAILED' || status == 'ERROR') {
        // ignore: avoid_print
        print('❌ [KIE] Task falló: ${result.message ?? "sin mensaje"}');
        throw KieImageException(
          'Task $taskId failed with status ${result.status} and message ${result.message ?? 'unknown'}.',
        );
      }

      if (DateTime.now().isAfter(deadline)) {
        // ignore: avoid_print
        print('⏱️ [KIE] Timeout tras ${elapsed}s esperando task $taskId');
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

    // ignore: avoid_print
    print('📥 [KIE] GET recordInfo status: ${response.statusCode}');
    // ignore: avoid_print
    print('   Body COMPLETO: ${response.body}');

    final json = _decodeResponse(response);
    final data = json['data'] as Map<String, dynamic>? ?? {};

    // ignore: avoid_print
    print('📊 [KIE] Data completa: ${jsonEncode(data).substring(0, 300)}...');

    String? imageUrl;

    // Intentar extraer de resultJson (formato callback)
    if (data['resultJson'] is String) {
      try {
        final resultJson =
            jsonDecode(data['resultJson'] as String) as Map<String, dynamic>;
        if (resultJson['resultUrls'] is List) {
          final urls = resultJson['resultUrls'] as List;
          if (urls.isNotEmpty) {
            imageUrl = urls.first as String;
            // ignore: avoid_print
            print('🎯 [KIE] URL extraída de resultJson.resultUrls: $imageUrl');
          }
        }
      } catch (e) {
        // ignore: avoid_print
        print('⚠️ [KIE] Error parseando resultJson: $e');
      }
    }

    // Fallback: intentar extraer de response.resultUrls directamente
    if (imageUrl == null) {
      final responseData = data['response'] as Map<String, dynamic>? ?? {};
      if (responseData['resultUrls'] is List) {
        final urls = responseData['resultUrls'] as List;
        if (urls.isNotEmpty) {
          imageUrl = urls.first as String;
          // ignore: avoid_print
          print('🎯 [KIE] URL extraída de response.resultUrls: $imageUrl');
        }
      }
    }

    // ignore: avoid_print
    print(
      '� [KIE] URL de imagen encontrada: ${imageUrl != null ? "SÍ - $imageUrl" : "NO"}',
    );

    return _KieTaskResult(
      status: data['state'] as String? ?? data['status'] as String?,
      message: json['msg'] as String?,
      imageUrl: imageUrl,
      raw: json,
    );
  }

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // ignore: avoid_print
      print('❌ [KIE] Error HTTP ${response.statusCode}');
      // ignore: avoid_print
      print('   Body: ${response.body}');
      throw KieImageException('HTTP ${response.statusCode}: ${response.body}');
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      // ignore: avoid_print
      print('❌ [KIE] Error parseando JSON: $e');
      // ignore: avoid_print
      print('   Body recibido: ${response.body}');
      throw KieImageException('Invalid JSON response: ${response.body}');
    }
  }

  /// Downloads an image from URL and converts it to base64
  static Future<String> _downloadImageAsBase64(String imageUrl) async {
    try {
      final response = await http.get(Uri.parse(imageUrl));

      if (response.statusCode != 200) {
        throw KieImageException(
          'Failed to download image from $imageUrl: HTTP ${response.statusCode}',
        );
      }

      final Uint8List bytes = response.bodyBytes;
      final base64String = base64Encode(bytes);

      // ignore: avoid_print
      print(
        '💾 [KIE] Imagen descargada: ${bytes.length} bytes → ${base64String.length} chars base64',
      );

      return base64String;
    } catch (e) {
      // ignore: avoid_print
      print('❌ [KIE] Error descargando imagen desde $imageUrl: $e');
      rethrow;
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
  final String? imageUrl;
  final Map<String, dynamic> raw;

  _KieTaskResult({
    required this.status,
    required this.message,
    required this.imageUrl,
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
