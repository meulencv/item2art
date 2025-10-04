import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Service for interacting with ElevenLabs (basic TTS and STT)
/// Note: In production, move API keys to a backend or secure service.
class ElevenLabsService {
  // Variables loaded from dotenv (.env)
  static final String _apiKey = dotenv.env['ELEVENLABS_API_KEY'] ?? '';
  static final String _baseUrl = 'https://api.elevenlabs.io';
  static final String _defaultVoiceId =
      dotenv.env['ELEVENLABS_VOICE_ID'] ?? 'JBFqnCBsd6RMkjVDRZzb';
  static final String _ttsModel =
      dotenv.env['ELEVENLABS_TTS_MODEL'] ?? 'eleven_multilingual_v2';
  static final String _sttModel =
      dotenv.env['ELEVENLABS_STT_MODEL'] ?? 'scribe_v1';

  static bool get isConfigured => _apiKey.isNotEmpty;

  /// Converts text into MP3 audio and returns a ready-to-play temp file.
  static Future<File?> textToSpeech(String text) async {
    if (!isConfigured) {
      print('⚠️ ElevenLabs API key not configured');
      return null;
    }
    try {
      final uri = Uri.parse(
        '$_baseUrl/v1/text-to-speech/$_defaultVoiceId?output_format=mp3_44100_128',
      );
      final body = jsonEncode({'text': text, 'model_id': _ttsModel});

      final resp = await http.post(
        uri,
        headers: {'xi-api-key': _apiKey, 'Content-Type': 'application/json'},
        body: body,
      );

      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        final dir = await getTemporaryDirectory();
        final file = File(
          '${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3',
        );
        await file.writeAsBytes(bytes, flush: true);
        return file;
      } else {
        print('❌ ElevenLabs TTS error: ${resp.statusCode} ${resp.body}');
        return null;
      }
    } catch (e) {
      print('❌ TTS exception: $e');
      return null;
    }
  }

  /// Sends an audio file for transcription.
  /// The file must be in a supported format (mp3/m4a/wav). Returns text or null.
  static Future<String?> speechToText(File audioFile) async {
    if (!isConfigured) {
      print('⚠️ ElevenLabs API key not configured');
      return null;
    }
    try {
      final uri = Uri.parse('$_baseUrl/v1/speech-to-text');
      final req = http.MultipartRequest('POST', uri)
        ..headers['xi-api-key'] = _apiKey
        ..fields['model_id'] = _sttModel
        ..files.add(await http.MultipartFile.fromPath('file', audioFile.path));

      final streamed = await req.send();
      final resp = await http.Response.fromStream(streamed);

      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['text'] as String?; // Simple response
      } else {
        print('❌ ElevenLabs STT error: ${resp.statusCode} ${resp.body}');
        return null;
      }
    } catch (e) {
      print('❌ STT exception: $e');
      return null;
    }
  }
}
