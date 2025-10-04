import 'package:flutter/foundation.dart';
import '../models/memory.dart';

class MemoryService {
  // In-memory storage simulation (could become SharedPreferences or SQLite later).
  static final Map<String, Memory> _memories = {};

  // Save a new memory.
  Future<bool> saveMemory(Memory memory) async {
    try {
      _memories[memory.nfcTagId] = memory;

      if (kDebugMode) {
        print('✅ Memory saved successfully:');
        print('   ID: ${memory.id}');
        print('   NFC Tag: ${memory.nfcTagId}');
        print(
          '   Story: ${memory.story.substring(0, memory.story.length > 50 ? 50 : memory.story.length)}...',
        );
      }

      return true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ Error saving memory: $e');
      }
      return false;
    }
  }

  // Get a memory by NFC tag ID.
  Memory? getMemoryByNfcTag(String nfcTagId) {
    return _memories[nfcTagId];
  }

  // Retrieve all memories.
  List<Memory> getAllMemories() {
    return _memories.values.toList();
  }

  // Delete a memory.
  bool deleteMemory(String nfcTagId) {
    return _memories.remove(nfcTagId) != null;
  }

  // Retrieve the total number of memories.
  int getMemoryCount() {
    return _memories.length;
  }
}
