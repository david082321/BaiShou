/// 日记轻量元数据（用于 VaultIndex 内存列表）
/// 只包含列表展示和快速检索需要的字段，不含完整内容。
/// 所有条目常驻内存（~300 bytes × 条数），无需分页。
class DiaryMeta {
  final int id;
  final DateTime date;
  final String preview; // 前 120 字符的内容预览
  final List<String> tags;
  final DateTime updatedAt;

  const DiaryMeta({
    required this.id,
    required this.date,
    required this.preview,
    required this.tags,
    required this.updatedAt,
  });

  DiaryMeta copyWith({
    int? id,
    DateTime? date,
    String? preview,
    List<String>? tags,
    DateTime? updatedAt,
  }) {
    return DiaryMeta(
      id: id ?? this.id,
      date: date ?? this.date,
      preview: preview ?? this.preview,
      tags: tags ?? this.tags,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is DiaryMeta && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() =>
      'DiaryMeta(id: $id, date: $date, preview: ${preview.substring(0, preview.length.clamp(0, 20))}...)';
}
