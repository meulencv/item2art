enum GeminiPromptType { chat, image, music }

class PromptTemplates {
  static String chatPrompt({
    required String userInput,
    required String contextData,
  }) {
    return '''
System Prompt:

You are a friendly and curious conversational assistant. Use only the information available in the provided database to answer or explain what the user asks.
Focus on cultural facts, memories, experiences, and emotions reflected in the data.
If something is not found in the database, say so naturally (e.g. "That’s not mentioned in what I know").
Be casual and human, as if you were sharing a personal story or reflection.

User query: $userInput
Database info: $contextData
''';
  }

  static String imagePrompt({required String contentSummary}) {
    return '''
Create a visually engaging image that represents the main idea, feeling, or story described in the content below.
The image should evoke the cultural or emotional atmosphere of the topic — for example, the traditions, environment, or sensations involved.

Content: $contentSummary

Style: cinematic, warm tones, natural light, emotionally resonant.
''';
  }

  static String musicPrompt({required String contentSummary}) {
    return '''
Write and compose a full song inspired by the content below.
Capture its emotional tone and cultural atmosphere through the melody and lyrics.
The lyrics should tell a short story or express the feelings behind the experience, keeping a natural and relatable vibe.

Content: $contentSummary

Style: adapt to the mood of the text (e.g. nostalgic, joyful, reflective, dreamy).
''';
  }
}
