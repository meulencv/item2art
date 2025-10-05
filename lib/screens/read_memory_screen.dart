import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
import '../services/audio_player_service.dart';
import '../services/gemini_service.dart';
import '../services/supabase_service.dart';
import '../services/suno_music_service.dart';
import '../services/nfc_foreground_service.dart';
import '../services/prompt_templates.dart';
import 'voice_chat_screen.dart';

class ReadMemoryScreen extends StatefulWidget {
  const ReadMemoryScreen({super.key});

  @override
  State<ReadMemoryScreen> createState() => _ReadMemoryScreenState();
}

class _ReadMemoryScreenState extends State<ReadMemoryScreen>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _pulseController;
  late AnimationController _successController;
  late Animation<double> _waveAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _successAnimation;

  bool _showContent = false;
  String? _memoryType;
  String? _memoryContent;
  String? _errorMessage;
  bool _isGeneratingImage = false;
  String? _generatedImageBase64;
  bool _isGeneratingMusic = false;
  SunoSong? _generatedSong;

  // Unified audio player
  AudioPlayerService? _audioService;
  bool _isMusicPlaying = false;
  StreamSubscription? _playerStateSubscription;

  @override
  void initState() {
    super.initState();

    _waveController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat();

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _successController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _waveAnimation = Tween<double>(begin: 0, end: 1).animate(_waveController);
    _pulseAnimation = Tween<double>(
      begin: 0.95,
      end: 1.05,
    ).animate(_pulseController);
    _successAnimation = CurvedAnimation(
      parent: _successController,
      curve: Curves.elasticOut,
    );

    // Enable NFC exclusive mode (Android only)
    NfcForegroundService.enable();
    _startNFCSession();
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  @override
  void dispose() {
    // Release the audio player
    _playerStateSubscription?.cancel();
    _audioService?.dispose();

    // Disable exclusive mode when leaving
    NfcForegroundService.disable();
    NfcManager.instance.stopSession();
    _waveController.dispose();
    _pulseController.dispose();
    _successController.dispose();
    super.dispose();
  }

  Future<void> _startNFCSession() async {
    try {
      bool isAvailable = await NfcManager.instance.isAvailable();

      if (!isAvailable) {
        _safeSetState(() {
          _errorMessage = 'NFC is not available on this device';
        });
        return;
      }

      NfcManager.instance.startSession(
        pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
        onDiscovered: (NfcTag tag) async {
          await _readFromNFC(tag);
        },
      );
    } catch (e) {
      print('Error starting NFC session: $e');
      _safeSetState(() {
        _errorMessage = 'Failed to start NFC: $e';
      });
    }
  }

  Future<void> _readFromNFC(NfcTag tag) async {
    try {
      print('📱 NFC tag detected');

      _safeSetState(() {
        _errorMessage = null;
        _showContent = false;
        _generatedImageBase64 = null;
        _generatedSong = null;
        _isGeneratingImage = false;
        _isGeneratingMusic = false;
      });

      String? uuid;

      // Try to read the UUID from Android first
      final ndefAndroid = NdefAndroid.from(tag);
      if (ndefAndroid != null) {
        uuid = await _readUuidFromNdefAndroid(ndefAndroid);
      }

      // If Android fails, try with iOS
      if (uuid == null) {
        final ndefIos = NdefIos.from(tag);
        if (ndefIos != null) {
          uuid = await _readUuidFromNdefIos(ndefIos);
        }
      }

      if (uuid == null) {
        _safeSetState(() {
          _errorMessage = 'This tag does not contain a valid UUID';
        });
        return;
      }

      print('🔖 UUID read: $uuid');

      // Retrieve data from Supabase using the UUID
      final memoryData = await SupabaseService.getMemoryByUuid(uuid);

      if (memoryData == null) {
        _safeSetState(() {
          _errorMessage =
              'No information was found for this UUID in the database';
        });
        return;
      }

      // Extract memory type and content
      final tipo = memoryData['tipo'] as String?;
      final contenido = memoryData['contenido'] as String?;

      if (tipo == null || contenido == null) {
        _safeSetState(() {
          _errorMessage = 'Incorrect data format in the database';
        });
        return;
      }

      _safeSetState(() {
        _memoryType = tipo;
        _memoryContent = contenido;
      });

      await NfcManager.instance.stopSession();

      // If the type is image, generate artwork with Gemini (regenerated on demand)
      if (tipo == 'image' || tipo == 'imagen') {
        // ignore: avoid_print
        print(
          '\n🖼️ [READ_MEMORY] Tipo de memoria detectado: IMAGEN (tipo=$tipo)',
        );
        // ignore: avoid_print
        print('   Iniciando generación de imagen...');

        _safeSetState(() {
          _isGeneratingImage = true;
        });

        final generatedImage = await GeminiService.generateImageFromMemory(
          contenido,
        );

        // ignore: avoid_print
        print('\n📊 [READ_MEMORY] Resultado de generación:');
        // ignore: avoid_print
        print('   ¿Imagen recibida?: ${generatedImage != null ? "SÍ" : "NO"}');
        if (generatedImage != null) {
          // ignore: avoid_print
          print('   Tamaño: ${generatedImage.length} caracteres');
        }

        _safeSetState(() {
          _isGeneratingImage = false;
          _generatedImageBase64 = generatedImage;
          _showContent = true;
        });

        // ignore: avoid_print
        print('   Estado UI actualizado - showContent: $_showContent\n');
      } else if (_isMusicType(tipo)) {
        // If the type is music, generate a song with Suno (regenerated on demand)
        _safeSetState(() {
          _isGeneratingMusic = true;
        });

        try {
          final musicPrompt = PromptTemplates.musicPrompt(
            contentSummary: contenido,
          );
          final sunoResult = await SunoMusicService.generateSongAndWait(
            prompt: musicPrompt,
            pollInterval: const Duration(seconds: 4),
            maxWait: const Duration(minutes: 3),
          );

          if (sunoResult.isComplete && sunoResult.songs.isNotEmpty) {
            final song = sunoResult.songs.first;
            print('🎵 [READ_MEMORY] Música generada exitosamente:');
            print('   Título: ${song.title}');
            print('   Stream URL: ${song.streamUrl}');
            print('   Download URL: ${song.downloadUrl}');
            print('   Estado final: ${sunoResult.status}');

            _safeSetState(() {
              _isGeneratingMusic = false;
              _generatedSong = song;
              _showContent = true;
              _errorMessage = null;
            });
          } else {
            print('❌ [READ_MEMORY] Error: música no completada o vacía');
            print('   Estado: ${sunoResult.status}');
            print('   Canciones: ${sunoResult.songs.length}');

            _safeSetState(() {
              _isGeneratingMusic = false;
              _errorMessage =
                  'Music generation failed (status: ${sunoResult.status})';
            });
          }
        } catch (e) {
          print('Error generating music: $e');
          _safeSetState(() {
            _isGeneratingMusic = false;
            _errorMessage = 'Failed to generate music: $e';
          });
        }
      } else {
        // For story, simply show the content
        _safeSetState(() {
          _showContent = true;
        });
      }

      _successController.forward();
    } catch (e) {
      print('Error reading NFC: $e');
      _safeSetState(() {
        _errorMessage = 'Failed to read the tag: $e';
      });
    }
  }

  Future<String?> _readUuidFromNdefAndroid(NdefAndroid ndefAndroid) async {
    try {
      // Try the cached message first
      if (ndefAndroid.cachedNdefMessage != null &&
          ndefAndroid.cachedNdefMessage!.records.isNotEmpty) {
        final firstRecord = ndefAndroid.cachedNdefMessage!.records[0];
        return _decodeNdefTextPayload(firstRecord.payload);
      }

      // If there isn't a cached message, try reading it
      final message = await ndefAndroid.getNdefMessage();
      if (message != null && message.records.isNotEmpty) {
        final firstRecord = message.records[0];
        return _decodeNdefTextPayload(firstRecord.payload);
      }

      return null;
    } catch (e) {
      print('Error reading Android NDEF UUID: $e');
      return null;
    }
  }

  Future<String?> _readUuidFromNdefIos(NdefIos ndefIos) async {
    try {
      // Try the cached message first
      if (ndefIos.cachedNdefMessage != null &&
          ndefIos.cachedNdefMessage!.records.isNotEmpty) {
        final firstRecord = ndefIos.cachedNdefMessage!.records[0];
        return _decodeNdefTextPayload(firstRecord.payload);
      }

      // If there isn't a cached message, try reading it
      final message = await ndefIos.readNdef();
      if (message != null && message.records.isNotEmpty) {
        final firstRecord = message.records[0];
        return _decodeNdefTextPayload(firstRecord.payload);
      }

      return null;
    } catch (e) {
      print('Error reading iOS NDEF: $e');
      return null;
    }
  }

  String _decodeNdefTextPayload(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    // The first byte contains encoding info and language length
    int languageCodeLength = bytes[0] & 0x3F;

    // Skip the status byte and the language code
    int textStart = 1 + languageCodeLength;

    if (textStart >= bytes.length) return '';

    // The remainder contains the UTF-8 text bytes
    return utf8.decode(bytes.sublist(textStart));
  }

  IconData _getIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'story':
      case 'historia':
        return Icons.book;
      case 'music':
      case 'musica':
      case 'música':
        return Icons.music_note;
      case 'image':
      case 'imagen':
        return Icons.image;
      default:
        return Icons.memory;
    }
  }

  Color _getColorForType(String type) {
    switch (type.toLowerCase()) {
      case 'story':
      case 'historia':
        return const Color(0xFF667EEA);
      case 'music':
      case 'musica':
      case 'música':
        return const Color(0xFFFEC163);
      case 'image':
      case 'imagen':
        return const Color(0xFFFF6B9D);
      default:
        return const Color(0xFF764BA2);
    }
  }

  bool _isMusicType(String? type) {
    if (type == null) return false;
    final normalized = type.toLowerCase();
    return normalized == 'music' ||
        normalized == 'musica' ||
        normalized == 'música';
  }

  /// Translates Spanish memory types to English for display
  String _translateTypeToEnglish(String type) {
    switch (type.toLowerCase()) {
      case 'historia':
        return 'STORY';
      case 'musica':
      case 'música':
        return 'MUSIC';
      case 'imagen':
        return 'IMAGE';
      case 'story':
        return 'STORY';
      case 'music':
        return 'MUSIC';
      case 'image':
        return 'IMAGE';
      default:
        return type.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0f0c29),
              const Color(0xFF302b63),
              const Color(0xFF24243e),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          Text(
            'Access Memory',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_errorMessage != null) {
      return _buildErrorView();
    } else if (_isGeneratingImage) {
      return _buildGeneratingImageView();
    } else if (_isGeneratingMusic) {
      return _buildGeneratingMusicView();
    } else if (_showContent) {
      return _buildContentView();
    } else {
      return _buildScanningView();
    }
  }

  Widget _buildScanningView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated NFC waves
          SizedBox(
            width: 300,
            height: 300,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer waves
                ...List.generate(3, (index) {
                  return AnimatedBuilder(
                    animation: _waveAnimation,
                    builder: (context, child) {
                      final delay = index * 0.3;
                      final progress = (_waveAnimation.value + delay) % 1.0;

                      return Container(
                        width: 100 + (progress * 200),
                        height: 100 + (progress * 200),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color(
                              0xFF667EEA,
                            ).withOpacity(1 - progress),
                            width: 2,
                          ),
                        ),
                      );
                    },
                  );
                }),

                // Center icon with pulse
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _pulseAnimation.value,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              const Color(0xFF667EEA),
                              const Color(0xFF764BA2),
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF667EEA).withOpacity(0.5),
                              blurRadius: 30,
                              spreadRadius: 10,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.nfc,
                          size: 60,
                          color: Colors.white,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          Text(
            'Bring your object close',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.95),
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Hold the object with the NFC tag near your device to read the memory',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.6),
                fontWeight: FontWeight.w300,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratingImageView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated loading indicator
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Spinning circle
                AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _waveController.value * 2 * 3.14159,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFFFF6B9D),
                              const Color(0xFFFEC163),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Inner icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF0f0c29),
                  ),
                  child: const Icon(Icons.image, size: 50, color: Colors.white),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          Text(
            'Generating image...',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.95),
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'AI is creating an image based on your memory',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.6),
                fontWeight: FontWeight.w300,
                height: 1.5,
              ),
            ),
          ),

          const SizedBox(height: 24),

          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B9D)),
          ),
        ],
      ),
    );
  }

  Widget _buildGeneratingMusicView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Animated loading indicator
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Spinning circle
                AnimatedBuilder(
                  animation: _waveController,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _waveController.value * 2 * 3.14159,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF667EEA),
                              const Color(0xFFFEC163),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Inner icon
                Container(
                  width: 100,
                  height: 100,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFF0f0c29),
                  ),
                  child: const Icon(
                    Icons.music_note,
                    size: 50,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          Text(
            'Generating music...',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: Colors.white.withOpacity(0.95),
              letterSpacing: 0.5,
            ),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Text(
              'Suno AI is composing a song based on your memory',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.6),
                fontWeight: FontWeight.w300,
                height: 1.5,
              ),
            ),
          ),

          const SizedBox(height: 24),

          const CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFEC163)),
          ),
        ],
      ),
    );
  }

  Widget _buildContentView() {
    if (_memoryType == null || _memoryContent == null) {
      return _buildErrorView();
    }

    final icon = _getIconForType(_memoryType!);
    final color = _getColorForType(_memoryType!);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ScaleTransition(
        scale: _successAnimation,
        child: Column(
          children: [
            const SizedBox(height: 20),

            // Success icon
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [color, color.withOpacity(0.7)],
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.5),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: Icon(icon, size: 50, color: Colors.white),
            ),

            const SizedBox(height: 32),

            // Type badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color.withOpacity(0.3), color.withOpacity(0.1)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: color.withOpacity(0.5), width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 20, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    _translateTypeToEnglish(_memoryType!),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // Content card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.15),
                    Colors.white.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.white.withOpacity(0.2),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // If the memory type is image, display the generated artwork
                  if ((_memoryType == 'image' || _memoryType == 'imagen') &&
                      _generatedImageBase64 != null &&
                      _generatedImageBase64!.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        base64Decode(_generatedImageBase64!),
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 200,
                            color: Colors.white.withOpacity(0.1),
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.broken_image,
                                    size: 60,
                                    color: Colors.white.withOpacity(0.3),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Error loading image',
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.5),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),
                  ] else if (_memoryType == 'image' ||
                      _memoryType == 'imagen') ...[
                    // If the image could not be generated, show a message
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange.shade300,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Failed to generate the image',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // If the memory type is music, show the Suno-generated song
                  if (_isMusicType(_memoryType) &&
                      _generatedSong?.streamUrl?.isNotEmpty == true) ...[
                    _buildMusicPlayerCard(),
                    const SizedBox(height: 20),
                  ] else if (_isMusicType(_memoryType)) ...[
                    // If the music could not be generated, show a message
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.orange.withOpacity(0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.orange.shade300,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Failed to generate the music',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  Text(
                    'Your Memory',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withOpacity(0.9),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _memoryContent!,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white.withOpacity(0.85),
                      height: 1.6,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Back button
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.pop(context),
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    vertical: 18,
                    horizontal: 32,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFF667EEA),
                        const Color(0xFF764BA2),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667EEA).withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.home, color: Colors.white, size: 24),
                      SizedBox(width: 12),
                      Text(
                        'Back to Home',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            if (_memoryType != null &&
                (_memoryType!.toLowerCase() == 'story' ||
                    _memoryType!.toLowerCase() == 'historia'))
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    // Navigate to the voice chat screen with the memory content
                    final content = _memoryContent!;
                    // Lazy load to avoid circular dependencies: dynamic import
                    // ignore: use_build_context_synchronously
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            VoiceChatScreen(memoryContext: content),
                      ),
                    );
                  },
                  borderRadius: BorderRadius.circular(30),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      vertical: 18,
                      horizontal: 32,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6B9D), Color(0xFFFEC163)],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF6B9D).withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.record_voice_over,
                          color: Colors.white,
                          size: 24,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Talk to the Memory',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.red.shade400, Colors.red.shade600],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.red.withOpacity(0.5),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.error_outline,
                size: 50,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 32),

            Text(
              'Read error',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.95),
              ),
            ),

            const SizedBox(height: 16),

            Text(
              _errorMessage ?? 'An unknown error occurred',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.white.withOpacity(0.7),
                height: 1.5,
              ),
            ),

            const SizedBox(height: 40),

            // Retry button
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  _safeSetState(() {
                    _showContent = false;
                    _errorMessage = null;
                    _memoryType = null;
                    _memoryContent = null;
                    _isGeneratingImage = false;
                    _generatedImageBase64 = null;
                  });
                  _startNFCSession();
                },
                borderRadius: BorderRadius.circular(30),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 18,
                    horizontal: 32,
                  ),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF667EEA), Color(0xFF764BA2)],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF667EEA).withOpacity(0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.refresh, color: Colors.white, size: 24),
                      SizedBox(width: 12),
                      Text(
                        'Try Again',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Back button
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Back to Home',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMusicPlayerCard() {
    final song = _generatedSong!;
    final title = (song.title?.isNotEmpty ?? false)
        ? song.title!
        : 'Generated song';
    final streamUrl = song.streamUrl!;
    final isPlaying = _isMusicPlaying;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFF667EEA).withOpacity(0.3),
            const Color(0xFFFEC163).withOpacity(0.2),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFEC163).withOpacity(0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.music_note, color: Color(0xFFFEC163), size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Tap play to listen to the track generated for this memory.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.75),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _playMusic(streamUrl),
              icon: Icon(
                isPlaying
                    ? Icons.pause_circle_filled
                    : Icons.play_circle_filled,
              ),
              label: Text(isPlaying ? 'Pause song' : 'Play song'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white.withOpacity(0.12),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Stream URL',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            streamUrl,
            style: TextStyle(
              color: Colors.white.withOpacity(0.65),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _playMusic(String url) async {
    try {
      print('🎵 [PLAY_MUSIC] Intentando reproducir URL: $url');

      // Lazily initialize the service if needed
      _audioService ??= AudioPlayerService();
      print('🎵 [PLAY_MUSIC] AudioPlayerService inicializado');

      // Listen for state changes (only once)
      _playerStateSubscription ??= _audioService!.playerStateStream.listen((
        state,
      ) {
        print(
          '🎵 [PLAY_MUSIC] Estado del reproductor: playing=${state.playing}',
        );
        _safeSetState(() {
          _isMusicPlaying = state.playing;
        });
      });

      if (_isMusicPlaying) {
        // Pause if it's already playing
        print('🎵 [PLAY_MUSIC] Pausando reproducción...');
        await _audioService!.pause();
      } else {
        // Start playback
        print('🎵 [PLAY_MUSIC] Iniciando reproducción desde URL...');
        await _audioService!.playFromUrl(url);
        print('🎵 [PLAY_MUSIC] ✅ Reproducción iniciada exitosamente');
      }
    } catch (e) {
      print('❌ [PLAY_MUSIC] Error playing music: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error playing music: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }
}
