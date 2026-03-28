import 'package:baishou/app.dart';
import 'package:baishou/core/widgets/app_restart_guard.dart';
import 'package:baishou/core/providers/shared_preferences_provider.dart';
import 'package:baishou/core/services/global_hotkey_service.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:baishou/i18n/strings.g.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await initializeDateFormatting();

  final prefs = await SharedPreferences.getInstance();

  // 提前初始化语言设置，防止首帧显示错误的默认语言
  final localeTag = prefs.getString('app_locale');
  if (localeTag != null) {
    try {
      final locale = AppLocaleUtils.parse(localeTag);
      await LocaleSettings.setLocale(locale);
    } catch (_) {
      await LocaleSettings.useDeviceLocale();
    }
  } else {
    await LocaleSettings.useDeviceLocale();
  }

  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    await windowManager.ensureInitialized();
    WindowOptions windowOptions = WindowOptions(
      minimumSize: const Size(1200, 800),
      center: true,
      title: t.common.app_tagline,
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: Colors.transparent,
    );
    windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    // 拦截窗口关闭事件，确保优雅退出（先清理 SQLite 等原生资源再销毁进程）
    await windowManager.setPreventClose(true);
    windowManager.addListener(_GracefulExitListener());

    // 初始化全局快捷键服务，先清空僵尸热键
    await hotKeyManager.unregisterAll();
    await GlobalHotkeyService.instance.init(prefs);
  }

  runApp(
    AppRestartGuard(
      child: TranslationProvider(
        child: ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const BaiShouApp(),
        ),
      ),
    ),
  );
}

/// 优雅退出监听器
///
/// 拦截 windowManager.close()，在 Dart 侧先完成所有原生资源的清理，
/// 再调用 destroy() 真正销毁进程。
/// 这能彻底规避 Riverpod dispose → SQLite native handle use-after-free 的崩溃。
class _GracefulExitListener extends WindowListener {
  bool _isExiting = false;

  @override
  void onWindowClose() async {
    if (_isExiting) return;
    _isExiting = true;

    debugPrint('GracefulExit: Intercepted close, hiding window...');

    // 1. 立即隐藏窗口 —— 即使后续析构阶段 native 层崩溃弹出错误框，用户也看不到
    try {
      await windowManager.setSkipTaskbar(true);
      await windowManager.hide();
    } catch (_) {}

    // 2. 注销全局快捷键
    try {
      await hotKeyManager.unregisterAll();
      GlobalHotkeyService.instance.dispose();
    } catch (_) {}

    // 3. 极短的排空窗口，让飞行中的异步操作落地
    await Future.delayed(const Duration(milliseconds: 50));

    // 4. 直接终止进程，由 OS 回收所有资源
    exit(0);
  }
}
