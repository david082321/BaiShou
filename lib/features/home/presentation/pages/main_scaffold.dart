import 'dart:io';

import 'package:baishou/core/router/app_router.dart';
import 'package:baishou/core/widgets/app_toast.dart';
import 'package:baishou/features/home/presentation/widgets/desktop_sidebar.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 主级架构视图
/// 负责分发移动端（底部导航）与桌面端（侧边栏）布局，切换不同的功能分支。
class MainScaffold extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  void _goBranch(int index) {
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
  }

  /// 将 Shell Branch 索引映射为移动端底栏索引
  /// Branch 0 → Nav 0 (时间轴), Branch 1 → Nav 1 (总结), Branch 3 → Nav 2 (设置)
  int _getMobileNavIndex() {
    final branchIndex = widget.navigationShell.currentIndex;
    if (branchIndex == 3) return 2; // 设置
    if (branchIndex <= 1) return branchIndex;
    return 0; // 默认回到时间轴（branch 2 是桌面端专用的同步页）
  }

  DateTime? _lastBackPress;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 响应式与设备类型判断
        // 逻辑：Windows/Linux/macOS 始终显示桌面版；
        // Android/iOS 根据屏幕宽度判断（手机 vs Pad）。
        final bool isDesktopOS =
            Platform.isWindows || Platform.isLinux || Platform.isMacOS;
        final bool isLargeScreen = constraints.maxWidth >= 700;
        final bool isDesktop = isDesktopOS || isLargeScreen;

        Widget content = widget.navigationShell;

        // 仅在移动端或非桌面 OS 且小屏时应用返回逻辑
        if (!isDesktop) {
          final currentIndex = widget.navigationShell.currentIndex;
          final GlobalKey<NavigatorState>? activeKey = switch (currentIndex) {
            0 => diaryNavKey,
            1 => summaryNavKey,
            2 => syncNavKey,
            3 => settingsNavKey,
            _ => null,
          };

          final navState = activeKey?.currentState;
          final bool canPopNested = navState?.canPop() ?? false;

          // 核心逻辑：
          // 1. 如果有内嵌页面，允许内部弹出 (canPop: true)
          // 2. 否则，如果用户是在首页（时间轴），拦截返回 (canPop: false)。
          // 3. 否则如果在其他 Tab，依然拦截返回并在微任务中切回首页。
          final bool shouldPopRoute = canPopNested;

          content = PopScope(
            canPop: shouldPopRoute,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;

              // 如果当前不在首个标签页（时间轴），则切回到时间轴
              if (currentIndex != 0) {
                Future.microtask(() => _goBranch(0));
                return;
              }

              // 在首页时，双击退出逻辑
              final now = DateTime.now();
              if (_lastBackPress == null ||
                  now.difference(_lastBackPress!) >
                      const Duration(seconds: 2)) {
                setState(() {
                  _lastBackPress = now;
                });
                AppToast.show(context, t.common.exit_hint);
                return;
              }

              // 2秒内连续按返回，则退出应用
              // 注意：直接使用 SystemNavigator.pop() 可能会抛弃部分上下文，
              // 但对于根部退出来说是目前最可靠的方法。
              SystemNavigator.pop();
            },
            child: widget.navigationShell,
          );
        }

        if (isDesktop) {
          return Scaffold(
            backgroundColor: Theme.of(context).colorScheme.surface,
            body: Row(
              children: [
                // 左侧导航栏 (桌面端)
                DesktopSidebar(
                  navigationShell: widget.navigationShell,
                  onBranchChange: _goBranch,
                ),
                // 主内容区域
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      // 在桌面端给主区域一个微妙的阴影或分界
                      boxShadow: [
                        if (Theme.of(context).brightness == Brightness.light)
                          BoxShadow(
                            color: Colors.black.withOpacity(0.02),
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
          );
        }

        // 移动端布局
        return Scaffold(
          body: Container(
            color: Theme.of(context).colorScheme.surface,
            child: content,
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _getMobileNavIndex(),
            onDestinationSelected: (index) {
              // 移动端映射：0=时间轴, 1=总结, 2=设置(branch 3)
              if (index == 2) {
                _goBranch(3); // 设置页面位于 branch 3
              } else {
                _goBranch(index);
              }
            },
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.timeline_outlined),
                selectedIcon: const Icon(Icons.timeline),
                label: t.diary.title,
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
      },
    );
  }
}
