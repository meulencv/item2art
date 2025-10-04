import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'prompt_templates.dart';
import 'kie_image_service.dart';

class GeminiService {
  // Keys and endpoints loaded via dotenv
  static final String _apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
  static final String _textModelUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/${dotenv.env['GEMINI_TEXT_MODEL'] ?? 'gemini-2.5-flash'}:generateContent';
  static final String _imageModelUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/${dotenv.env['GEMINI_IMAGE_MODEL'] ?? 'gemini-2.5-flash-image'}:streamGenerateContent';

  static bool get isGeminiConfigured => _apiKey.isNotEmpty;

  /// Generates a conversational reply constrained to the provided context data.
  static Future<String> generateChatReply({
    required String userInput,
    required String contextData,
  }) async {
    final prompt = PromptTemplates.chatPrompt(
      userInput: userInput,
      contextData: contextData.isNotEmpty ? contextData : 'No data provided.',
    );

    return _callTextModel(
      prompt: prompt,
      fallback:
          'No pude obtener una respuesta en este momento, pero seguimos explorando tus recuerdos.',
      maxOutputTokens: 250,
      temperature: 0.6,
    );
  }

  /// Generates an image using the KIE AI API based on the memory content.
  /// Used when reading an NFC tag of type image.
  static Future<String?> generateImageFromMemory(String memoryContent) async {
    if (!KieImageService.isConfigured) {
      print('⚠️ KIE API key not configured');
      return null;
    }
    try {
      print('🎨 Calling KIE AI API to generate image...');

      final prompt = PromptTemplates.imagePrompt(contentSummary: memoryContent);

      final base64 = await KieImageService.generateImage(prompt: prompt);

      print('✅ Image generated successfully (${base64.length} chars)');
      return base64;
    } catch (e) {
      print('❌ KIE API error: $e');
      return null;
    }
  }

  /// Processes an image memory using Gemini 2.5 Flash Image.
  /// Returns a map with a textual summary ('text') and the generated image in base64 ('image').
  static Future<Map<String, String>> processImageMemory(
    String originalText,
  ) async {
    if (!isGeminiConfigured) {
      print('⚠️ Gemini API key not configured');
      return {'text': originalText, 'image': ''};
    }
    try {
      final prompt =
          '''${PromptTemplates.imagePrompt(contentSummary: originalText)}
Additionally, provide a brief English summary of the memory (maximum 100 words) that highlights emotional keywords.''';

      final requestBody = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt},
            ],
          },
        ],
        'generationConfig': {
          'responseModalities': ['IMAGE', 'TEXT'],
        },
      };

      print('🎨 Calling Gemini Image API...');
      final response = await http.post(
        Uri.parse('$_imageModelUrl?key=$_apiKey'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(requestBody),
      );

      print('📡 Gemini Image API response (status: ${response.statusCode})');
      print('📄 Full body: ${response.body}');

      if (response.statusCode == 200) {
        final lines = response.body.split('\n');
        String? imageBase64;
        String? textDescription;

        for (final line in lines) {
          if (line.trim().isEmpty) continue;
          final jsonLine = line.startsWith('data: ') ? line.substring(6) : line;
          try {
            final data = jsonDecode(jsonLine);
            if (data['candidates'] != null && data['candidates'].isNotEmpty) {
              final parts = data['candidates'][0]['content']?['parts'];
              if (parts != null) {
                for (final part in parts) {
                  if (part['inlineData'] != null &&
                      part['inlineData']['data'] != null) {
                    imageBase64 = part['inlineData']['data'];
                    print(
                      '✅ Image generated (${imageBase64?.length ?? 0} base64 chars)',
                    );
                  }
                  if (part['text'] != null) {
                    textDescription = (textDescription ?? '') + part['text'];
                  }
                }
              }
            }
          } catch (_) {
            continue;
          }
        }

        if (imageBase64 != null && imageBase64.isNotEmpty) {
          print('✅ Image processing succeeded');
          return {
            'text': textDescription?.trim() ?? originalText,
            'image': imageBase64,
          };
        }
      }

      print('⚠️ Unable to generate image (status: ${response.statusCode})');
      return {'text': originalText, 'image': ''};
    } catch (e) {
      print('❌ Gemini Image API error: $e');
      return {'text': originalText, 'image': ''};
    }
  }

  /// Processes user text using the Gemini API to create a summary optimized with keywords.
  static Future<String> processMemoryText(
    String originalText,
    String memoryType,
  ) async {
    if (!isGeminiConfigured) {
      print('⚠️ Gemini API key not configured');
      return originalText;
    }
    try {
      final prompt = _buildPrompt(originalText, memoryType);

      return _callTextModel(
        prompt: prompt,
        fallback: originalText,
        maxOutputTokens: 200,
        temperature: 0.7,
      );
    } catch (e) {
      print('Error processing with Gemini: $e');
      return originalText;
    }
  }

  /// Builds the prompt for Gemini based on the memory type
  static String _buildPrompt(String text, String memoryType) {
    String typeContext = '';

    switch (memoryType.toLowerCase()) {
      case 'historia':
      case 'story':
        typeContext = 'a personal story or anecdote';
        break;
      case 'musica':
      case 'música':
      case 'music':
        typeContext = 'a memory related to music';
        break;
      case 'imagen':
      case 'image':
        typeContext = 'a visual memory or one related to images';
        break;
      default:
        typeContext = 'a memory';
    }

    return '''
You are an assistant that condenses memories into short but meaningful text.

The user wrote $typeContext:
"$text"

Please create a summarized and improved version of this memory (maximum 150 words) that:
1. Captures the emotional essence of the memory
2. Includes key phrases that aid recall
3. Stays clear and evocative
4. Preserves the user's personal tone
5. Remains easy to read later on an NFC tag

Respond ONLY with the improved text, without additional explanations.
''';
  }

  static Future<String> _callTextModel({
    required String prompt,
    required String fallback,
    int maxOutputTokens = 200,
    double temperature = 0.7,
  }) async {
    if (!isGeminiConfigured) {
      print('⚠️ Gemini API key not configured');
      return fallback;
    }

    try {
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
            'thinkingConfig': {'thinkingBudget': 0},
            'maxOutputTokens': maxOutputTokens,
            'temperature': temperature,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final generatedText =
            data['candidates']?[0]?['content']?['parts']?[0]?['text'] ??
            fallback;
        return generatedText.trim();
      } else {
        print('Gemini API error: ${response.statusCode}');
        print('Response: ${response.body}');
        return fallback;
      }
    } catch (e) {
      print('Error processing with Gemini: $e');
      return fallback;
    }
  }
}
