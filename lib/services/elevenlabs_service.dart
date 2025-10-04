import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Servicio para interactuar con ElevenLabs (TTS y STT simples)
/// Nota: Para producción mover las claves a backend o a un servicio seguro.
class ElevenLabsService {
  static const String _apiKey = 'REEMPLAZAR_CON_TU_XI_API_KEY'; // TODO mover a seguro
  static const String _baseUrl = 'https://api.elevenlabs.io';
  static const String _defaultVoiceId = 'JBFqnCBsd6RMkjVDRZzb'; // Ejemplo voice ID
  static const String _ttsModel = 'eleven_multilingual_v2'; // Modelo estable actual
  static const String _sttModel = 'scribe_v1';

  /// Convierte texto a bytes de audio (mp3) y retorna un archivo temporal listo para reproducir.
  static Future<File?> textToSpeech(String text) async {
    try {
      final uri = Uri.parse('$_baseUrl/v1/text-to-speech/$_defaultVoiceId?output_format=mp3_44100_128');
      final body = jsonEncode({
        'text': text,
        'model_id': _ttsModel,
      });

      final resp = await http.post(
        uri,
        headers: {
          'xi-api-key': _apiKey,
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (resp.statusCode == 200) {
        final bytes = resp.bodyBytes;
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
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
