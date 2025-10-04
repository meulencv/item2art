import 'package:supabase_flutter/supabase_flutter.dart';

/// Servicio para interactuar con Supabase
/// TODO: Mover URL y ANON_KEY a variables de entorno o backend seguro
class SupabaseService {
  static const String _supabaseUrl = 'https://zepcazomutywgatdchpc.supabase.co';
  // anon public key (NO es secreta como la service_role, pero evita exponerla en repos públicos)
  static const String _supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InplcGNhem9tdXR5d2dhdGRjaHBjIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk1NDk2OTksImV4cCI6MjA3NTEyNTY5OX0.RdWEzDHYF9a4EXmTkRxgMUM3Das8rOD6L1wtJDbsfQY';

  static SupabaseClient? _client;

  /// Inicializa Supabase (llamar una vez al inicio de la app)
  static Future<void> initialize() async {
    if (_client != null) return;

    await Supabase.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
    _client = Supabase.instance.client;
  }

  /// Obtiene el cliente de Supabase (asegura que esté inicializado)
  static SupabaseClient get client {
    if (_client == null) {
      throw Exception(
        'Supabase no está inicializado. Llama a SupabaseService.initialize() primero.',
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
    try {
      final data = {'nfc_uuid': nfcUuid, 'tipo': tipo, 'contenido': contenido};

      await client.from('memories').upsert(data);

      print('✅ Recuerdo guardado en Supabase');
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
