import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
import '../models/memory.dart';
import '../services/memory_service.dart';

class NFCScanScreen extends StatefulWidget {
  final String memoryStory;

  const NFCScanScreen({super.key, required this.memoryStory});

  @override
  State<NFCScanScreen> createState() => _NFCScanScreenState();
}

class _NFCScanScreenState extends State<NFCScanScreen>
    with TickerProviderStateMixin {
  late AnimationController _waveController;
  late AnimationController _pulseController;
  late AnimationController _successController;
  late Animation<double> _waveAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<double> _successAnimation;

  final MemoryService _memoryService = MemoryService();
  bool _isScanning = true;
  bool _showSuccess = false;
  String? _savedMemoryId;

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

    _waveAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _waveController, curve: Curves.easeInOut),
    );

    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _successAnimation = CurvedAnimation(
      parent: _successController,
      curve: Curves.elasticOut,
    );

    // Iniciar sesión NFC real
    _startNFCSession();
  }

  /// Inicia la sesión NFC para escuchar tags
  /// Usa foreground dispatch para que SOLO esta app maneje el NFC
  void _startNFCSession() async {
    // Verificar disponibilidad de NFC
    bool isAvailable = await NfcManager.instance.isAvailable();

    if (!isAvailable) {
      if (mounted) {
        // Mostrar error al usuario
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'NFC no está disponible o está desactivado. Por favor, actívalo en configuración',
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Iniciar sesión NFC con foreground dispatch
    // Esto evita que otras apps intercepten el NFC mientras esta pantalla está activa
    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
      onDiscovered: (NfcTag tag) async {
        // Obtener ID del tag
        final String nfcTagId = _extractTagId(tag);

        // Procesar el tag detectado
        await _onNFCDetected(nfcTagId);
      },
    );
  }

  /// Extrae el ID único del tag NFC usando las clases de plataforma
  String _extractTagId(NfcTag tag) {
    try {
      // Android: Intentar obtener del tag genérico primero
      final nfcTagAndroid = NfcTagAndroid.from(tag);
      if (nfcTagAndroid != null && nfcTagAndroid.id.isNotEmpty) {
        return nfcTagAndroid.id
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toUpperCase();
      }

      // iOS: Intentar obtener de MiFare
      final mifare = MiFareIos.from(tag);
      if (mifare != null && mifare.identifier.isNotEmpty) {
        return mifare.identifier
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toUpperCase();
      }

      // iOS: Intentar obtener de Iso15693
      final iso15693 = Iso15693Ios.from(tag);
      if (iso15693 != null && iso15693.identifier.isNotEmpty) {
        return iso15693.identifier
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toUpperCase();
      }

      // iOS: Intentar obtener de FeliCa
      final feliCa = FeliCaIos.from(tag);
      if (feliCa != null && feliCa.currentIDm.isNotEmpty) {
        return feliCa.currentIDm
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toUpperCase();
      }
    } catch (e) {
      print('Error extrayendo ID del tag: $e');
    }

    // Fallback si no se puede extraer el ID
    return 'NFC_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Procesa la detección de un tag NFC
  Future<void> _onNFCDetected(String nfcTagId) async {
    // Detener la sesión NFC inmediatamente para evitar múltiples lecturas
    await NfcManager.instance.stopSession();

    // Crear objeto Memory
    final memory = Memory(
      id: 'MEM_${DateTime.now().millisecondsSinceEpoch}',
      story: widget.memoryStory,
      nfcTagId: nfcTagId,
      createdAt: DateTime.now(),
    );

    // Guardar en el servicio
    final saved = await _memoryService.saveMemory(memory);

    if (saved && mounted) {
      setState(() {
        _isScanning = false;
        _showSuccess = true;
        _savedMemoryId = memory.id;
      });
      _waveController.stop();
      _pulseController.stop();
      _successController.forward();

      // Volver a home después de mostrar éxito
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      });
    }
  }

  @override
  void dispose() {
    // Detener la sesión NFC al salir de la pantalla
    NfcManager.instance.stopSession();

    _waveController.dispose();
    _pulseController.dispose();
    _successController.dispose();
    super.dispose();
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
              // Header with back button
              _buildHeader(),

              const Spacer(),

              // Main scanning area
              _showSuccess ? _buildSuccessAnimation() : _buildScanningArea(),

              const Spacer(),

              // Instructions
              _buildInstructions(),

              const SizedBox(height: 60),
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
            'Crear Recuerdo',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48), // Balance for back button
        ],
      ),
    );
  }

  Widget _buildScanningArea() {
    return Column(
      children: [
        // NFC Icon with pulse animation
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, child) {
            return Transform.scale(
              scale: _pulseAnimation.value,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [const Color(0xFF667EEA), const Color(0xFF764BA2)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF667EEA).withOpacity(0.6),
                      blurRadius: 40,
                      spreadRadius: 10,
                    ),
                  ],
                ),
                child: const Icon(Icons.nfc, size: 70, color: Colors.white),
              ),
            );
          },
        ),

        const SizedBox(height: 60),

        // Revolut-style wave animation
        SizedBox(
          height: 200,
          child: AnimatedBuilder(
            animation: _waveAnimation,
            builder: (context, child) {
              return CustomPaint(
                painter: WavePainter(animationValue: _waveAnimation.value),
                size: Size(MediaQuery.of(context).size.width, 200),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessAnimation() {
    return ScaleTransition(
      scale: _successAnimation,
      child: Column(
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [const Color(0xFF11998E), const Color(0xFF38EF7D)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF38EF7D).withOpacity(0.6),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: const Icon(
              Icons.check_circle_outline,
              size: 70,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 30),
          Text(
            '¡Item Detectado!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '¡Recuerdo guardado exitosamente!',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
              letterSpacing: 0.5,
            ),
          ),
          if (_savedMemoryId != null) ...[
            const SizedBox(height: 8),
            Text(
              'ID: $_savedMemoryId',
              style: TextStyle(
                color: Colors.white.withOpacity(0.5),
                fontSize: 12,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstructions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        children: [
          if (_isScanning) ...[
            Text(
              'Acerca tu objeto',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Coloca tu dispositivo cerca del item con la etiqueta NFC',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.6),
                fontWeight: FontWeight.w300,
                letterSpacing: 0.5,
                height: 1.5,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class WavePainter extends CustomPainter {
  final double animationValue;

  WavePainter({required this.animationValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..strokeWidth = 2;

    final centerY = size.height / 2;

    // Draw multiple waves with different opacities and offsets
    for (int i = 0; i < 3; i++) {
      final path = Path();
      final offset = (animationValue * 2 * math.pi) + (i * math.pi / 3);
      final opacity = 0.15 - (i * 0.04);

      paint.color = const Color(0xFF667EEA).withOpacity(opacity);

      path.moveTo(0, centerY);

      for (double x = 0; x <= size.width; x += 1) {
        final normalizedX = x / size.width;
        final y =
            centerY +
            math.sin((normalizedX * 4 * math.pi) + offset) * (30.0 - i * 8);
        path.lineTo(x, y);
      }

      path.lineTo(size.width, size.height);
      path.lineTo(0, size.height);
      path.close();

      canvas.drawPath(path, paint);
    }

    // Draw a brighter center wave
    final centerPath = Path();
    final centerOffset = animationValue * 2 * math.pi;

    paint.color = const Color(0xFF667EEA).withOpacity(0.25);
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 3;

    centerPath.moveTo(0, centerY);

    for (double x = 0; x <= size.width; x += 1) {
      final normalizedX = x / size.width;
      final y =
          centerY + math.sin((normalizedX * 4 * math.pi) + centerOffset) * 25;
      centerPath.lineTo(x, y);
    }

    canvas.drawPath(centerPath, paint);

    // Draw scanning line
    final scanLineX = (animationValue * size.width);
    final scanLinePaint = Paint()
      ..color = const Color(0xFF667EEA).withOpacity(0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      Offset(scanLineX, centerY - 40),
      Offset(scanLineX, centerY + 40),
      scanLinePaint,
    );

    // Draw glow at scan line
    final glowPaint = Paint()
      ..color = const Color(0xFF667EEA).withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 20);

    canvas.drawCircle(Offset(scanLineX, centerY), 30, glowPaint);
  }

  @override
  bool shouldRepaint(WavePainter oldDelegate) {
    return oldDelegate.animationValue != animationValue;
  }
}
