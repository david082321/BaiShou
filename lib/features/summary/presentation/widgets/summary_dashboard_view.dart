import 'package:baishou/core/database/tables/summaries.dart';
import 'package:baishou/features/diary/data/repositories/diary_repository_impl.dart';
import 'package:baishou/core/theme/app_theme.dart';
import 'package:baishou/core/widgets/app_toast.dart';
import 'package:baishou/core/services/data_refresh_notifier.dart';
import 'package:baishou/features/diary/data/vault_index_notifier.dart';
import 'package:baishou/features/index/data/shadow_index_database.dart';
import 'package:baishou/features/summary/data/repositories/summary_repository_impl.dart';
import 'package:baishou/features/summary/domain/entities/summary.dart';
import 'package:baishou/features/summary/domain/services/context_builder.dart';
import 'package:baishou/features/summary/presentation/widgets/missing_summary_list.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:baishou/features/summary/presentation/providers/summary_filter_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:baishou/features/summary/presentation/widgets/dashboard/dashboard_hero_banner.dart';
import 'package:baishou/features/summary/presentation/widgets/dashboard/dashboard_stats_card.dart';
import 'package:baishou/features/summary/presentation/widgets/dashboard/dashboard_shared_memory_card.dart';
import 'package:baishou/features/summary/presentation/widgets/dashboard/dashboard_gallery_section.dart';

/// 记忆仪表盘 — 按参考图重构
///
/// 结构：
/// - 顶部：面板 / 记忆画廊 标签切换（Chrome 风格）
/// - 面板页：顶部横幅 + 双栏卡片（共同回忆 / 统计面板）+ AI 建议补全
/// - 画廊页：标签（周度/月度/季度/年度）+ 列表/详情双栏
class SummaryDashboardView extends ConsumerStatefulWidget {
  const SummaryDashboardView({super.key});

  @override
  ConsumerState<SummaryDashboardView> createState() =>
      _SummaryDashboardViewState();
}

class _SummaryDashboardViewState extends ConsumerState<SummaryDashboardView>
    with TickerProviderStateMixin {
  bool _isLoading = false;
  ContextResult? _result;

  // 全量统计
  int _totalDiaryCount = 0;
  int _totalWeeklyCount = 0;
  int _totalMonthlyCount = 0;
  int _totalQuarterlyCount = 0;
  int _totalYearlyCount = 0;

  late final TabController _mainTabController; // 面板 / 画廊 切换
  late final TabController _galleryTabController; // 周/月/季/年
  int _lastRefreshVersion = 0;
  int _maxMonths = 60;

  late final TextEditingController _monthsController;

  // 记忆画廊选中的 summary
  Summary? _selectedSummary;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this);
    _galleryTabController = TabController(length: 4, vsync: this);
    _galleryTabController.addListener(() {
      if (!_galleryTabController.indexIsChanging) {
        setState(() => _selectedSummary = null);
      }
    });

    final initialMonths = ref.read(summaryFilterProvider).lookbackMonths;
    _monthsController = TextEditingController(text: initialMonths.toString());

    _loadAllData();
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    _galleryTabController.dispose();
    _monthsController.dispose();
    super.dispose();
  }

  /// 加载全量统计 + 共同回忆
  Future<void> _loadAllData() async {
    // 等待影子索引库初始化完成后再加载数据
    final dbState = ref.read(shadowIndexDatabaseProvider);
    if (dbState is! AsyncData) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      // 加载全量统计（不受月份过滤）
      final summaryRepo = ref.read(summaryRepositoryProvider);
      final allSummaries = await summaryRepo.getSummaries();

      int wc = 0, mc = 0, qc = 0, yc = 0;
      for (final s in allSummaries) {
        switch (s.type) {
          case SummaryType.weekly:
            wc++;
          case SummaryType.monthly:
            mc++;
          case SummaryType.quarterly:
            qc++;
          case SummaryType.yearly:
            yc++;
        }
      }

      // 日记总数
      final diaryRepo = ref.read(diaryRepositoryProvider);
      final allDiaries = await diaryRepo.getAllDiaries();
      final diaryTotal = allDiaries.length;

      // 共同回忆数据
      final months = ref.read(summaryFilterProvider).lookbackMonths;
      final result = await ref
          .read(contextBuilderProvider)
          .buildLifeBookContext(months: months);

      if (mounted) {
        setState(() {
          _totalWeeklyCount = wc;
          _totalMonthlyCount = mc;
          _totalQuarterlyCount = qc;
          _totalYearlyCount = yc;
          _totalDiaryCount = diaryTotal;
          _result = result;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // drift 隔离通道关闭（热重启/数据库未就绪）时静默重试，不弹 Toast
        final msg = e.toString();
        if (msg.contains('Channel was closed') ||
            msg.contains('Closed before') ||
            msg.contains('数据库未挂载')) {
          debugPrint('SummaryDashboard: DB not ready, will retry in 1s: $e');
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) _loadAllData();
          });
        } else {
          AppToast.showError(context, '${t.summary.load_failed}: $e');
        }
      }
    }
  }

  Future<void> _copyContext() async {
    if (_result == null) return;
    final prefix = ref.read(summaryFilterProvider).copyContextPrefix;
    final textToCopy = prefix.isEmpty
        ? _result!.text
        : "$prefix\n\n${_result!.text}";
    await Clipboard.setData(ClipboardData(text: textToCopy));
    if (mounted) {
      AppToast.showSuccess(context, t.summary.toast_copied);
    }
  }

  @override
  Widget build(BuildContext context) {
    final refreshVersion = ref.watch(dataRefreshProvider);
    // 监听影子索引库状态，初始化完成后加载数据
    ref.listen(shadowIndexDatabaseProvider, (previous, next) {
      if (next is AsyncData) {
        _loadAllData();
      }
    });

    // 监听Vault主列表变动刷新统计
    ref.listen(vaultIndexProvider, (prev, next) {
      if (next is AsyncData) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _loadAllData();
        });
      }
    });
    ref.listen(summaryFilterProvider.select((s) => s.lookbackMonths), (
      prev,
      next,
    ) {
      if (prev != next) {
        _monthsController.text = next.toString();
        _loadAllData();
      }
    });
    if (refreshVersion != _lastRefreshVersion) {
      _lastRefreshVersion = refreshVersion;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadAllData();
      });
    }

    final theme = Theme.of(context);

    if (_isLoading && _result == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Chrome 风格标签栏
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TabBar(
                  controller: _mainTabController,
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: AppTheme.primary,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  labelStyle: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  tabs: [
                    Tab(text: t.summary.panel_tab),
                    Tab(text: t.summary.memory_gallery),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: IconButton(
                  icon: const Icon(Icons.tune_rounded, size: 20),
                  tooltip: t.settings.summary_settings_tooltip,
                  onPressed: () => context.push('/settings/summary'),
                  style: IconButton.styleFrom(
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
        // 标签内容
        Expanded(
          child: TabBarView(
            controller: _mainTabController,
            children: [
              _buildPanelView(theme),
              DashboardGallerySection(
                galleryTabController: _galleryTabController,
                selectedSummary: _selectedSummary,
                onSelect: (s) => setState(() => _selectedSummary = s),
                onDelete: () => setState(() => _selectedSummary = null),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // 面板页
  // ═══════════════════════════════════════════════════════

  Widget _buildPanelView(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DashboardHeroBanner(),
          const SizedBox(height: 24),
          _buildDualCards(theme),
          const SizedBox(height: 24),
          const MissingSummaryList(),
        ],
      ),
    );
  }

  Widget _buildDualCards(ThemeData theme) {
    final sharedMemoryCard = DashboardSharedMemoryCard(
      result: _result,
      currentMonths: ref.watch(summaryFilterProvider).lookbackMonths,
      maxMonths: _maxMonths,
      monthsController: _monthsController,
      onMonthsChanged: (val) {
        ref.read(summaryFilterProvider.notifier).updateLookbackMonths(val);
      },
      onCopyContext: _copyContext,
    );
    final statsCard = DashboardStatsCard(
      totalDiaryCount: _totalDiaryCount,
      totalWeeklyCount: _totalWeeklyCount,
      totalMonthlyCount: _totalMonthlyCount,
      totalQuarterlyCount: _totalQuarterlyCount,
      totalYearlyCount: _totalYearlyCount,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 600;
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: sharedMemoryCard),
              const SizedBox(width: 16),
              Expanded(child: statsCard),
            ],
          );
        }
        return Column(
          children: [sharedMemoryCard, const SizedBox(height: 16), statsCard],
        );
      },
    );
  }
}
