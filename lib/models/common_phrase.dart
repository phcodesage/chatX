/// Model for common phrases used in quick messaging
class CommonPhrase {
  final int? id;
  final String phrase;
  final int usageCount;
  final bool isDefault;
  final bool isCustom;

  const CommonPhrase({
    required this.id,
    required this.phrase,
    required this.usageCount,
    required this.isDefault,
    required this.isCustom,
  });

  factory CommonPhrase.fromJson(Map<String, dynamic> json) {
    return CommonPhrase(
      id: json['id'] as int?,
      phrase: (json['phrase'] ?? '').toString(),
      usageCount: (json['usage_count'] ?? 0) as int,
      isDefault: (json['is_default'] ?? false) as bool,
      isCustom: (json['is_custom'] ?? false) as bool,
    );
  }

  @override
  String toString() =>
      'CommonPhrase(id: $id, phrase: $phrase, usageCount: $usageCount, isDefault: $isDefault, isCustom: $isCustom)';
}
