import 'package:flutter/material.dart';
import 'dart:math' as math;

class NFCScanScreen extends StatefulWidget {
  const NFCScanScreen({super.key});

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

  bool _isScanning = true;
  bool _showSuccess = false;

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

    // Simular detección de NFC después de 3 segundos
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _simulateNFCDetection();
      }
    });
  }

  void _simulateNFCDetection() {
    setState(() {
      _isScanning = false;
      _showSuccess = true;
    });
    _waveController.stop();
    _pulseController.stop();
    _successController.forward();
  }

  @override
  void dispose() {
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
            'Preparando tu recuerdo...',
            style: TextStyle(
              color: Colors.white.withOpacity(0.7),
              fontSize: 16,
              letterSpacing: 0.5,
            ),
          ),
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
