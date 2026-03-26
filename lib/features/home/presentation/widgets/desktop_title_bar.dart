import 'dart:io';

import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:baishou/features/diary/presentation/pages/diary_list_page.dart';
import 'package:baishou/core/storage/vault_service.dart';

/// 桌面端自定义标题栏
///
/// 放在 MaterialApp.builder 层级，始终显示在所有路由之上。
/// 包含标签切换（记忆/Agent）、设置按钮、窗口控制按钮。
class DesktopTitleBar extends ConsumerStatefulWidget {
  final Widget child;
  final GoRouter router;

  const DesktopTitleBar({super.key, required this.child, required this.router});

  @override
  ConsumerState<DesktopTitleBar> createState() => _DesktopTitleBarState();
}

class _DesktopTitleBarState extends ConsumerState<DesktopTitleBar>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _currentLocation = '/';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_onTabChanged);
    widget.router.routerDelegate.addListener(_onRouteChanged);
    _syncTabFromRoute();
  }

  @override
  void dispose() {
    widget.router.routerDelegate.removeListener(_onRouteChanged);
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() async {
    if (!_tabController.indexIsChanging) return;
    if (_tabController.index == 0) {
      // 根据侧边栏排序首位决定默认路由
      final route = await _getDefaultRoute();
      if (route == '/') {
        ref.read(diaryScrollToTopProvider.notifier).trigger();
      }
      widget.router.go(route);
    } else {
      widget.router.go('/agent');
    }
  }

  /// 读取侧边栏排序的首位 branchIndex，返回对应路由
  Future<String> _getDefaultRoute() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList('desktop_sidebar_nav_order');
      if (saved != null && saved.isNotEmpty) {
        final firstBranch = int.tryParse(saved.first) ?? 0;
        return switch (firstBranch) {
          1 => '/summary',
          2 => '/sync',
          _ => '/',
        };
      }
    } catch (_) {}
    return '/';
  }

  void _onRouteChanged() {
    _syncTabFromRoute();
  }

  void _syncTabFromRoute() {
    final location = widget.router.routeInformationProvider.value.uri.path;

    // 延迟到 build 之后再更新状态，避免在 build 阶段调用 setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _currentLocation = location);
    });

    // 只在主标签路由间同步，覆盖层路由（settings/diary/edit）不改标签
    final isMainRoute =
        location == '/' ||
        location.startsWith('/summary') ||
        location.startsWith('/sync') ||
        location.startsWith('/agent') ||
        location.startsWith('/settings-mobile');
    if (!isMainRoute) return;

    final newIndex = location.startsWith('/agent') ? 1 : 0;
    if (_tabController.index != newIndex && !_tabController.indexIsChanging) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _tabController.animateTo(newIndex);
      });
    }
  }

  /// 是否应该显示标题栏（onboarding 页面不显示）
  bool get _shouldShowTitleBar {
    return !_currentLocation.startsWith('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    if (!isDesktop || !_shouldShowTitleBar) return widget.child;

    final theme = Theme.of(context);

    return Column(
      children: [
        _buildTitleBar(theme),
        Expanded(child: widget.child),
      ],
    );
  }

  Widget _buildTitleBar(ThemeData theme) {
    return GestureDetector(
      onDoubleTap: () async {
        if (await windowManager.isMaximized()) {
          windowManager.unmaximize();
        } else {
          windowManager.maximize();
        }
      },
      child: DragToMoveArea(
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
          ),
          child: Row(
            children: [
              const SizedBox(width: 16),

              // 标签栏
              SizedBox(
                width: 240,
                child: TabBar(
                  controller: _tabController,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorWeight: 2.5,
                  indicatorColor: theme.colorScheme.primary,
                  labelColor: theme.colorScheme.primary,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  labelStyle: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: theme.textTheme.bodySmall,
                  dividerHeight: 0,
                  splashBorderRadius: BorderRadius.circular(8),
                  tabs: [
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_stories_rounded, size: 16),
                          const SizedBox(width: 6),
                          Text(t.diary.title),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.auto_awesome_rounded, size: 16),
                          const SizedBox(width: 6),
                          Text(t.agent.partner_label),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // 工作空间切换
              Consumer(
                builder: (context, ref, child) {
                  final activeVault = ref.watch(vaultServiceProvider).value;
                  return _VaultSwitcher(
                    activeVaultName: activeVault?.name,
                    theme: theme,
                    router: widget.router,
                  );
                },
              ),

              // 设置按钮（不用 IconButton 因为 builder 层没有 Overlay）
              _TitleBarButton(
                icon: Icons.settings_outlined,
                onPressed: () => widget.router.push('/settings'),
                theme: theme,
              ),

              // 分隔线
              Container(
                width: 1,
                height: 20,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),

              // 窗口控制按钮
              _WindowButton(
                icon: Icons.remove,
                onPressed: () => windowManager.minimize(),
                theme: theme,
              ),
              _WindowButton(
                icon: Icons.crop_square,
                onPressed: () async {
                  if (await windowManager.isMaximized()) {
                    windowManager.unmaximize();
                  } else {
                    windowManager.maximize();
                  }
                },
                theme: theme,
              ),
              _WindowButton(
                icon: Icons.close,
                onPressed: () => windowManager.close(),
                theme: theme,
                isClose: true,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 标题栏通用按钮（无 Tooltip，避免 Overlay 依赖） ──────────

class _TitleBarButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final ThemeData theme;

  const _TitleBarButton({
    required this.icon,
    required this.onPressed,
    required this.theme,
  });

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.theme.colorScheme.onSurface.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            widget.icon,
            size: 20,
            color: widget.theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─── 窗口控制按钮 ──────────────────────────────────────────────

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final ThemeData theme;
  final bool isClose;

  const _WindowButton({
    required this.icon,
    required this.onPressed,
    required this.theme,
    this.isClose = false,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: 32,
          decoration: BoxDecoration(
            color: _isHovered
                ? (widget.isClose
                      ? Colors.red
                      : widget.theme.colorScheme.onSurface.withValues(
                          alpha: 0.08,
                        ))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Icon(
            widget.icon,
            size: 16,
            color: _isHovered && widget.isClose
                ? Colors.white
                : widget.theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

// ─── 工作空间切换组件 ──────────────────────────────────────────

class _VaultSwitcher extends ConsumerStatefulWidget {
  final String? activeVaultName;
  final ThemeData theme;
  final GoRouter router;

  const _VaultSwitcher({
    required this.activeVaultName,
    required this.theme,
    required this.router,
  });

  @override
  ConsumerState<_VaultSwitcher> createState() => _VaultSwitcherState();
}

class _VaultSwitcherState extends ConsumerState<_VaultSwitcher> {
  bool _isHovered = false;

  void _showVaultMenu() {
    final navContext = widget.router.routerDelegate.navigatorKey.currentContext;
    if (navContext == null) return;

    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(navContext).overlay!.context.findRenderObject()
            as RenderBox;

    final RelativeRect position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(
          button.size.bottomLeft(Offset.zero),
          ancestor: overlay,
        ),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    final service = ref.read(vaultServiceProvider.notifier);
    final vaults = service.getAllVaults();

    showMenu<String>(
      context: navContext,
      position: position,
      elevation: 4,
      color: widget.theme.colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: vaults
          .map(
            (v) => PopupMenuItem<String>(
              value: v.name,
              child: Row(
                children: [
                  Icon(
                    v.name == widget.activeVaultName
                        ? Icons.check
                        : Icons.circle_outlined,
                    size: 16,
                    color: widget.theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(v.name),
                ],
              ),
            ),
          )
          .toList(),
    ).then((name) {
      if (name != null && name != widget.activeVaultName) {
        ref.read(vaultServiceProvider.notifier).switchVault(name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.activeVaultName == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: _showVaultMenu,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.theme.colorScheme.onSurface.withValues(alpha: 0.08)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.folder_shared_outlined,
                size: 16,
                color: widget.theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(
                widget.activeVaultName!,
                style: widget.theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: widget.theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 16,
                color: widget.theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
