class Memory {
  final String id;
  final String story;
  final String nfcTagId;
  final DateTime createdAt;

  Memory({
    required this.id,
    required this.story,
    required this.nfcTagId,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'story': story,
      'nfcTagId': nfcTagId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Memory.fromJson(Map<String, dynamic> json) {
    return Memory(
      id: json['id'] as String,
      story: json['story'] as String,
      nfcTagId: json['nfcTagId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
