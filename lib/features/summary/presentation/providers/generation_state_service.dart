import 'package:flutter/foundation.dart';

/// 管理 AI 生成状态的服务，用于跨页面持久化状态
/// 使用单例 + ValueNotifier 模式，不依赖 Riverpod 以避免版本/环境问题
class GenerationStateService {
  // 单例模式
  static final GenerationStateService _instance =
      GenerationStateService._internal();
  factory GenerationStateService() => _instance;
  GenerationStateService._internal();

  // 状态
  final ValueNotifier<Map<String, String>> statusNotifier = ValueNotifier({});

  Map<String, String> get statusMap => statusNotifier.value;

  void setStatus(String key, String status) {
    statusNotifier.value = {...statusNotifier.value, key: status};
  }

  void removeStatus(String key) {
    final newState = Map<String, String>.from(statusNotifier.value);
    newState.remove(key);
    statusNotifier.value = newState;
  }

  String? getStatus(String key) => statusNotifier.value[key];
}
