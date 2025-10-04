import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Service responsible for interacting with Supabase.
/// Loads configuration from environment variables (.env).
class SupabaseService {
  static final String _supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  static final String _supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  static SupabaseClient? _client;

  static bool get isConfigured =>
      _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

  static bool get isInitialized => _client != null;

  /// Initializes Supabase (call once at app startup).
  static Future<void> initialize() async {
    if (_client != null) return;
    if (!isConfigured) {
      // Do not throw: just log so the app keeps running.
      // We can later surface UI if Supabase becomes mandatory.
      // ignore: avoid_print
      print(
        '⚠️ Supabase not configured (missing SUPABASE_URL / SUPABASE_ANON_KEY)',
      );
      return;
    }

    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
    _client = Supabase.instance.client;
    // ignore: avoid_print
    print('✅ Supabase initialized');
  }

  /// Retrieves the Supabase client (ensures it is initialized).
  static SupabaseClient get client {
    if (_client == null) {
      throw Exception(
        'Supabase is not initialized. Configure variables and call SupabaseService.initialize().',
      );
    }
    return _client!;
  }

  /// Saves a memory in Supabase using the NFC card UUID.
  /// Returns true when the operation succeeds.
  /// Note: parameter names remain in Spanish (`tipo`, `contenido`) to match the Supabase schema.
  static Future<bool> saveMemory({
    required String nfcUuid,
    required String tipo,
    required String contenido,
  }) async {
    if (!isInitialized) {
      print('⚠️ Skipped save: Supabase not initialized');
      return false;
    }
    try {
      final normalizedTipo = _normalizeTipo(tipo);
      final data = {
        'nfc_uuid': nfcUuid,
        'tipo': normalizedTipo,
        'contenido': contenido,
      };

      final response = await client
          .from('memories')
          .upsert(data, onConflict: 'nfc_uuid')
          .select();

      final updated = response.isNotEmpty;
      print(
        updated
            ? '♻️ Memory updated in Supabase'
            : '✅ Memory saved in Supabase',
      );
      print('   UUID: $nfcUuid');
      print('   Type (raw): $tipo');
      print('   Type (normalized): $normalizedTipo');
      print(
        '   Content: ${contenido.substring(0, contenido.length > 50 ? 50 : contenido.length)}...',
      );

      return true;
    } catch (e) {
      print('❌ Error saving to Supabase: $e');
      return false;
    }
  }

  static String _normalizeTipo(String tipo) {
    final lower = tipo.toLowerCase();
    switch (lower) {
      case 'story':
      case 'historia':
        return 'historia';
      case 'music':
      case 'música':
      case 'musica':
        return 'musica';
      case 'image':
      case 'imagen':
        return 'imagen';
      default:
        return lower;
    }
  }

  /// Fetches a memory from Supabase using the NFC card UUID.
  /// Returns a map containing 'tipo' and 'contenido'.
  static Future<Map<String, dynamic>?> getMemoryByUuid(String nfcUuid) async {
    if (!isInitialized) {
      print('⚠️ Skipped read: Supabase not initialized');
      return null;
    }
    try {
      final response = await client
          .from('memories')
          .select('tipo, contenido')
          .eq('nfc_uuid', nfcUuid)
          .maybeSingle();

      if (response == null) {
        print('⚠️ No memory found for UUID: $nfcUuid');
        return null;
      }

      print('✅ Memory retrieved from Supabase');
      print('   UUID: $nfcUuid');
      print("   Type: ${response['tipo']}");

      return {
        'tipo': response['tipo'] as String,
        'contenido': response['contenido'] as String,
      };
    } catch (e) {
      print('❌ Error fetching memory from Supabase: $e');
      return null;
    }
  }

  /// Deletes a memory from Supabase using the UUID.
  static Future<bool> deleteMemory(String nfcUuid) async {
    if (!isInitialized) {
      print('⚠️ Skipped delete: Supabase not initialized');
      return false;
    }
    try {
      await client.from('memories').delete().eq('nfc_uuid', nfcUuid);
      print('✅ Memory deleted from Supabase (UUID: $nfcUuid)');
      return true;
    } catch (e) {
      print('❌ Error deleting memory from Supabase: $e');
      return false;
    }
  }
}
