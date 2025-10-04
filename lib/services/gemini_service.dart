import 'dart:convert';
import 'package:http/http.dart' as http;

class GeminiService {
  // IMPORTANTE: Reemplaza con tu clave de API de Gemini
  // Obtén una en: https://aistudio.google.com/app/apikey
  static const String _apiKey = 'AIzaSyB2gIaB9txferfkiP4prTn_CB0Tbp8oY74';
  static const String _textModelUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';
  static const String _imageModelUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-image:streamGenerateContent';

  // OpenRouter API (nano banana) para generación de imágenes al LEER NFC
  static const String _openRouterApiKey = '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';
  static const String _openRouterUrl = 'https://openrouter.ai/api/v1/chat/completions';

  /// Genera una imagen usando OpenRouter API (nano banana) basándose en el contenido del recuerdo
  /// Se usa al LEER un NFC de tipo imagen
  static Future<String?> generateImageFromMemory(String memoryContent) async {
    try {
      print('🎨 Llamando a OpenRouter API (nano banana) para generar imagen...');
      
      final requestBody = {
        'model': 'google/gemini-2.5-flash-image-preview',
        'messages': [
          {
            'role': 'user',
            'content': 'Crea una foto artística y emotiva basada en este recuerdo: $memoryContent'
          }
        ],
        'modalities': ['image', 'text']
      };

      final response = await http.post(
        Uri.parse(_openRouterUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_openRouterApiKey',
        },
        body: jsonEncode(requestBody),
      );

      print('📡 Respuesta de OpenRouter API (Status: ${response.statusCode})');
      print('📄 Body completo: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Extraer la imagen de la respuesta
        final images = data['choices']?[0]?['message']?['images'];
        if (images != null && images.isNotEmpty) {
          final imageUrl = images[0]?['image_url']?['url'];
          if (imageUrl != null && imageUrl.startsWith('data:image')) {
            // Extraer el base64 de la URL data:image
            final base64Data = imageUrl.split(',').last;
            print('✅ Imagen generada exitosamente (${base64Data.length} chars)');
            return base64Data;
          }
        }
      }

      print('⚠️ No se pudo generar imagen (status: ${response.statusCode})');
      return null;
      
    } catch (e) {
      print('❌ Error en OpenRouter API: $e');
      return null;
    }
  }

  /// Procesa una memoria de tipo imagen usando Gemini 2.5 Flash Image
  /// Devuelve un Map con 'texto' (descripción) e 'imagen' (base64)
  static Future<Map<String, String>> processImageMemory(String originalText) async {
    try {
      final prompt = '''Basándote en esta descripción, genera una imagen artística y emotiva que capture la esencia del recuerdo:

"$originalText"

También proporciona una breve descripción del recuerdo en español (máximo 100 palabras) que incluya palabras clave emocionales.''';

      final requestBody = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'responseModalities': ['IMAGE', 'TEXT']
        }
      };

      print('🎨 Llamando a Gemini Image API...');
      final response = await http.post(
        Uri.parse('$_imageModelUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      print('📡 Respuesta de Gemini Image API (Status: ${response.statusCode})');
      print('📄 Body completo: ${response.body}');

      if (response.statusCode == 200) {
        // La API usa streaming, procesamos las líneas
        final lines = response.body.split('\n');
        String? imageBase64;
        String? textDescription;

        for (var line in lines) {
          if (line.trim().isEmpty) continue;
          
          // Eliminar prefijo "data: " si existe
          final jsonLine = line.startsWith('data: ') ? line.substring(6) : line;
          
          try {
            final data = jsonDecode(jsonLine);
            if (data['candidates'] != null && data['candidates'].isNotEmpty) {
              final parts = data['candidates'][0]['content']?['parts'];
              if (parts != null) {
                for (var part in parts) {
                  // Extraer imagen en base64
                  if (part['inlineData'] != null && part['inlineData']['data'] != null) {
                    imageBase64 = part['inlineData']['data'];
                    print('✅ Imagen generada (${imageBase64?.length ?? 0} chars en base64)');
                  }
                  // Extraer texto
                  if (part['text'] != null) {
                    textDescription = (textDescription ?? '') + part['text'];
                  }
                }
              }
            }
          } catch (e) {
            // Ignorar líneas mal formadas
            continue;
          }
        }

        if (imageBase64 != null && imageBase64.isNotEmpty) {
          print('✅ Procesamiento de imagen exitoso');
          return {
            'texto': textDescription?.trim() ?? originalText,
            'imagen': imageBase64
          };
        }
      }

      print('⚠️ No se pudo generar imagen (status: ${response.statusCode})');
      print('Response: ${response.body}');
      return {'texto': originalText, 'imagen': ''};
      
    } catch (e) {
      print('❌ Error en Gemini Image API: $e');
      return {'texto': originalText, 'imagen': ''};
    }
  }

  /// Procesa el texto del usuario usando Gemini API para crear un resumen
  /// optimizado con palabras clave
  static Future<String> processMemoryText(
    String originalText,
    String memoryType,
  ) async {
    try {
      final prompt = _buildPrompt(originalText, memoryType);

      final response = await http.post(
        Uri.parse('$_textModelUrl?key=$_apiKey'),
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
