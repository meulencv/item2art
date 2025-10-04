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

  /// Requests the generation of a song and returns the taskId.
  static Future<String> generateSong({
    required String prompt,
    bool instrumental = false,
    bool customMode = false,
    String? callbackUrl,
    String? style,
    String? title,
    String? negativeTags,
    String? vocalGender,
    double? styleWeight,
    double? weirdnessConstraint,
    double? audioWeight,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    _ensureConfigured();

    // Validate and sanitize the prompt based on the mode and model.
    final sanitizedPrompt = _validateAndSanitizePrompt(
      prompt,
      customMode,
      _model,
    );

    final payload = <String, dynamic>{
      'prompt': sanitizedPrompt,
      'model': _model,
      'instrumental': instrumental,
      'customMode': customMode,
      // callBackUrl is required by the API, but we can use a placeholder because we poll for status updates.
      'callBackUrl': callbackUrl ?? 'https://example.com/callback',
    };

    // Add optional parameters when provided.
    if (style != null && style.isNotEmpty) {
      payload['style'] = _validateStyle(style, _model);
    }
    if (title != null && title.isNotEmpty) {
      payload['title'] = _validateTitle(title);
    }
    if (negativeTags != null && negativeTags.isNotEmpty) {
      payload['negativeTags'] = negativeTags;
    }
    if (vocalGender != null && (vocalGender == 'm' || vocalGender == 'f')) {
      payload['vocalGender'] = vocalGender;
    }
    if (styleWeight != null && styleWeight >= 0 && styleWeight <= 1) {
      payload['styleWeight'] = styleWeight;
    }
    if (weirdnessConstraint != null &&
        weirdnessConstraint >= 0 &&
        weirdnessConstraint <= 1) {
      payload['weirdnessConstraint'] = weirdnessConstraint;
    }
    if (audioWeight != null && audioWeight >= 0 && audioWeight <= 1) {
      payload['audioWeight'] = audioWeight;
    }

    print('🎵 Suno API Request: ${jsonEncode(payload)}');

    final response = await http
        .post(
          Uri.parse('$_baseUrl/generate'),
          headers: _headers,
          body: jsonEncode(payload),
        )
        .timeout(timeout);

    print('🎵 Suno API Response: ${response.body}');

    final json = _decodeResponse(response);

    // Validate the response code according to the Suno API documentation.
    final code = json['code'] as int?;
    final msg = json['msg'] as String?;

    if (code != 200) {
      throw SunoApiException(
        'Suno API error (code $code): ${msg ?? "Unknown error"}',
      );
    }

    final taskId = json['data']?['taskId'] as String?;
    if (taskId == null || taskId.isEmpty) {
      throw SunoApiException(
        'The response does not include a valid taskId. Full response: ${jsonEncode(json)}',
      );
    }
    print('✅ Generated taskId: $taskId');
    return taskId;
  }

  /// Retrieves the current status of a task.
  static Future<SunoTaskResult> getTaskStatus(String taskId) async {
    _ensureConfigured();

    print('🔍 Checking task status: $taskId');

    final response = await http.get(
      Uri.parse('$_baseUrl/generate/record-info?taskId=$taskId'),
      headers: _headers,
    );

    print('🔍 Status response: ${response.statusCode} - ${response.body}');

    final json = _decodeResponse(response);

    // Validate the response code.
    final code = json['code'] as int?;
    final msg = json['msg'] as String?;

    if (code != null && code != 200) {
      throw SunoApiException(
        'Error fetching task status (code $code): ${msg ?? "Unknown error"}',
      );
    }
    // Response structure: data.status and data.response.sunoData.
    final status = json['data']?['status'] as String? ?? 'unknown';
    final responseData = json['data']?['response'] as Map<String, dynamic>?;
    final songsJson = responseData?['sunoData'] as List<dynamic>?;

    print('📊 Status: $status, Songs: ${songsJson?.length ?? 0}');

    final songs = songsJson == null
        ? <SunoSong>[]
        : songsJson
              .map((e) => SunoSong.fromJson(e as Map<String, dynamic>))
              .toList();

    print('🎵 Songs processed: ${songs.length}');
    for (var song in songs) {
      print(
        '   - ${song.title}: stream=${song.streamUrl}, download=${song.downloadUrl}',
      );
    }

    return SunoTaskResult(
      taskId: taskId,
      status: status,
      songs: songs,
      raw: json,
    );
  }

  /// Generates a song and waits for it to complete or fail.
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

  /// Waits until the task reaches either `complete` or `failed`.
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
          'Music generation exceeded the maximum time (${maxWait.inSeconds}s).',
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
      throw SunoApiException('Invalid response: ${response.body}');
    }
  }

  static void _ensureConfigured() {
    if (!isConfigured) {
      throw SunoConfigException(
        'SUNO_API_TOKEN not configured. Add it to your .env file.',
      );
    }
  }

  /// Validates and sanitizes the prompt according to the mode and model.
  static String _validateAndSanitizePrompt(
    String prompt,
    bool customMode,
    String model,
  ) {
    int maxLength;

    if (customMode) {
      // Custom mode: limits depend on the selected model.
      if (model == 'V3_5' || model == 'V4') {
        maxLength = 3000;
      } else {
        // V4_5, V4_5PLUS, V5
        maxLength = 5000;
      }
    } else {
      // Non-custom mode: fixed limit.
      maxLength = 500;
    }

    if (prompt.length > maxLength) {
      print(
        '⚠️ Prompt truncated from ${prompt.length} to $maxLength characters',
      );
      return prompt.substring(0, maxLength - 3) + '...';
    }

    return prompt;
  }

  /// Validates the style according to the model.
  static String _validateStyle(String style, String model) {
    int maxLength;

    if (model == 'V3_5' || model == 'V4') {
      maxLength = 200;
    } else {
      // V4_5, V4_5PLUS, V5
      maxLength = 1000;
    }

    if (style.length > maxLength) {
      print('⚠️ Style truncated from ${style.length} to $maxLength characters');
      return style.substring(0, maxLength - 3) + '...';
    }

    return style;
  }

  /// Validates the title value.
  static String _validateTitle(String title) {
    const maxLength = 80;

    if (title.length > maxLength) {
      print('⚠️ Title truncated from ${title.length} to $maxLength characters');
      return title.substring(0, maxLength - 3) + '...';
    }

    return title;
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

  // As per documentation: SUCCESS, FIRST_SUCCESS, PENDING, CREATE_TASK_FAILED, etc.
  bool get isComplete => status.toUpperCase() == 'SUCCESS';
  bool get isFailed =>
      status.toUpperCase().contains('FAILED') ||
      status.toUpperCase().contains('ERROR');
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
      streamUrl: json['streamAudioUrl'] as String?,
      downloadUrl: json['audioUrl'] as String?,
    );
  }
}

/// Base exception for Suno API errors.
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
