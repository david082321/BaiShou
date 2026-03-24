import 'package:baishou/core/services/global_hotkey_service.dart';
import 'package:baishou/core/providers/shared_preferences_provider.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局快捷键设置卡片（仅桌面端）
class HotkeySettingsCard extends ConsumerStatefulWidget {
  const HotkeySettingsCard({super.key});

  @override
  ConsumerState<HotkeySettingsCard> createState() =>
      _HotkeySettingsCardState();
}

class _HotkeySettingsCardState extends ConsumerState<HotkeySettingsCard> {
  @override
  Widget build(BuildContext context) {
    final hotkeyService = ref.read(globalHotkeyServiceProvider);
    final prefs = ref.read(sharedPreferencesProvider);
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.keyboard_rounded),
            title: Text(t.settings.hotkey_title),
            subtitle: Text(
              hotkeyService.isEnabled
                  ? t.settings.hotkey_desc_enabled(
                      hotkey: hotkeyService.getHotkeyDisplayString())
                  : t.settings.hotkey_desc_disabled,
            ),
            value: hotkeyService.isEnabled,
            onChanged: (v) async {
              if (v) {
                await hotkeyService.enable(prefs);
              } else {
                await hotkeyService.disable(prefs);
              }
              setState(() {});
            },
          ),
          if (hotkeyService.isEnabled) ...[
            const Divider(height: 1),
            ListTile(
              leading: const SizedBox(width: 24),
              title: Text(t.settings.hotkey_change),
              trailing: ActionChip(
                label: Text(
                  hotkeyService.getHotkeyDisplayString(),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                avatar: const Icon(Icons.edit_rounded, size: 16),
                onPressed: () => _showHotkeyPickerDialog(hotkeyService, prefs),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showHotkeyPickerDialog(
    GlobalHotkeyService hotkeyService,
    SharedPreferences prefs,
  ) async {
    String selectedModifier = hotkeyService.currentModifier;
    String selectedKey = hotkeyService.currentKey;

    const modifierOptions = [
      ('alt', 'Alt'),
      ('ctrl', 'Ctrl'),
      ('shift', 'Shift'),
      ('meta', 'Win / ⌘'),
    ];
    const keyOptions = [
      ('keyA', 'A'), ('keyB', 'B'), ('keyC', 'C'), ('keyD', 'D'),
      ('keyE', 'E'), ('keyF', 'F'), ('keyG', 'G'), ('keyH', 'H'),
      ('keyI', 'I'), ('keyJ', 'J'), ('keyK', 'K'), ('keyL', 'L'),
      ('keyM', 'M'), ('keyN', 'N'), ('keyO', 'O'), ('keyP', 'P'),
      ('keyQ', 'Q'), ('keyR', 'R'), ('keyS', 'S'), ('keyT', 'T'),
      ('keyU', 'U'), ('keyV', 'V'), ('keyW', 'W'), ('keyX', 'X'),
      ('keyY', 'Y'), ('keyZ', 'Z'),
      ('space', 'Space'),
      ('f1', 'F1'), ('f2', 'F2'), ('f3', 'F3'), ('f4', 'F4'),
      ('f5', 'F5'), ('f6', 'F6'), ('f7', 'F7'), ('f8', 'F8'),
      ('f9', 'F9'), ('f10', 'F10'), ('f11', 'F11'), ('f12', 'F12'),
    ];

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final theme = Theme.of(ctx);
          final conflict = _checkHotkeyConflict(selectedModifier, selectedKey);

          return AlertDialog(
            title: Text(t.settings.hotkey_dialog_title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 修饰键选择
                Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(
                        t.settings.hotkey_modifier_label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedModifier,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: modifierOptions
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.$1,
                                child: Text(e.$2),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => selectedModifier = v);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 按键选择
                Row(
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(
                        t.settings.hotkey_key_label,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: selectedKey,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: keyOptions
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.$1,
                                child: Text(e.$2),
                              ),
                            )
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => selectedKey = v);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // 预览
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: conflict
                        ? theme.colorScheme.errorContainer
                            .withValues(alpha: 0.3)
                        : theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        conflict
                            ? Icons.warning_amber_rounded
                            : Icons.keyboard_rounded,
                        size: 18,
                        color: conflict
                            ? theme.colorScheme.error
                            : theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${modifierOptions.firstWhere((e) => e.$1 == selectedModifier).$2}'
                        ' + '
                        '${keyOptions.firstWhere((e) => e.$1 == selectedKey).$2}',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: conflict
                              ? theme.colorScheme.error
                              : theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                // 冲突警告
                if (conflict) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.errorContainer
                          .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: theme.colorScheme.error.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline_rounded,
                          size: 16,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            t.settings.hotkey_conflict_warning,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(t.common.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  conflict ? t.settings.hotkey_use_anyway : t.common.confirm,
                ),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      await hotkeyService.updateHotkey(
        prefs,
        modifier: selectedModifier,
        key: selectedKey,
      );
      setState(() {});
    }
  }

  /// 应用内所有快捷键定义（AI Assistant 模式）
  List<(String id, String modifier, String key)> get _appShortcuts {
    final service = ref.read(globalHotkeyServiceProvider);
    return [
      ('global_show_hide', service.currentModifier, service.currentKey),
    ];
  }

  /// 检查是否与应用内其他快捷键冲突（排除指定 id）
  bool _checkHotkeyConflict(String modifier, String key,
      {String excludeId = 'global_show_hide'}) {
    final candidateCombo = '${modifier.toLowerCase()}+${key.toLowerCase()}';

    for (final shortcut in _appShortcuts) {
      if (shortcut.$1 == excludeId) continue;
      final existingCombo =
          '${shortcut.$2.toLowerCase()}+${shortcut.$3.toLowerCase()}';
      if (candidateCombo == existingCombo) {
        return true;
      }
    }
    return false;
  }
}
