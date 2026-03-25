import 'package:uuid/uuid.dart';

/// 快捷指令模型
class PromptShortcut {
  final String id;
  final String icon; // emoji图标, 例如 "📝"
  final String name;
  final String content;

  PromptShortcut({
    String? id,
    required this.icon,
    required this.name,
    required this.content,
  }) : id = id ?? const Uuid().v4();

  factory PromptShortcut.fromJson(Map<String, dynamic> json) {
    return PromptShortcut(
      id: json['id'] as String?,
      icon: json['icon'] as String? ?? '⚡',
      name: json['name'] as String? ?? '',
      content: json['content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'icon': icon,
      'name': name,
      'content': content,
    };
  }

  PromptShortcut copyWith({
    String? icon,
    String? name,
    String? content,
  }) {
    return PromptShortcut(
      id: id,
      icon: icon ?? this.icon,
      name: name ?? this.name,
      content: content ?? this.content,
    );
  }
}
