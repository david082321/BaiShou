import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/shared_preferences_provider.dart';

class AppThemeState {
  final ThemeMode mode;
  final Color seedColor;

  const AppThemeState({required this.mode, required this.seedColor});

  AppThemeState copyWith({ThemeMode? mode, Color? seedColor}) {
    return AppThemeState(
      mode: mode ?? this.mode,
      seedColor: seedColor ?? this.seedColor,
    );
  }
}

class ThemeNotifier extends Notifier<AppThemeState> {
  static const String _keyThemeMode = 'theme_mode';
  static const String _keySeedColor = 'theme_seed_color';

  late SharedPreferences _prefs;

  /// 白守品牌专属浅蓝（与外观设置唯一色盘选项一致）
  static const int _brandBlue = 0xFF9AD4EA;

  @override
  AppThemeState build() {
    _prefs = ref.watch(sharedPreferencesProvider);

    // [v3 一次性迁移] 老用户升级后统一重置为品牌色
    final hasMigratedColor = _prefs.getBool('migrated_seed_color_v3') ?? false;
    if (!hasMigratedColor) {
      _prefs.setInt(_keySeedColor, _brandBlue);
      _prefs.setBool('migrated_seed_color_v3', true);
    }

    final modeIndex = _prefs.getInt(_keyThemeMode) ?? ThemeMode.system.index;
    final colorValue = _prefs.getInt(_keySeedColor) ?? _brandBlue;

    return AppThemeState(
      mode: ThemeMode.values[modeIndex],
      seedColor: Color(colorValue),
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs.setInt(_keyThemeMode, mode.index);
    state = state.copyWith(mode: mode);
  }

  Future<void> setSeedColor(Color color) async {
    await _prefs.setInt(_keySeedColor, color.value);
    state = state.copyWith(seedColor: color);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, AppThemeState>(
  ThemeNotifier.new,
);
