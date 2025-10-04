import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import '../services/audio_player_service.dart';
import '../services/elevenlabs_service.dart';
import '../services/gemini_service.dart';

enum VoiceChatMessageRole { user, ai }

class VoiceChatMessage {
  final VoiceChatMessageRole role;
  final String text;
  final DateTime timestamp;
  VoiceChatMessage({required this.role, required this.text})
    : timestamp = DateTime.now();
}

class VoiceChatProvider extends ChangeNotifier {
  final List<VoiceChatMessage> _messages = [];
  bool _isRecording = false;
  bool _isProcessing = false;
  bool _isPlaying = false;

  final AudioPlayerService _audioService = AudioPlayerService();
  final AudioRecorder _recorder = AudioRecorder();

  List<VoiceChatMessage> get messages => List.unmodifiable(_messages);
  bool get isRecording => _isRecording;
  bool get isProcessing => _isProcessing;
  bool get isPlaying => _isPlaying;

  Future<void> disposePlayer() async {
    await _audioService.dispose();
  }

  void addSystemIntro(String introText) {
    if (_messages.isEmpty) {
      _messages.add(
        VoiceChatMessage(role: VoiceChatMessageRole.ai, text: introText),
      );
      notifyListeners();
      _autoplayLastAI();
    }
  }

  Future<void> _autoplayLastAI() async {
    final last = _messages.last;
    if (last.role == VoiceChatMessageRole.ai) {
      await _speak(last.text);
    }
  }

  Future<void> startRecording() async {
    if (_isRecording) return;
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      return; // TODO: handle permission UI
    }
    _isRecording = true;
    notifyListeners();
    final tempDir = Directory.systemTemp;
    final filePath =
        '${tempDir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: filePath,
    );
  }

  Future<void> stopRecordingAndProcess() async {
    if (!_isRecording) return;
    _isRecording = false;
    _isProcessing = true;
    notifyListeners();

    final path = await _recorder.stop();
    if (path == null) {
      _isProcessing = false;
      notifyListeners();
      return;
    }

    try {
      final file = File(path);
      final userText =
          await ElevenLabsService.speechToText(file) ??
          '[Transcription failed]';
      _messages.add(
        VoiceChatMessage(role: VoiceChatMessageRole.user, text: userText),
      );
      notifyListeners();

      // Fetch Gemini's reply using a trimmed conversation history.
      final contextText = _buildContext();
      final aiResponse = await GeminiService.generateChatReply(
        userInput: userText,
        contextData: contextText,
      );
      _messages.add(
        VoiceChatMessage(role: VoiceChatMessageRole.ai, text: aiResponse),
      );
      notifyListeners();
      await _speak(aiResponse);
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  String _buildContext() {
    final buffer = StringBuffer();
    for (final m
        in _messages
            .where(
              (m) =>
                  m.role == VoiceChatMessageRole.ai ||
                  m.role == VoiceChatMessageRole.user,
            )
            .take(10)) {
      buffer.writeln(
        m.role == VoiceChatMessageRole.user
            ? 'User: ${m.text}'
            : 'AI: ${m.text}',
      );
    }
    return buffer.toString();
  }

  Future<void> _speak(String text) async {
    _isPlaying = true;
    notifyListeners();
    try {
      final file = await ElevenLabsService.textToSpeech(text);
      if (file != null) {
        await _audioService.playFromFile(file);
      }
    } catch (e) {
      if (kDebugMode) print('Audio playback error: $e');
    } finally {
      _isPlaying = false;
      notifyListeners();
    }
  }
}
