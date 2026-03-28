import 'package:baishou/app.dart';
import 'package:baishou/core/widgets/app_restart_guard.dart';
import 'package:baishou/core/providers/shared_preferences_provider.dart';
import 'package:baishou/core/services/global_hotkey_service.dart';
import 'package:baishou/core/database/app_database.dart';
import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/features/index/data/shadow_index_database.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:baishou/i18n/strings.g.dart';

/// 全局 ProviderContainer 引用，供退出时关闭数据库使用
ProviderContainer? _globalContainer;

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

    // 拦截窗口关闭事件，确保优雅退出
    await windowManager.setPreventClose(true);
    windowManager.addListener(_GracefulExitListener());

    // 初始化全局快捷键服务，先清空僵尸热键
    await hotKeyManager.unregisterAll();
    await GlobalHotkeyService.instance.init(prefs);
  }

  // 创建 ProviderContainer 并保存全局引用
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  _globalContainer = container;

  runApp(
    AppRestartGuard(
      child: TranslationProvider(
        child: UncontrolledProviderScope(
          container: container,
          child: const BaiShouApp(),
        ),
      ),
    ),
  );
}

/// 优雅退出监听器
///
/// 拦截 windowManager.close()，在 Dart 侧按序关闭所有原生数据库连接，
/// 再调用 destroy() 真正销毁进程。
/// 这能彻底消除 Riverpod dispose → SQLite native handle use-after-free 的崩溃。
class _GracefulExitListener extends WindowListener {
  bool _isExiting = false;

  @override
  void onWindowClose() async {
    if (_isExiting) return;
    _isExiting = true;

    debugPrint('GracefulExit: Intercepted close, shutting down gracefully...');

    // ── Step 1: 注销全局快捷键 ──
    try {
      await hotKeyManager.unregisterAll();
      GlobalHotkeyService.instance.dispose();
    } catch (_) {}

    // ── Step 2: 按序关闭全部数据库连接（消除 use-after-free 根因）──
    final container = _globalContainer;
    if (container != null) {
      try {
        // 2a. 关闭影子索引库（sqlite3 直连，同步 close）
        container.read(shadowIndexDatabaseProvider.notifier).close();
        debugPrint('GracefulExit: ShadowIndexDatabase closed.');
      } catch (_) {}

      try {
        // 2b. 关闭主数据库（Drift NativeDatabase，后台 Isolate）
        await closeAppDatabase();
        debugPrint('GracefulExit: AppDatabase closed.');
      } catch (_) {}

      try {
        // 2c. 关闭全部 Agent 数据库（Drift NativeDatabase + sqlite-vec）
        await closeAllAgentDatabases();
        debugPrint('GracefulExit: All AgentDatabases closed.');
      } catch (_) {}
    }

    // ── Step 3: 排空残余微任务 ──
    await Future.delayed(const Duration(milliseconds: 30));

    debugPrint('GracefulExit: All resources released, destroying window.');

    // ── Step 4: 正常销毁窗口（此时所有 native handle 已关闭，不会崩溃）──
    await windowManager.destroy();
  }
}
