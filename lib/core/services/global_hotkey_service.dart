/// 全局快捷键服务（桌面端系统级）
///
/// 使用 hotkey_manager 注册系统级全局热键，实现窗口显隐切换。
/// 默认关闭，用户可在设置中开启并自定义快捷键（默认 Alt+S）。
///
/// 仅在 Windows/macOS/Linux 桌面端生效。

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

// ─── SharedPreferences 键名 ───
const _kHotkeyEnabled = 'global_hotkey_enabled';
const _kHotkeyModifier = 'global_hotkey_modifier';
const _kHotkeyKey = 'global_hotkey_key';

/// 全局快捷键服务 Provider（单例）
final globalHotkeyServiceProvider = Provider<GlobalHotkeyService>((ref) {
  return GlobalHotkeyService.instance;
});

class GlobalHotkeyService {
  GlobalHotkeyService._();
  static final GlobalHotkeyService instance = GlobalHotkeyService._();

  HotKey? _currentHotKey;
  bool _isEnabled = false;

  bool get isEnabled => _isEnabled;
  String get currentModifier => _modifier;
  String get currentKey => _key;

  String _modifier = 'alt';
  String _key = 'keyS';

  /// 初始化：从 SharedPreferences 读取配置并注册热键
  Future<void> init(SharedPreferences prefs) async {
    if (kIsWeb ||
        !(Platform.isWindows || Platform.isMacOS || Platform.isLinux)) {
      return;
    }

    // 清理可能残留的各种全局热键（特别是开发期热重载后，或上一次异常退出）
    await hotKeyManager.unregisterAll();

    _isEnabled = prefs.getBool(_kHotkeyEnabled) ?? false;
    _modifier = prefs.getString(_kHotkeyModifier) ?? 'alt';
    _key = prefs.getString(_kHotkeyKey) ?? 'keyS';

    if (_isEnabled) {
      await _register();
    }
  }

  /// 启用全局快捷键
  Future<void> enable(SharedPreferences prefs) async {
    _isEnabled = true;
    await prefs.setBool(_kHotkeyEnabled, true);
    await _register();
  }

  /// 禁用全局快捷键
  Future<void> disable(SharedPreferences prefs) async {
    _isEnabled = false;
    await prefs.setBool(_kHotkeyEnabled, false);
    await _unregister();
  }

  /// 更新快捷键
  Future<void> updateHotkey(
    SharedPreferences prefs, {
    required String modifier,
    required String key,
  }) async {
    _modifier = modifier;
    _key = key;
    await prefs.setString(_kHotkeyModifier, modifier);
    await prefs.setString(_kHotkeyKey, key);

    if (_isEnabled) {
      await _unregister();
      await _register();
    }
  }

  Future<void> _register() async {
    final keyModifier = parseModifier(_modifier);
    final physicalKey = parsePhysicalKey(_key);
    if (physicalKey == null) return;

    _currentHotKey = HotKey(
      key: physicalKey,
      modifiers: keyModifier != null ? [keyModifier] : [],
      scope: HotKeyScope.system,
    );

    // 注册前先尝试注销确保唯一性
    await hotKeyManager.unregister(_currentHotKey!);
    await hotKeyManager.register(
      _currentHotKey!,
      keyDownHandler: (_) => _toggleWindow(),
    );
  }

  Future<void> _unregister() async {
    if (_currentHotKey != null) {
      await hotKeyManager.unregister(_currentHotKey!);
      _currentHotKey = null;
    }
  }

  Future<void> _toggleWindow() async {
    try {
      final isMinimized = await windowManager.isMinimized();
      final isVisible = await windowManager.isVisible();
      final isFocused = await windowManager.isFocused();

      // 当窗口可见并且拥有焦点时，执行隐藏
      if (isVisible && !isMinimized && isFocused) {
        await windowManager.hide();
      } else {
        if (isMinimized) {
          await windowManager.restore();
        }
        if (!isVisible) {
          await windowManager.show();
        }
        // 强制要求焦点并将窗口移至最前
        await windowManager.focus();
        if (Platform.isWindows) {
          await windowManager.setSkipTaskbar(false);
          await windowManager.setAlwaysOnTop(true);
          await windowManager.setAlwaysOnTop(false);
        }
      }
    } catch (e) {
      debugPrint('GlobalHotkeyService: toggle window failed: $e');
    }
  }


  void dispose() {
    _unregister();
  }

  static HotKeyModifier? parseModifier(String mod) {
    switch (mod.toLowerCase()) {
      case 'alt':
        return HotKeyModifier.alt;
      case 'ctrl':
      case 'control':
        return HotKeyModifier.control;
      case 'shift':
        return HotKeyModifier.shift;
      case 'meta':
      case 'win':
      case 'cmd':
        return HotKeyModifier.meta;
      default:
        return HotKeyModifier.alt;
    }
  }

  static PhysicalKeyboardKey? parsePhysicalKey(String key) {
    switch (key.toLowerCase()) {
      case 'keys':
        return PhysicalKeyboardKey.keyS;
      case 'keya':
        return PhysicalKeyboardKey.keyA;
      case 'keyb':
        return PhysicalKeyboardKey.keyB;
      case 'keyc':
        return PhysicalKeyboardKey.keyC;
      case 'keyd':
        return PhysicalKeyboardKey.keyD;
      case 'keye':
        return PhysicalKeyboardKey.keyE;
      case 'keyf':
        return PhysicalKeyboardKey.keyF;
      case 'keyg':
        return PhysicalKeyboardKey.keyG;
      case 'keyh':
        return PhysicalKeyboardKey.keyH;
      case 'keyi':
        return PhysicalKeyboardKey.keyI;
      case 'keyj':
        return PhysicalKeyboardKey.keyJ;
      case 'keyk':
        return PhysicalKeyboardKey.keyK;
      case 'keyl':
        return PhysicalKeyboardKey.keyL;
      case 'keym':
        return PhysicalKeyboardKey.keyM;
      case 'keyn':
        return PhysicalKeyboardKey.keyN;
      case 'keyo':
        return PhysicalKeyboardKey.keyO;
      case 'keyp':
        return PhysicalKeyboardKey.keyP;
      case 'keyq':
        return PhysicalKeyboardKey.keyQ;
      case 'keyr':
        return PhysicalKeyboardKey.keyR;
      case 'keyt':
        return PhysicalKeyboardKey.keyT;
      case 'keyu':
        return PhysicalKeyboardKey.keyU;
      case 'keyv':
        return PhysicalKeyboardKey.keyV;
      case 'keyw':
        return PhysicalKeyboardKey.keyW;
      case 'keyx':
        return PhysicalKeyboardKey.keyX;
      case 'keyy':
        return PhysicalKeyboardKey.keyY;
      case 'keyz':
        return PhysicalKeyboardKey.keyZ;
      case 'space':
        return PhysicalKeyboardKey.space;
      case 'f1':
        return PhysicalKeyboardKey.f1;
      case 'f2':
        return PhysicalKeyboardKey.f2;
      case 'f3':
        return PhysicalKeyboardKey.f3;
      case 'f4':
        return PhysicalKeyboardKey.f4;
      case 'f5':
        return PhysicalKeyboardKey.f5;
      case 'f6':
        return PhysicalKeyboardKey.f6;
      case 'f7':
        return PhysicalKeyboardKey.f7;
      case 'f8':
        return PhysicalKeyboardKey.f8;
      case 'f9':
        return PhysicalKeyboardKey.f9;
      case 'f10':
        return PhysicalKeyboardKey.f10;
      case 'f11':
        return PhysicalKeyboardKey.f11;
      case 'f12':
        return PhysicalKeyboardKey.f12;
      default:
        return PhysicalKeyboardKey.keyS;
    }
  }

  /// 获取人类可读的快捷键描述
  String getHotkeyDisplayString() {
    final modStr = switch (_modifier.toLowerCase()) {
      'alt' => 'Alt',
      'ctrl' || 'control' => 'Ctrl',
      'shift' => 'Shift',
      'meta' || 'win' || 'cmd' => Platform.isMacOS ? '⌘' : 'Win',
      _ => _modifier,
    };
    final keyStr = _key
        .replaceFirst(RegExp(r'^key', caseSensitive: false), '')
        .toUpperCase();
    return '$modStr + $keyStr';
  }
}
