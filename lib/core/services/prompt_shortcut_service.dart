import 'dart:convert';
import 'package:baishou/agent/models/prompt_shortcut.dart';
import 'package:baishou/core/providers/shared_preferences_provider.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'prompt_shortcut_service.g.dart';

@riverpod
class PromptShortcutService extends _$PromptShortcutService {
  static const String _storageKey = 'prompt_shortcuts_v2';

  @override
  List<PromptShortcut> build() {
    return _loadShortcuts();
  }

  List<PromptShortcut> _loadShortcuts() {
    final prefs = ref.read(sharedPreferencesProvider);
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) {
      // 默认快捷指令
      return [
        PromptShortcut(
          icon: '🌐',
          name: t.agent.tools.shortcuts.translate_name,
          content: t.agent.tools.shortcuts.translate_content,
        ),
        PromptShortcut(
          icon: '📝',
          name: t.agent.tools.shortcuts.summarize_name,
          content: t.agent.tools.shortcuts.summarize_content,
        ),
      ];
    }

    try {
      final list = jsonDecode(jsonStr) as List;
      return list
          .map((e) => PromptShortcut.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> _saveShortcuts(List<PromptShortcut> list) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final jsonStr = jsonEncode(list.map((e) => e.toJson()).toList());
    await prefs.setString(_storageKey, jsonStr);
    state = list;
  }

  Future<void> addShortcut(PromptShortcut shortcut) async {
    final newList = [...state, shortcut];
    await _saveShortcuts(newList);
  }

  Future<void> updateShortcut(PromptShortcut shortcut) async {
    final newList = state
        .map((e) => e.id == shortcut.id ? shortcut : e)
        .toList();
    await _saveShortcuts(newList);
  }

  Future<void> removeShortcut(String id) async {
    final newList = state.where((e) => e.id != id).toList();
    await _saveShortcuts(newList);
  }

  Future<void> reorderShortcuts(int oldIndex, int newIndex) async {
    final newList = List<PromptShortcut>.from(state);
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = newList.removeAt(oldIndex);
    newList.insert(newIndex, item);
    await _saveShortcuts(newList);
  }
}
