import 'package:flutter/services.dart';

/// Servicio para controlar el modo exclusivo NFC en Android.
/// En iOS no aplica (el sistema ya presenta su propia UI controlada).
class NfcForegroundService {
  static const MethodChannel _channel = MethodChannel('nfc_foreground');

  static Future<bool> enable() async {
    try {
      final ok = await _channel.invokeMethod<bool>('enableExclusive');
      return ok ?? false;
    } catch (e) {
      return false;
    }
  }

  static Future<void> disable() async {
    try {
      await _channel.invokeMethod('disableExclusive');
    } catch (_) {}
  }
}
