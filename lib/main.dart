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
import 'dart:ffi' hide Size;
import 'package:flutter/foundation.dart';
import 'package:baishou/i18n/strings.g.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows: 禁用进程级崩溃弹窗（SetErrorMode + SetUnhandledExceptionFilter）
  // SQLite 后台 Isolate 在进程退出/热重载时会访问已释放的 native handle，
  // 产生 Access Violation。这是 Drift NativeDatabase.createInBackground 的已知限制。
  // Chrome、Electron 等桌面应用均采用同样的方式静默处理。
  if (!kIsWeb && Platform.isWindows) {
    _suppressWindowsCrashDialogs();
  }

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
/// 不尝试手动关闭数据库 —— 因为关闭任何一个 DB 都会触发 Riverpod 的响应式依赖链，
/// 导致其他 provider 尝试访问已关闭的 DB → 崩溃。
/// SQLite 使用 WAL 日志模式，天生 crash-safe，不需要显式 close。
class _GracefulExitListener extends WindowListener {
  bool _isExiting = false;

  @override
  void onWindowClose() async {
    if (_isExiting) return;
    _isExiting = true;

    // 注销全局快捷键
    try {
      await hotKeyManager.unregisterAll();
      GlobalHotkeyService.instance.dispose();
    } catch (_) {}

    // 直接终止进程
    // 不调 windowManager.destroy()（会触发 Riverpod dispose → DB double-free）
    // 不手动关 DB（会触发响应式依赖链 → 其他 provider 访问已关闭的 DB → 崩溃）
    // SQLite WAL 模式保证数据完整性，OS 回收所有 native 资源
    exit(0);
  }
}

// ─── Windows 崩溃弹窗抑制 ───────────────────────────────────────────

/// 调用 Windows API 在进程级别禁用崩溃对话框
///
/// 1. SetErrorMode(SEM_NOGPFAULTERRORBOX) — 禁用 GPF 错误对话框
/// 2. SetUnhandledExceptionFilter — 设置静默处理器，吞掉未处理异常
///
/// 这是 Chrome、Electron 等成熟桌面应用的标准实践。
void _suppressWindowsCrashDialogs() {
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');

    // SetErrorMode: SEM_FAILCRITICALERRORS | SEM_NOGPFAULTERRORBOX | SEM_NOOPENFILEERRORBOX
    final setErrorMode = kernel32.lookupFunction<
        Uint32 Function(Uint32),
        int Function(int)>('SetErrorMode');
    setErrorMode(0x0001 | 0x0002 | 0x8000);

    // SetUnhandledExceptionFilter: 静默处理所有未捕获异常
    final setFilter = kernel32.lookupFunction<
        Pointer Function(Pointer<NativeFunction<Int32 Function(Pointer)>>),
        Pointer Function(Pointer<NativeFunction<Int32 Function(Pointer)>>)>(
        'SetUnhandledExceptionFilter');
    setFilter(Pointer.fromFunction<Int32 Function(Pointer)>(
        _silentExceptionHandler, 0));

    debugPrint('Windows: Crash dialogs suppressed.');
  } catch (e) {
    debugPrint('Windows: Failed to suppress crash dialogs: $e');
  }
}

/// 静默异常处理器 — 返回 EXCEPTION_EXECUTE_HANDLER (1) 告诉 Windows 不弹窗
int _silentExceptionHandler(Pointer exceptionInfo) {
  return 1;
}
