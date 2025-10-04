import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Servicio para interactuar con ElevenLabs (TTS y STT simples)
/// Nota: Para producción mover las claves a backend o a un servicio seguro.
class ElevenLabsService {
  // Variables obtenidas desde dotenv (.env)
  static final String _apiKey = dotenv.env['ELEVENLABS_API_KEY'] ?? '';
  static final String _baseUrl = 'https://api.elevenlabs.io';
  static final String _defaultVoiceId =
      dotenv.env['ELEVENLABS_VOICE_ID'] ?? 'JBFqnCBsd6RMkjVDRZzb';
  static final String _ttsModel =
      dotenv.env['ELEVENLABS_TTS_MODEL'] ?? 'eleven_multilingual_v2';
  static final String _sttModel =
      dotenv.env['ELEVENLABS_STT_MODEL'] ?? 'scribe_v1';

  static bool get isConfigured => _apiKey.isNotEmpty;

  /// Convierte texto a bytes de audio (mp3) y retorna un archivo temporal listo para reproducir.
  static Future<File?> textToSpeech(String text) async {
    if (!isConfigured) {
      print('⚠️ ElevenLabs API key no configurada');
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
        print('❌ Error TTS ElevenLabs: ${resp.statusCode} ${resp.body}');
        return null;
      }
    } catch (e) {
      print('❌ Excepción TTS: $e');
      return null;
    }
  }

  /// Envía un archivo de audio para transcribir.
  /// El archivo debe ser un formato soportado (mp3/m4a/wav). Devuelve texto o null.
  static Future<String?> speechToText(File audioFile) async {
    if (!isConfigured) {
      print('⚠️ ElevenLabs API key no configurada');
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
        return data['text'] as String?; // Respuesta simple
      } else {
        print('❌ Error STT ElevenLabs: ${resp.statusCode} ${resp.body}');
        return null;
      }
    } catch (e) {
      print('❌ Excepción STT: $e');
      return null;
    }
  }
}
