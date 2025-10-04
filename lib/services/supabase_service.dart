import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Servicio para interactuar con Supabase
/// Carga configuración desde variables de entorno (.env)
class SupabaseService {
  static final String _supabaseUrl = dotenv.env['SUPABASE_URL'] ?? '';
  static final String _supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY'] ?? '';

  static SupabaseClient? _client;

  static bool get isConfigured =>
      _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

  static bool get isInitialized => _client != null;

  /// Inicializa Supabase (llamar una vez al inicio de la app)
  static Future<void> initialize() async {
    if (_client != null) return;
    if (!isConfigured) {
      // No lanzar excepción: solo log para no bloquear la app
      // Podremos mostrar una UI más adelante si se requiere Supabase.
      // ignore: avoid_print
      print(
        '⚠️ Supabase no configurado (faltan SUPABASE_URL / SUPABASE_ANON_KEY)',
      );
      return;
    }

    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
    _client = Supabase.instance.client;
    // ignore: avoid_print
    print('✅ Supabase inicializado');
  }

  /// Obtiene el cliente de Supabase (asegura que esté inicializado)
  static SupabaseClient get client {
    if (_client == null) {
      throw Exception(
        'Supabase no está inicializado. Configura variables y llama a SupabaseService.initialize().',
      );
    }
    return _client!;
  }

  /// Guarda un recuerdo en Supabase usando el UUID de la tarjeta NFC
  /// Retorna true si se guardó exitosamente
  static Future<bool> saveMemory({
    required String nfcUuid,
    required String tipo,
    required String contenido,
  }) async {
    if (!isInitialized) {
      print('⚠️ Guardado omitido: Supabase no inicializado');
      return false;
    }
    try {
      final data = {'nfc_uuid': nfcUuid, 'tipo': tipo, 'contenido': contenido};

      final response = await client
          .from('memories')
          .upsert(data, onConflict: 'nfc_uuid')
          .select();

      final updated = response.isNotEmpty;
      print(
        updated
            ? '♻️ Recuerdo actualizado en Supabase'
            : '✅ Recuerdo guardado en Supabase',
      );
      print('   UUID: $nfcUuid');
      print('   Tipo: $tipo');
      print(
        '   Contenido: ${contenido.substring(0, contenido.length > 50 ? 50 : contenido.length)}...',
      );

      return true;
    } catch (e) {
      print('❌ Error al guardar en Supabase: $e');
      return false;
    }
  }

  /// Obtiene un recuerdo desde Supabase usando el UUID de la tarjeta NFC
  /// Retorna un Map con 'tipo' y 'contenido'
  static Future<Map<String, dynamic>?> getMemoryByUuid(String nfcUuid) async {
    if (!isInitialized) {
      print('⚠️ Lectura omitida: Supabase no inicializado');
      return null;
    }
    try {
      final response = await client
          .from('memories')
          .select('tipo, contenido')
          .eq('nfc_uuid', nfcUuid)
          .maybeSingle();

      if (response == null) {
        print('⚠️ No se encontró recuerdo para UUID: $nfcUuid');
        return null;
      }

      print('✅ Recuerdo recuperado desde Supabase');
      print('   UUID: $nfcUuid');
      print('   Tipo: ${response['tipo']}');

      return {
        'tipo': response['tipo'] as String,
        'contenido': response['contenido'] as String,
      };
    } catch (e) {
      print('❌ Error al obtener recuerdo desde Supabase: $e');
      return null;
    }
  }

  /// Elimina un recuerdo de Supabase usando el UUID
  static Future<bool> deleteMemory(String nfcUuid) async {
    if (!isInitialized) {
      print('⚠️ Eliminación omitida: Supabase no inicializado');
      return false;
    }
    try {
      await client.from('memories').delete().eq('nfc_uuid', nfcUuid);
      print('✅ Recuerdo eliminado de Supabase (UUID: $nfcUuid)');
      return true;
    } catch (e) {
      print('❌ Error al eliminar recuerdo de Supabase: $e');
      return false;
    }
  }
}
