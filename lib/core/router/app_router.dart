import 'package:baishou/i18n/strings.g.dart';
import 'package:baishou/core/providers/shared_preferences_provider.dart';
import 'package:baishou/agent/presentation/pages/agent_main_page.dart';
import 'package:baishou/features/diary/presentation/pages/diary_editor_page.dart';
import 'package:baishou/features/diary/presentation/pages/diary_list_page.dart';
import 'package:baishou/features/home/presentation/pages/main_scaffold.dart';
import 'package:baishou/features/onboarding/data/providers/onboarding_provider.dart';
import 'package:baishou/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:baishou/features/settings/presentation/pages/data_sync_page.dart';
import 'package:baishou/features/settings/presentation/pages/settings_page.dart';
import 'package:baishou/features/settings/presentation/pages/views/ai_global_models_view.dart';
import 'package:baishou/features/settings/presentation/pages/views/ai_model_services_view.dart';
import 'package:baishou/features/settings/presentation/pages/views/agent_tools_view.dart';
import 'package:baishou/features/settings/presentation/pages/views/general_settings_view.dart';
import 'package:baishou/features/settings/presentation/pages/lan_transfer_page.dart';
import 'package:baishou/features/summary/presentation/pages/summary_page.dart';
import 'package:baishou/features/settings/presentation/pages/views/summary_settings_view.dart';
import 'package:baishou/features/settings/presentation/pages/views/rag_memory_view.dart';
import 'package:baishou/agent/presentation/pages/assistant_management_page.dart';
import 'package:baishou/features/settings/presentation/pages/views/web_search_settings_view.dart';
import 'package:baishou/features/settings/presentation/pages/views/attachment_management_view.dart'
    as baishou_attachment;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

final diaryNavKey = GlobalKey<NavigatorState>(debugLabel: 'diary');
final summaryNavKey = GlobalKey<NavigatorState>(debugLabel: 'summary');
final syncNavKey = GlobalKey<NavigatorState>(debugLabel: 'sync');
final settingsNavKey = GlobalKey<NavigatorState>(debugLabel: 'settings');
final agentNavKey = GlobalKey<NavigatorState>(debugLabel: 'agent');

/// 用于记录 App 是否已经经历过首次启动，一旦启动所有后续对 '/' 的访问全部作为幽灵 Intent 拦截
class AppLaunchGuard {
  static bool hasStarted = false;
  static String? lastRoute;
}

/// 全局路由配置
/// 使用 GoRouter 处理页面导航、重定向（如开启引导页）以及子路由嵌套。
@Riverpod(keepAlive: true)
GoRouter goRouter(Ref ref) {
  final rootNavigatorKey = GlobalKey<NavigatorState>();

  // Watch onboarding state
  final onboardingCompleted = ref.watch(onboardingCompletedProvider);

  // Determine initial location based on saved sidebar order
  String initialLoc = '/diary';
  final prefs = ref.watch(sharedPreferencesProvider);
  final savedOrder = prefs.getStringList('desktop_sidebar_nav_order');
  if (savedOrder != null && savedOrder.isNotEmpty) {
    final firstBranch = int.tryParse(savedOrder.first) ?? 0;
    if (firstBranch == 2) {
      initialLoc = '/summary';
    } else if (firstBranch == 4) {
      initialLoc = '/sync';
    }
  }

  final router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLoc,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      debugPrint(
        '[ROUTER_TRACE] redirect triggered | uri: ${state.uri.path} | matched: ${state.matchedLocation} | hasStarted: ${AppLaunchGuard.hasStarted}',
      );
      final isGoingToOnboarding = state.matchedLocation == '/onboarding';

      if (!onboardingCompleted && !isGoingToOnboarding) {
        return '/onboarding';
      }

      if (onboardingCompleted && isGoingToOnboarding) {
        return initialLoc;
      }

      // 如果是 '/'，且 App 刚启动，则放行到 initialLoc，并标记已启动。
      // 如果已启动，说明是 Android MIUI 到底层的假路由指令，直接弹回当前路由。
      if (state.uri.path == '/') {
        if (!AppLaunchGuard.hasStarted) {
          debugPrint(
            '[ROUTER_TRACE] Cold start detect: allowing / to initialLoc ($initialLoc)',
          );
          AppLaunchGuard.hasStarted = true;
          return initialLoc;
        } else {
          debugPrint(
            '[NAV_GUARD] ⚠️ BLOCKED spurious / -> stay at ${AppLaunchGuard.lastRoute ?? initialLoc}',
          );
          return AppLaunchGuard.lastRoute ?? initialLoc;
        }
      }

      // 非 '/' 的所有路由，直接正常放行并记录当前足迹
      AppLaunchGuard.hasStarted = true;
      AppLaunchGuard.lastRoute = state.matchedLocation;

      return null;
    },
    routes: [
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            navigatorKey: diaryNavKey,
            routes: [
              GoRoute(
                path: '/diary',
                builder: (context, state) => const DiaryListPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: agentNavKey,
            routes: [
              GoRoute(
                path: '/agent',
                builder: (context, state) => const AgentMainPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: summaryNavKey,
            routes: [
              GoRoute(
                path: '/summary',
                builder: (context, state) => const SummaryPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: settingsNavKey,
            routes: [
              GoRoute(
                path: '/settings-mobile',
                builder: (context, state) => const SettingsPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: syncNavKey,
            routes: [
              GoRoute(
                path: '/sync',
                builder: (context, state) => const DataSyncPage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      // 设置子页路由 —— 必须走 rootNavigatorKey，成为全屏覆盖层。
      // 这样子页不会进入 settingsNavKey 的内部栈，
      // 避免切换到其它 Tab 后，后台隐藏的子页被侧滑手势静默 pop。
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings/general',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: Text(t.settings.general)),
          body: const GeneralSettingsView(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings/ai-services',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: Text(t.settings.ai_services)),
          body: const AiModelServicesView(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings/ai-models',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: Text(t.settings.ai_global_models)),
          body: const AiGlobalModelsView(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings/summary',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: Text(t.settings.summary_settings_title)),
          body: const SummarySettingsView(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings/rag',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: Text(t.agent.rag.title)),
          body: const RagMemoryView(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings/web-search',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: Text(t.agent.tools.web_search)),
          body: const WebSearchSettingsView(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings/assistants',
        builder: (context, state) => const AssistantManagementPage(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings/agent-tools',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: Text(t.settings.agent_tools_title)),
          body: const AgentToolsView(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings/data-sync',
        builder: (context, state) => Scaffold(
          appBar: AppBar(title: Text(t.data_sync.title)),
          body: const DataSyncPage(),
        ),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings/lan-transfer',
        builder: (context, state) => const LanTransferPage(),
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/settings/attachments',
        builder: (context, state) {
          return Scaffold(
            appBar: AppBar(title: Text(t.settings.attachment_management)),
            body: const baishou_attachment.AttachmentManagementView(),
          );
        },
      ),
      GoRoute(
        parentNavigatorKey: rootNavigatorKey,
        path: '/diary/edit',
        builder: (context, state) {
          final dateStr = state.uri.queryParameters['date'];
          final idStr = state.uri.queryParameters['id'];
          final summaryIdStr = state.uri.queryParameters['summaryId'];
          final appendStr = state.uri.queryParameters['append'];

          final date = dateStr != null ? DateTime.tryParse(dateStr) : null;
          final id = idStr != null ? int.tryParse(idStr) : null;
          final summaryId = summaryIdStr != null
              ? int.tryParse(summaryIdStr)
              : null;
          final shouldAppend = appendStr == '1';

          return DiaryEditorPage(
            diaryId: id,
            summaryId: summaryId,
            initialDate: date,
            appendOnLoad: shouldAppend,
          );
        },
      ),
    ],
  );

  return router;
}
