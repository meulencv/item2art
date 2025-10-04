import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  // IMPORTANTE: Reemplaza con tu clave de API de Gemini
  // Obtén una en: https://aistudio.google.com/app/apikey
  static const String _apiKey = 'AIzaSyB2gIaB9txferfkiP4prTn_CB0Tbp8oY74';
  static const String _baseUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

  /// Procesa el texto del usuario usando Gemini API para crear un resumen
  /// optimizado con palabras clave
  static Future<String> processMemoryText(
    String originalText,
    String memoryType,
  ) async {
    try {
      final prompt = _buildPrompt(originalText, memoryType);

      final response = await http.post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt},
              ],
            },
          ],
          'generationConfig': {
            // Desactivar "pensamiento" para respuestas más rápidas
            'thinkingConfig': {'thinkingBudget': 0},
            'maxOutputTokens': 200,
            'temperature': 0.7,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Extraer el texto generado de la respuesta
        final generatedText =
            data['candidates']?[0]?['content']?['parts']?[0]?['text'] ??
            originalText;

        return generatedText.trim();
      } else {
        print('Error en Gemini API: ${response.statusCode}');
        print('Response: ${response.body}');
        // En caso de error, retornar el texto original
        return originalText;
      }
    } catch (e) {
      print('Error procesando con Gemini: $e');
      // En caso de error, retornar el texto original
      return originalText;
    }
  }

  /// Construye el prompt para Gemini según el tipo de recuerdo
  static String _buildPrompt(String text, String memoryType) {
    String typeContext = '';

    switch (memoryType.toLowerCase()) {
      case 'historia':
        typeContext = 'una historia o anécdota personal';
        break;
      case 'musica':
      case 'música':
        typeContext = 'un recuerdo relacionado con música';
        break;
      case 'imagen':
        typeContext = 'un recuerdo visual o relacionado con imágenes';
        break;
      default:
        typeContext = 'un recuerdo';
    }

    return '''
Eres un asistente que ayuda a condensar recuerdos en texto corto pero significativo.

El usuario ha escrito $typeContext:
"$text"

Por favor, crea una versión resumida y mejorada de este recuerdo (máximo 150 palabras) que:
1. Capture la esencia emocional del recuerdo
2. Incluya palabras clave importantes que ayuden a recordar
3. Sea claro y evocativo
4. Mantenga el tono personal del usuario
5. Sea fácil de leer posteriormente en una tarjeta NFC

Responde SOLO con el texto mejorado, sin explicaciones adicionales.
''';
  }
}
