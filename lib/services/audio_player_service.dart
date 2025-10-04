import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Unified service for audio playback (voices, music, etc.)
/// Applies DRY by centralizing playback logic in a single place
class AudioPlayerService {
  final AudioPlayer _player;
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  AudioPlayerService() : _player = AudioPlayer() {
    // Listen for position changes
    _player.positionStream.listen((position) {
      _position = position;
    });

    // Listen for duration changes
    _player.durationStream.listen((duration) {
      _duration = duration ?? Duration.zero;
    });

    // Listen for state changes
    _player.playerStateStream.listen((state) {
      _isPlaying = state.playing;
      _isLoading =
          state.processingState == ProcessingState.loading ||
          state.processingState == ProcessingState.buffering;
    });
  }

  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  Duration get duration => _duration;
  Duration get position => _position;

  /// Stream to observe position updates
  Stream<Duration> get positionStream => _player.positionStream;

  /// Stream to observe player state changes
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  /// Plays audio from a local file
  Future<void> playFromFile(File file) async {
    try {
      await _player.setFilePath(file.path);
      await _player.play();
    } catch (e) {
      if (kDebugMode) print('❌ Error playing from file: $e');
      rethrow;
    }
  }

  /// Plays audio from a URL
  Future<void> playFromUrl(String url) async {
    try {
      await _player.setUrl(url);
      await _player.play();
    } catch (e) {
      if (kDebugMode) print('❌ Error playing from URL: $e');
      rethrow;
    }
  }

  /// Pauses playback
  Future<void> pause() async {
    await _player.pause();
  }

  /// Resumes playback
  Future<void> resume() async {
    await _player.play();
  }

  /// Stops playback
  Future<void> stop() async {
    await _player.stop();
  }

  /// Seeks to a specific position
  Future<void> seek(Duration position) async {
    await _player.seek(position);
  }

  /// Releases player resources
  Future<void> dispose() async {
    await _player.dispose();
  }

  /// Plays audio and waits until it finishes
  Future<void> playAndWait(String url) async {
    try {
      await _player.setUrl(url);
      await _player.play();

      // Wait until playback completes
      await _player.playerStateStream.firstWhere((state) {
        return state.processingState == ProcessingState.completed;
      });
    } catch (e) {
      if (kDebugMode) print('❌ Error in playAndWait: $e');
      rethrow;
    }
  }
}
