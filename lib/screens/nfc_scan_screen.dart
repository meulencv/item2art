import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
import 'package:ndef/ndef.dart' as ndef;
import 'package:ndef_record/ndef_record.dart';
import '../models/memory.dart';
import '../services/memory_service.dart';
import '../services/supabase_service.dart';
import '../services/nfc_foreground_service.dart';

class NFCScanScreen extends StatefulWidget {
  final String memoryStory;
  final String memoryType;
  final String? imageBase64; // Optional: only for image type

  const NFCScanScreen({
    super.key,
    required this.memoryStory,
    required this.memoryType,
    this.imageBase64,
  });

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
  String? _lastWriteError;

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

    // Enable NFC exclusive mode (Android)
    NfcForegroundService.enable();
    // Start the actual NFC session
    _startNFCSession();
  }

  @override
  void dispose() {
    // Stop the NFC session when leaving the screen
    NfcManager.instance.stopSession();
    // Disable exclusive mode when leaving
    NfcForegroundService.disable();
    _waveController.dispose();
    _pulseController.dispose();
    _successController.dispose();
    super.dispose();
  }

  /// Starts the NFC session to listen for tags
  /// Uses foreground dispatch so ONLY this app handles NFC events
  void _startNFCSession() async {
    // Check NFC availability
    bool isAvailable = await NfcManager.instance.isAvailable();

    if (!isAvailable) {
      if (mounted) {
        // Show an error to the user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'NFC is unavailable or disabled. Please enable it in settings.',
            ),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    // Start the NFC session with foreground dispatch
    // This prevents other apps from intercepting NFC while this screen is active
    NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
      onDiscovered: (NfcTag tag) async {
        // Get tag ID (factory-unique UUID)
        final String nfcTagId = _extractTagId(tag);

        // Save content to Supabase first
        final supabaseSaved = await SupabaseService.saveMemory(
          nfcUuid: nfcTagId,
          tipo: widget.memoryType,
          contenido: widget.memoryStory,
        );

        if (!supabaseSaved) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Cloud save failed. Please check your connection.',
                ),
                backgroundColor: Colors.red.shade700,
                duration: const Duration(seconds: 3),
              ),
            );
          }
          await NfcManager.instance.stopSession();
          return;
        }

        // Write only the UUID to the NFC tag (lightweight)
        bool writeSuccess = await _writeUuidToNFC(tag, nfcTagId);

        if (!writeSuccess) {
          final message =
              _lastWriteError ??
              'Could not write to the NFC tag. It may be read-only.';
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(message),
                backgroundColor: Colors.orange.shade700,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          await NfcManager.instance.stopSession();
          return;
        }

        // Process the detected tag (store locally in the app)
        await _onNFCDetected(nfcTagId);

        // Stop the NFC session after processing
        await NfcManager.instance.stopSession();
      },
    );
  }

  /// Extracts the unique ID from the NFC tag.
  String _extractTagId(NfcTag tag) {
    try {
      // Android
      final androidTag = NfcTagAndroid.from(tag);
      if (androidTag != null && androidTag.id.isNotEmpty) {
        return androidTag.id
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toUpperCase();
      }

      // iOS - MiFare
      final miFareTag = MiFareIos.from(tag);
      if (miFareTag != null && miFareTag.identifier.isNotEmpty) {
        return miFareTag.identifier
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toUpperCase();
      }

      // iOS - ISO15693
      final iso15693Tag = Iso15693Ios.from(tag);
      if (iso15693Tag != null && iso15693Tag.identifier.isNotEmpty) {
        return iso15693Tag.identifier
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toUpperCase();
      }

      // iOS - FeliCa
      final feliCaTag = FeliCaIos.from(tag);
      if (feliCaTag != null && feliCaTag.currentIDm.isNotEmpty) {
        return feliCaTag.currentIDm
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join(':')
            .toUpperCase();
      }
    } catch (e) {
      print('Error extracting tag ID: $e');
    }

    // Fallback if the ID cannot be extracted
    return 'NFC_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Writes only the UUID on the physical NFC tag (plain text format)
  /// Much lighter than writing the full JSON
  Future<bool> _writeUuidToNFC(NfcTag tag, String uuid) async {
    try {
      // Intentar Android primero
      final ndefAndroid = NdefAndroid.from(tag);
      if (ndefAndroid != null) {
        return await _writeUuidToNFCAndroid(ndefAndroid, uuid);
      }

      // Intentar iOS
      final ndefIos = NdefIos.from(tag);
      if (ndefIos != null) {
        return await _writeUuidToNFCIos(ndefIos, uuid);
      }

      print('❌ This NFC tag does not support NDEF');
      return false;
    } catch (e) {
      print('❌ Error writing UUID to NFC: $e');
      return false;
    }
  }

  /// Writes to an Android NFC tag
  /// Stores the UUID on an Android NFC tag (plain text only, no JSON)
  Future<bool> _writeUuidToNFCAndroid(
    NdefAndroid ndefAndroid,
    String uuid,
  ) async {
    try {
      // Check if the tag is writable
      if (!ndefAndroid.isWritable) {
        print('❌ This NFC tag is read-only');
        return false;
      }

      print('📊 Tag capacity: ${ndefAndroid.maxSize} bytes');

      // Create an NDEF message with a text record using the ndef package
      // Store only the plain UUID (much lighter than JSON)
      final textRecord = ndef.TextRecord(
        encoding: ndef.TextEncoding.UTF8,
        language: 'en',
        text: uuid,
      );

      // Encode the record to bytes
      final payload = textRecord.payload;

      final estimatedSize = _estimateTextRecordSize(textRecord);
      print('📦 Estimated UUID size: $estimatedSize bytes (~50 bytes typical)');

      final int capacity = ndefAndroid.maxSize;
      if (capacity > 0 && estimatedSize > capacity) {
        _lastWriteError =
            'The UUID exceeds this tag\'s capacity (${estimatedSize} > $capacity bytes).';
        print('❌ Message too large for the tag (${capacity} bytes)');
        return false;
      }

      // Create an NdefRecord using ndef_record
      final ndefRecord = NdefRecord(
        typeNameFormat: TypeNameFormat.wellKnown,
        type: textRecord.type!,
        identifier: textRecord.id != null
            ? Uint8List.fromList(textRecord.id!)
            : Uint8List(0),
        payload: payload,
      );

      // Create the NDEF message
      final ndefMessage = NdefMessage(records: [ndefRecord]);

      // Write to the NFC tag (OVERWRITES previous content)
      await ndefAndroid.writeNdefMessage(ndefMessage);

      print('✅ UUID successfully written to the NFC tag (Android)');
      print('🔖 UUID: $uuid');

      _lastWriteError = null;

      return true;
    } catch (e) {
      print('❌ Error writing UUID to Android NFC tag: $e');
      _lastWriteError ??= 'Unexpected error while writing to the tag: $e';
      return false;
    }
  }

  /// Writes the UUID on an iOS NFC tag (plain text only, no JSON)
  Future<bool> _writeUuidToNFCIos(NdefIos ndefIos, String uuid) async {
    try {
      // Check status
      if (ndefIos.status == NdefStatusIos.notSupported) {
        print('❌ This NFC tag does not support NDEF');
        return false;
      }

      if (ndefIos.status == NdefStatusIos.readOnly) {
        print('❌ This NFC tag is read-only');
        return false;
      }

      print('📊 Tag capacity: ${ndefIos.capacity} bytes');

      // Create an NDEF message with a text record using the ndef package
      // Store only the plain UUID (much lighter than JSON)
      final textRecord = ndef.TextRecord(
        encoding: ndef.TextEncoding.UTF8,
        language: 'en',
        text: uuid,
      );

      // Encode the record to bytes
      final payload = textRecord.payload;

      final estimatedSize = _estimateTextRecordSize(textRecord);
      print('📦 Estimated UUID size: $estimatedSize bytes (~50 bytes typical)');

      final int capacity = ndefIos.capacity;
      if (capacity > 0 && estimatedSize > capacity) {
        _lastWriteError =
            'The UUID exceeds this tag\'s capacity (${estimatedSize} > $capacity bytes).';
        print('❌ Message too large for the tag (${capacity} bytes)');
        return false;
      }

      // Create an NdefRecord using ndef_record
      final ndefRecord = NdefRecord(
        typeNameFormat: TypeNameFormat.wellKnown,
        type: textRecord.type!,
        identifier: textRecord.id != null
            ? Uint8List.fromList(textRecord.id!)
            : Uint8List(0),
        payload: payload,
      );

      // Create the NDEF message
      final ndefMessage = NdefMessage(records: [ndefRecord]);

      // Write to the NFC tag (OVERWRITES previous content)
      await ndefIos.writeNdef(ndefMessage);

      print('✅ UUID successfully written to the NFC tag (iOS)');
      print('🔖 UUID: $uuid');

      _lastWriteError = null;

      return true;
    } catch (e) {
      print('❌ Error writing UUID to iOS NFC tag: $e');
      _lastWriteError ??= 'Unexpected error while writing to the tag: $e';
      return false;
    }
  }

  int _estimateTextRecordSize(ndef.TextRecord record) {
    final payloadLength = record.payload.length;
    final typeLength = record.type?.length ?? 0;
    final idLength = record.id?.length ?? 0;

    const flagsLength = 1; // header byte (TNF + flags)
    const typeLengthField = 1;
    const payloadLengthField = 4; // use 4 bytes to stay conservative
    final idLengthField = idLength > 0 ? 1 : 0;

    final header =
        flagsLength + typeLengthField + payloadLengthField + idLengthField;

    final size = header + typeLength + idLength + payloadLength;
    return size;
  }

  /// Handles NFC tag detection events.
  Future<void> _onNFCDetected(String nfcTagId) async {
    // Do NOT stop the session yet—we still need to write to the tag

    // Create Memory object
    final memory = Memory(
      id: 'MEM_${DateTime.now().millisecondsSinceEpoch}',
      story: widget.memoryStory,
      nfcTagId: nfcTagId,
      createdAt: DateTime.now(),
    );

    // Save it in the service
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

      // Return to home after showing success
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          Navigator.popUntil(context, (route) => route.isFirst);
        }
      });
    } else {
      // If storing failed, end the session
      await NfcManager.instance.stopSession();
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
            'Create Memory',
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
            'Item detected!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Memory saved successfully!',
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
              'Bring your object close',
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
              'Hold your device near the item with the NFC tag',
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
