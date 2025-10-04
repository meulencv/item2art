import 'package:flutter/foundation.dart';
import '../models/memory.dart';

class MemoryService {
  // Simulación de almacenamiento en memoria (más tarde podría ser SharedPreferences o SQLite)
  static final Map<String, Memory> _memories = {};

  // Guardar un nuevo recuerdo
  Future<bool> saveMemory(Memory memory) async {
    try {
      _memories[memory.nfcTagId] = memory;

      if (kDebugMode) {
        print('✅ Recuerdo guardado exitosamente:');
        print('   ID: ${memory.id}');
        print('   NFC Tag: ${memory.nfcTagId}');
        print(
          '   Historia: ${memory.story.substring(0, memory.story.length > 50 ? 50 : memory.story.length)}...',
        );
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error al guardar recuerdo: $e');
      }
      return false;
    }
  }

  // Obtener recuerdo por NFC Tag ID
  Memory? getMemoryByNfcTag(String nfcTagId) {
    return _memories[nfcTagId];
  }

  // Obtener todos los recuerdos
  List<Memory> getAllMemories() {
    return _memories.values.toList();
  }

  // Eliminar un recuerdo
  bool deleteMemory(String nfcTagId) {
    return _memories.remove(nfcTagId) != null;
  }

  // Obtener cantidad de recuerdos
  int getMemoryCount() {
    return _memories.length;
  }
}
