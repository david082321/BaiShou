import 'dart:io';

import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:baishou/features/home/presentation/widgets/desktop_sidebar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:baishou/agent/rag/embedding_service.dart';
import 'package:baishou/features/settings/presentation/pages/views/rag_memory_dialogs.dart';
import 'package:baishou/core/widgets/app_toast.dart';
import 'package:baishou/core/router/app_router.dart';
import 'package:baishou/core/providers/shared_preferences_provider.dart';

/// 主级架构视图
///
/// 桌面端：侧边栏 + 内容区（标题栏已提升到 app.dart builder 层）
/// 移动端：底部导航栏（日记 / 总结 / Agent / 设置）
class MainScaffold extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _overlayController;
  DateTime? _lastPressedAt;

  int _defaultBranch = 0;

  void _computeDefaultBranch() {
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      final saved = prefs.getStringList('desktop_sidebar_nav_order');
      if (saved != null && saved.isNotEmpty) {
        _defaultBranch = int.tryParse(saved.first) ?? 0;
      }
    } catch (_) {}
  }

  void _goBranch(int index) {
    debugPrint(
      '[SCAFFOLD_TRACE] _goBranch called with index: $index | previous is: ${widget.navigationShell.currentIndex}',
    );
    widget.navigationShell.goBranch(index, initialLocation: false);
  }

  int _getMobileNavIndex() {
    final currentIndex = widget.navigationShell.currentIndex;
    return currentIndex < 4 ? currentIndex : 0;
  }

  Future<void> _checkHeterogeneousEmbeddings() async {
    // 延迟检查，避免与初始导航动画冲突
    await Future.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;

    try {
      final embeddingService = ref.read(embeddingServiceProvider);
      final hasMismatch = await embeddingService.hasHeterogeneousEmbeddings();

      if (hasMismatch && mounted) {
        final confirmed = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Text(t.agent.rag.migration_mismatch_title),
            content: Text(t.agent.rag.migration_mismatch_content),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(t.agent.rag.migration_later),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(t.agent.rag.migration_continue),
              ),
            ],
          ),
        );

        if (confirmed == true && mounted) {
          RagMemoryDialogs.startMigration(context, ref);
        }
      }
    } catch (e) {
      debugPrint('Error checking heterogeneous embeddings: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _computeDefaultBranch();
    debugPrint(
      '[SCAFFOLD_TRACE] MainScaffold initState called! This means the entire root UI was rebuilt!',
    );
    _overlayController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 0.0, // 初始透明（不遮挡）
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkHeterogeneousEmbeddings();
    });
  }

  @override
  void didUpdateWidget(covariant MainScaffold oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.navigationShell.currentIndex !=
        widget.navigationShell.currentIndex) {
      final oldIndex = oldWidget.navigationShell.currentIndex;
      final newIndex = widget.navigationShell.currentIndex;
      // 仅在进出 Agent（大 Tab 切换）时触发渐变，侧边栏切换不需要
      if (oldIndex == 1 || newIndex == 1) {
        _overlayController.value = 1.0;
        _overlayController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _overlayController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[SCAFFOLD_TRACE] build called | shell index: ${widget.navigationShell.currentIndex}',
    );
    final bool isDesktopOS =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isLargeScreen = constraints.maxWidth >= 700;
        final bool isDesktop = isDesktopOS || isLargeScreen;

        if (isDesktop) {
          return _buildDesktopLayout(context);
        }
        return _buildMobileLayout(context);
      },
    );
  }

  // ─── 桌面端布局（标题栏已在上层） ─────────────────────────────

  Widget _buildDesktopLayout(BuildContext context) {
    final theme = Theme.of(context);
    final isAgent = widget.navigationShell.currentIndex == 1;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Stack(
        children: [
          // 底层：实际内容（始终满透明度）
          Row(
            children: [
              if (!isAgent)
                DesktopSidebar(
                  navigationShell: widget.navigationShell,
                  onBranchChange: _goBranch,
                ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    boxShadow: [
                      if (theme.brightness == Brightness.light)
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 10,
                          offset: const Offset(-5, 0),
                        ),
                    ],
                  ),
                  child: widget.navigationShell,
                ),
              ),
            ],
          ),
          // 顶层：背景色覆盖层，切换时瞬间出现 → 淡出揭示新内容
          IgnorePointer(
            child: FadeTransition(
              opacity: _overlayController,
              child: Container(color: theme.colorScheme.surface),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 移动端布局 ──────────────────────────────────────────────

  Widget _buildMobileLayout(BuildContext context) {
    final currentIndex = widget.navigationShell.currentIndex;

    final GlobalKey<NavigatorState>? activeKey = switch (currentIndex) {
      0 => diaryNavKey,
      1 => agentNavKey,
      2 => summaryNavKey,
      3 => settingsNavKey,
      4 => syncNavKey,
      _ => null,
    };

    final navState = activeKey?.currentState;
    final bool canPopNested = navState?.canPop() ?? false;

    // ⚠️ canPop 必须恒为 false！
    // MIUI 的 WindowOnBackDispatcher 在 canPop 从 true→false 变化时
    // 会向 Flutter Router 发送虚假的路由重置通知（'/'），导致 GoRouter
    // 的 StatefulShellRoute 回到初始分支。固定为 false 可避免此问题。
    Widget content = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;

        // 1. 如果当前分支有嵌套页面可以 pop，优先 pop 嵌套页面
        if (canPopNested) {
          navState?.pop();
          return;
        }

        // 2. 如果不在默认分支，返回默认分支
        if (currentIndex != _defaultBranch) {
          _goBranch(_defaultBranch);
          return;
        }

        // 3. 在默认分支按两次退出
        final now = DateTime.now();
        if (_lastPressedAt == null ||
            now.difference(_lastPressedAt!) > const Duration(seconds: 2)) {
          setState(() {
            _lastPressedAt = now;
          });
          AppToast.show(context, t.common.exit_hint);
          return;
        }

        SystemNavigator.pop();
      },
      child: widget.navigationShell,
    );

    return Scaffold(
      body: Container(
        color: Theme.of(context).colorScheme.surface,
        child: content,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _getMobileNavIndex(),
        onDestinationSelected: _goBranch,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.timeline_outlined),
            selectedIcon: const Icon(Icons.timeline),
            label: t.diary.title,
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_awesome_outlined),
            selectedIcon: const Icon(Icons.auto_awesome_rounded),
            label: t.agent.partner_label,
          ),
          NavigationDestination(
            icon: const Icon(Icons.auto_stories_outlined),
            selectedIcon: const Icon(Icons.auto_stories),
            label: t.summary.dashboard_title,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: t.settings.title,
          ),
        ],
      ),
    );
  }
}
