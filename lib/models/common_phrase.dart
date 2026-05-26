/// Model for common phrases used in quick messaging
class CommonPhrase {
  final int? id;
  final String phrase;
  final int usageCount;
  final bool isDefault;
  final bool isCustom;
  final int? pinOrderWeb;
  final int? pinOrderMobile;
  final DateTime? lastUsedAt;

  const CommonPhrase({
    required this.id,
    required this.phrase,
    required this.usageCount,
    required this.isDefault,
    required this.isCustom,
    this.pinOrderWeb,
    this.pinOrderMobile,
    this.lastUsedAt,
  });

  /// Whether this phrase is pinned on mobile
  bool get isPinnedMobile => pinOrderMobile != null;

  /// Whether this phrase is pinned on web
  bool get isPinnedWeb => pinOrderWeb != null;

  factory CommonPhrase.fromJson(Map<String, dynamic> json) {
    return CommonPhrase(
      id: json['id'] as int?,
      phrase: (json['phrase'] ?? '').toString(),
      usageCount: (json['usage_count'] ?? 0) as int,
      isDefault: (json['is_default'] ?? false) as bool,
      isCustom: (json['is_custom'] ?? false) as bool,
      pinOrderWeb: json['pin_order_web'] as int?,
      pinOrderMobile: json['pin_order_mobile'] as int?,
      lastUsedAt: json['last_used_at'] != null
          ? DateTime.tryParse(json['last_used_at'].toString())
          : null,
    );
  }

  @override
  String toString() =>
      'CommonPhrase(id: $id, phrase: $phrase, usageCount: $usageCount, '
      'isDefault: $isDefault, isCustom: $isCustom, '
      'pinnedMobile: $isPinnedMobile, pinnedWeb: $isPinnedWeb)';
}
