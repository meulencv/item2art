import 'dart:async';
import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class SunoMusicService {
  static const String _baseUrl = 'https://api.sunoapi.org/api/v1';

  static String get _apiToken => dotenv.env['SUNO_API_TOKEN']?.trim() ?? '';
  static String get _model =>
      dotenv.env['SUNO_MODEL']?.trim().isNotEmpty == true
      ? dotenv.env['SUNO_MODEL']!.trim()
      : 'V5';

  static bool get isConfigured => _apiToken.isNotEmpty;

  static Map<String, String> get _headers => {
    'Authorization': 'Bearer $_apiToken',
    'Content-Type': 'application/json',
  };

  /// Solicita la generación de una canción y devuelve el taskId.
  static Future<String> generateSong({
    required String prompt,
    bool instrumental = false,
    bool customMode = false,
    String? callbackUrl,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _ensureConfigured();

    final payload = <String, dynamic>{
      'prompt': prompt,
      'model': _model,
      'instrumental': instrumental,
      'customMode': customMode,
    };

    if (callbackUrl != null && callbackUrl.isNotEmpty) {
      payload['callBackUrl'] = callbackUrl;
    }

    final response = await http
        .post(
          Uri.parse('$_baseUrl/generate'),
          headers: _headers,
          body: jsonEncode(payload),
        )
        .timeout(timeout);

    final json = _decodeResponse(response);
    final taskId = json['data']?['taskId'];
    if (taskId is! String || taskId.isEmpty) {
      throw SunoApiException('La respuesta no incluye taskId válido.');
    }
    return taskId;
  }

  /// Obtiene el estado actual de un task.
  static Future<SunoTaskResult> getTaskStatus(String taskId) async {
    _ensureConfigured();

    final response = await http.get(
      Uri.parse('$_baseUrl/get?taskId=$taskId'),
      headers: _headers,
    );

    final json = _decodeResponse(response);
    final status = json['data']?['status'] as String? ?? 'unknown';
    final songsJson = json['data']?['songs'] as List<dynamic>?;

    final songs = songsJson == null
        ? <SunoSong>[]
        : songsJson
              .map((e) => SunoSong.fromJson(e as Map<String, dynamic>))
              .toList();

    return SunoTaskResult(
      taskId: taskId,
      status: status,
      songs: songs,
      raw: json,
    );
  }

  /// Genera una canción y espera a que finalice o falle.
  static Future<SunoTaskResult> generateSongAndWait({
    required String prompt,
    bool instrumental = false,
    bool customMode = false,
    String? callbackUrl,
    Duration pollInterval = const Duration(seconds: 3),
    Duration maxWait = const Duration(minutes: 2),
  }) async {
    final taskId = await generateSong(
      prompt: prompt,
      instrumental: instrumental,
      customMode: customMode,
      callbackUrl: callbackUrl,
    );

    return waitForCompletion(
      taskId,
      pollInterval: pollInterval,
      maxWait: maxWait,
    );
  }

  /// Espera hasta que el task alcance estado `complete` o `failed`.
  static Future<SunoTaskResult> waitForCompletion(
    String taskId, {
    Duration pollInterval = const Duration(seconds: 3),
    Duration maxWait = const Duration(minutes: 2),
  }) async {
    final deadline = DateTime.now().add(maxWait);
    SunoTaskResult lastResult = await getTaskStatus(taskId);

    while (!lastResult.isTerminal) {
      if (DateTime.now().isAfter(deadline)) {
        throw SunoTimeoutException(
          'La generación musical excedió el tiempo máximo (${maxWait.inSeconds}s).',
        );
      }

      await Future.delayed(pollInterval);
      lastResult = await getTaskStatus(taskId);
    }

    return lastResult;
  }

  static Map<String, dynamic> _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SunoApiException(
        'Error HTTP ${response.statusCode}: ${response.body}',
      );
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      throw SunoApiException('Respuesta inválida: ${response.body}');
    }
  }

  static void _ensureConfigured() {
    if (!isConfigured) {
      throw SunoConfigException(
        'SUNO_API_TOKEN no configurado. Añádelo en tu archivo .env',
      );
    }
  }
}

class SunoTaskResult {
  final String taskId;
  final String status;
  final List<SunoSong> songs;
  final Map<String, dynamic> raw;

  SunoTaskResult({
    required this.taskId,
    required this.status,
    required this.songs,
    required this.raw,
  });

  bool get isComplete => status.toLowerCase() == 'complete';
  bool get isFailed => status.toLowerCase() == 'failed';
  bool get isTerminal => isComplete || isFailed;
}

class SunoSong {
  final String? id;
  final String? title;
  final String? streamUrl;
  final String? downloadUrl;

  SunoSong({this.id, this.title, this.streamUrl, this.downloadUrl});

  factory SunoSong.fromJson(Map<String, dynamic> json) {
    return SunoSong(
      id: json['id'] as String?,
      title: json['title'] as String?,
      streamUrl: json['streamUrl'] as String?,
      downloadUrl: json['downloadUrl'] as String?,
    );
  }
}

/// Excepción base para errores en la API de Suno.
class SunoApiException implements Exception {
  final String message;
  SunoApiException(this.message);

  @override
  String toString() => 'SunoApiException: $message';
}

class SunoConfigException extends SunoApiException {
  SunoConfigException(String message) : super(message);
}

class SunoTimeoutException extends SunoApiException {
  SunoTimeoutException(String message) : super(message);
}
