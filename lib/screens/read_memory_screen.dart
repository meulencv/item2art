import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

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

    _startNFCSession();
  }

  @override
  void dispose() {
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
        setState(() {
          _errorMessage = 'NFC no está disponible en este dispositivo';
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
      print('Error iniciando sesión NFC: $e');
      setState(() {
        _errorMessage = 'Error al iniciar NFC: $e';
      });
    }
  }

  Future<void> _readFromNFC(NfcTag tag) async {
    try {
      print('📱 Tarjeta NFC detectada');

      String? text;

      // Intentar leer NDEF desde Android
      final ndefAndroid = NdefAndroid.from(tag);
      if (ndefAndroid != null) {
        text = await _readFromNdefAndroid(ndefAndroid);
      }

      // Si no funcionó con Android, intentar con iOS
      if (text == null) {
        final ndefIos = NdefIos.from(tag);
        if (ndefIos != null) {
          text = await _readFromNdefIos(ndefIos);
        }
      }

      if (text == null) {
        setState(() {
          _errorMessage = 'Esta tarjeta no contiene datos NDEF';
        });
        return;
      }

      print('📄 Texto leído: $text');

      // Intentar parsear como JSON
      try {
        final jsonData = jsonDecode(text);

        if (jsonData is Map &&
            jsonData.containsKey('tipo') &&
            jsonData.containsKey('contenido')) {
          setState(() {
            _showContent = true;
            _memoryType = jsonData['tipo'];
            _memoryContent = jsonData['contenido'];
          });

          _successController.forward();
          await NfcManager.instance.stopSession();
        } else {
          setState(() {
            _errorMessage = 'Formato de datos incorrecto';
          });
        }
      } catch (e) {
        print('Error parseando JSON: $e');
        setState(() {
          _errorMessage = 'Esta tarjeta no contiene un recuerdo válido';
        });
      }
    } catch (e) {
      print('Error leyendo NFC: $e');
      setState(() {
        _errorMessage = 'Error al leer la tarjeta: $e';
      });
    }
  }

  Future<String?> _readFromNdefAndroid(NdefAndroid ndefAndroid) async {
    try {
      // Primero intentar con el mensaje cacheado
      if (ndefAndroid.cachedNdefMessage != null &&
          ndefAndroid.cachedNdefMessage!.records.isNotEmpty) {
        final firstRecord = ndefAndroid.cachedNdefMessage!.records[0];
        return _decodeNdefTextPayload(firstRecord.payload);
      }

      // Si no hay mensaje cacheado, intentar leer
      final message = await ndefAndroid.getNdefMessage();
      if (message != null && message.records.isNotEmpty) {
        final firstRecord = message.records[0];
        return _decodeNdefTextPayload(firstRecord.payload);
      }

      return null;
    } catch (e) {
      print('Error leyendo Android NDEF: $e');
      return null;
    }
  }

  Future<String?> _readFromNdefIos(NdefIos ndefIos) async {
    try {
      // Primero intentar con el mensaje cacheado
      if (ndefIos.cachedNdefMessage != null &&
          ndefIos.cachedNdefMessage!.records.isNotEmpty) {
        final firstRecord = ndefIos.cachedNdefMessage!.records[0];
        return _decodeNdefTextPayload(firstRecord.payload);
      }

      // Si no hay mensaje cacheado, intentar leer
      final message = await ndefIos.readNdef();
      if (message != null && message.records.isNotEmpty) {
        final firstRecord = message.records[0];
        return _decodeNdefTextPayload(firstRecord.payload);
      }

      return null;
    } catch (e) {
      print('Error leyendo iOS NDEF: $e');
      return null;
    }
  }

  String _decodeNdefTextPayload(Uint8List bytes) {
    if (bytes.isEmpty) return '';

    // El primer byte contiene información de codificación y longitud del idioma
    int languageCodeLength = bytes[0] & 0x3F;

    // Saltar el byte de estado y el código de idioma
    int textStart = 1 + languageCodeLength;

    if (textStart >= bytes.length) return '';

    // El resto son los bytes del texto en UTF-8
    return utf8.decode(bytes.sublist(textStart));
  }

  IconData _getIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'historia':
        return Icons.book;
      case 'musica':
      case 'música':
        return Icons.music_note;
      case 'imagen':
        return Icons.image;
      default:
        return Icons.memory;
    }
  }

  Color _getColorForType(String type) {
    switch (type.toLowerCase()) {
      case 'historia':
        return const Color(0xFF667EEA);
      case 'musica':
      case 'música':
        return const Color(0xFFFEC163);
      case 'imagen':
        return const Color(0xFFFF6B9D);
      default:
        return const Color(0xFF764BA2);
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
            'Acceder a Recuerdo',
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
            'Acerca tu objeto',
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
              'Coloca el objeto con la tarjeta NFC cerca de tu dispositivo para leer el recuerdo',
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
                    _memoryType!.toUpperCase(),
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
                  Text(
                    'Tu Recuerdo',
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
                        'Volver al Inicio',
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
              'Error al leer',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white.withOpacity(0.95),
              ),
            ),

            const SizedBox(height: 16),

            Text(
              _errorMessage ?? 'Ocurrió un error desconocido',
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
                  setState(() {
                    _showContent = false;
                    _errorMessage = null;
                    _memoryType = null;
                    _memoryContent = null;
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
                        'Intentar de Nuevo',
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
                'Volver al Inicio',
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
}
