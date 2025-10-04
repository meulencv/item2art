import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:convert';
import 'nfc_scan_screen.dart';
import '../services/gemini_service.dart';

class CreateMemoryScreen extends StatefulWidget {
  const CreateMemoryScreen({super.key});

  @override
  State<CreateMemoryScreen> createState() => _CreateMemoryScreenState();
}

enum MemoryType { historia, musica, imagen }

class _CreateMemoryScreenState extends State<CreateMemoryScreen>
    with TickerProviderStateMixin {
  final TextEditingController _storyController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  late AnimationController _fadeController;
  late AnimationController _floatController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _floatAnimation;

  bool _canContinue = false;
  MemoryType? _selectedMemoryType;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );

    _floatController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );

    _floatAnimation = Tween<double>(begin: -8, end: 8).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    _fadeController.forward();

    _storyController.addListener(() {
      setState(() {
        _canContinue =
            _storyController.text.trim().length > 10 &&
            _selectedMemoryType != null;
      });
    });
  }

  @override
  void dispose() {
    _storyController.dispose();
    _focusNode.dispose();
    _fadeController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  Future<bool?> _showImagePreviewDialog(String text, String imageBase64) async {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0f0c29),
                  Color(0xFF302b63),
                  Color(0xFF24243e),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF6B9D).withOpacity(0.3),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        const Color(0xFFFF6B9D).withOpacity(0.8),
                        const Color(0xFFFEC163).withOpacity(0.8),
                      ],
                    ),
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(22),
                      topRight: Radius.circular(22),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.image, color: Colors.white, size: 28),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Imagen Generada',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Content
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Imagen generada
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.memory(
                          base64Decode(imageBase64),
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 200,
                              color: Colors.grey.shade800,
                              child: const Center(
                                child: Icon(
                                  Icons.error_outline,
                                  color: Colors.white,
                                  size: 48,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Texto del recuerdo
                      Text(
                        'Contenido:',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.7),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.2),
                          ),
                        ),
                        child: Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Botones
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white.withOpacity(0.2),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF667EEA),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Continuar a NFC',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _continueToNFC() async {
    if (_canContinue && !_isProcessing) {
      setState(() {
        _isProcessing = true;
      });

      try {
        final memoryTypeStr = _selectedMemoryType.toString().split('.').last;
        
        // Si es tipo imagen, procesar con Gemini Image API
        if (_selectedMemoryType == MemoryType.imagen) {
          final result = await GeminiService.processImageMemory(
            _storyController.text.trim(),
          );

          setState(() {
            _isProcessing = false;
          });

          if (!mounted) return;

          // Mostrar vista previa de la imagen generada
          if (result['imagen'] != null) {
            final shouldContinue = await _showImagePreviewDialog(
              result['contenido'] ?? _storyController.text.trim(),
              result['imagen']!,
            );

            if (shouldContinue == true && mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NFCScanScreen(
                    memoryStory: result['contenido'] ?? _storyController.text.trim(),
                    memoryType: memoryTypeStr,
                    imageBase64: result['imagen'],
                  ),
                ),
              );
            }
          } else {
            // No se generó imagen
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('No se pudo generar la imagen. Intenta de nuevo.'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        } else {
          // Para historia y música, procesar solo texto
          final processedText = await GeminiService.processMemoryText(
            _storyController.text.trim(),
            memoryTypeStr,
          );

          setState(() {
            _isProcessing = false;
          });

          if (!mounted) return;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NFCScanScreen(
                memoryStory: processedText,
                memoryType: memoryTypeStr,
              ),
            ),
          );
        }
      } catch (e) {
        print('Error procesando con IA: $e');
        setState(() {
          _isProcessing = false;
        });
        
        // En caso de error, usar el texto original
        if (!mounted) return;

        final memoryTypeStr = _selectedMemoryType.toString().split('.').last;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => NFCScanScreen(
              memoryStory: _storyController.text.trim(),
              memoryType: memoryTypeStr,
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

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
        child: Stack(
          children: [
            // Animated background particles
            ...List.generate(
              15,
              (index) => _buildFloatingParticle(index, size),
            ),

            // Main content
            SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Column(
                          children: [
                            const SizedBox(height: 40),
                            _buildMemoryTypeSelector(),
                            const SizedBox(height: 40),
                            _buildIconHeader(),
                            const SizedBox(height: 40),
                            _buildStoryInput(),
                            const SizedBox(height: 30),
                            _buildCharacterCount(),
                            const SizedBox(height: 40),
                          ],
                        ),
                      ),
                    ),
                    _buildContinueButton(),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFloatingParticle(int index, Size size) {
    final random = math.Random(index);
    final left = random.nextDouble() * size.width;
    final top = random.nextDouble() * size.height;
    final particleSize = random.nextDouble() * 4 + 2;

    return Positioned(
      left: left,
      top: top,
      child: AnimatedBuilder(
        animation: _floatAnimation,
        builder: (context, child) {
          return Transform.translate(
            offset: Offset(
              math.sin(_floatAnimation.value + index) * 15,
              _floatAnimation.value,
            ),
            child: Container(
              width: particleSize,
              height: particleSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.25),
                boxShadow: [
                  BoxShadow(
                    color: Colors.white.withOpacity(0.4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          );
        },
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
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildMemoryTypeSelector() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tipo de Recuerdo',
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 18,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildMemoryTypeCard(
                  type: MemoryType.historia,
                  icon: Icons.book,
                  label: 'Historia',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMemoryTypeCard(
                  type: MemoryType.musica,
                  icon: Icons.music_note,
                  label: 'Música',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMemoryTypeCard(
                  type: MemoryType.imagen,
                  icon: Icons.image,
                  label: 'Imagen',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMemoryTypeCard({
    required MemoryType type,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _selectedMemoryType == type;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedMemoryType = type;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSelected
                ? [
                    const Color(0xFFFF6B9D).withOpacity(0.8),
                    const Color(0xFFFEC163).withOpacity(0.8),
                  ]
                : [
                    Colors.white.withOpacity(0.1),
                    Colors.white.withOpacity(0.05),
                  ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFFF6B9D).withOpacity(0.8)
                : Colors.white.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFFFF6B9D).withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconHeader() {
    return AnimatedBuilder(
      animation: _floatAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _floatAnimation.value * 0.5),
          child: Column(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [const Color(0xFFFF6B9D), const Color(0xFFFEC163)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFF6B9D).withOpacity(0.4),
                      blurRadius: 25,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.edit_note,
                  size: 50,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Cuenta tu historia',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white.withOpacity(0.95),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Escribe la semilla del recuerdo que quieres vincular a este objeto',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withOpacity(0.6),
                    fontWeight: FontWeight.w300,
                    letterSpacing: 0.5,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStoryInput() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withOpacity(0.1),
            Colors.white.withOpacity(0.05),
          ],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.2), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: TextField(
        controller: _storyController,
        focusNode: _focusNode,
        maxLines: 8,
        maxLength: 500,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w400,
          height: 1.6,
        ),
        decoration: InputDecoration(
          hintText:
              'Ej: "Aventura, dragones, me sentí valiente"\n\n'
              'Describe emociones, momentos clave o anécdotas que quieres preservar...',
          hintStyle: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 15,
            fontWeight: FontWeight.w300,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(24),
          counterText: '',
        ),
      ),
    );
  }

  Widget _buildCharacterCount() {
    final count = _storyController.text.length;
    final color = count > 10
        ? const Color(0xFF38EF7D)
        : Colors.white.withOpacity(0.5);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          count > 10 ? '✓ Mínimo alcanzado' : 'Escribe al menos 10 caracteres',
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.3,
          ),
        ),
        Text(
          '$count / 500',
          style: TextStyle(
            color: Colors.white.withOpacity(0.5),
            fontSize: 13,
            fontWeight: FontWeight.w400,
          ),
        ),
      ],
    );
  }

  Widget _buildContinueButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: AnimatedOpacity(
        opacity: _canContinue ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 300),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _canContinue ? _continueToNFC : null,
            borderRadius: BorderRadius.circular(30),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _canContinue
                      ? [const Color(0xFF667EEA), const Color(0xFF764BA2)]
                      : [Colors.grey.shade700, Colors.grey.shade800],
                ),
                borderRadius: BorderRadius.circular(30),
                boxShadow: _canContinue
                    ? [
                        BoxShadow(
                          color: const Color(0xFF667EEA).withOpacity(0.4),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ]
                    : [],
              ),
              child: _isProcessing
                  ? const SizedBox(
                      height: 24,
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Continuar al Escaneo NFC',
                          style: const TextStyle(
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
      ),
    );
  }
}
