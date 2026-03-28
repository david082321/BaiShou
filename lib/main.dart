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
    // 防止重入（用户疯狂点关闭按钮）
    if (_isExiting) return;
    _isExiting = true;

    debugPrint('GracefulExit: Intercepted close, cleaning up resources...');

    try {
      // 1. 注销全局快捷键（避免进程残留时仍拦截系统热键）
      await hotKeyManager.unregisterAll();
      GlobalHotkeyService.instance.dispose();
    } catch (e) {
      debugPrint('GracefulExit: Hotkey cleanup failed (non-fatal): $e');
    }

    // 2. 给异步操作一个极短的排空窗口
    //    让尚在飞行中的 Future（如 DB write、Stream listener callback）有机会完成
    await Future.delayed(const Duration(milliseconds: 100));

    debugPrint('GracefulExit: All resources cleaned up, destroying window.');

    // 3. 真正销毁窗口（此后进程退出，Riverpod 的 onDispose 会自动触发 DB close）
    await windowManager.destroy();
  }
}
