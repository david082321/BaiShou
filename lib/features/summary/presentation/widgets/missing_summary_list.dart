import 'package:baishou/core/theme/app_theme.dart';
import 'package:baishou/core/services/api_config_service.dart';
import 'package:baishou/core/services/data_refresh_notifier.dart';
import 'package:baishou/core/widgets/app_toast.dart';
import 'package:baishou/features/summary/domain/services/missing_summary_detector.dart';
import 'package:baishou/features/summary/domain/services/summary_generator_service.dart';
import 'package:baishou/features/summary/data/repositories/summary_repository_impl.dart';
import 'package:baishou/features/summary/presentation/providers/generation_state_service.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:baishou/features/summary/presentation/widgets/missing_summary_card.dart';
import 'package:go_router/go_router.dart';
import 'package:baishou/features/index/data/shadow_index_database.dart';

class MissingSummaryList extends ConsumerStatefulWidget {
  const MissingSummaryList({super.key});

  @override
  ConsumerState<MissingSummaryList> createState() => _MissingSummaryListState();
}

class _MissingSummaryListState extends ConsumerState<MissingSummaryList> {
  int _concurrencyLimit = 3;

  @override
  Widget build(BuildContext context) {
    // 检查影子索引库是否初始化完成，未就绪时不查询
    final dbState = ref.watch(shadowIndexDatabaseProvider);
    if (dbState is! AsyncData) return const SizedBox.shrink();

    // 监听 dataRefreshProvider 以在数据变更后触发 rebuild
    ref.watch(dataRefreshProvider);

    // FutureBuilder 放在最外层，实时查询数据库
    return FutureBuilder<List<MissingSummary>>(
      future: _safeGetAllMissing(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();
        final missing = snapshot.data!;
        if (missing.isEmpty) return const SizedBox.shrink();

        final service = GenerationStateService();

        // 双层 ValueListenableBuilder：生成进度 + 批处理状态
        return ValueListenableBuilder<bool>(
          valueListenable: service.isBatchProcessing,
          builder: (context, isBatchProcessing, _) {
            return ValueListenableBuilder<Map<String, String>>(
              valueListenable: service.statusNotifier,
              builder: (context, generationStatus, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.auto_fix_high_rounded,
                              size: 20,
                              color: Colors.amber.shade700,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              t.summary.ai_suggestions,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        // 批量生成按钮
                        FilledButton.tonal(
                          onPressed: isBatchProcessing
                              ? () => service.requestCancel()
                              : () => _batchGenerate(missing),
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            backgroundColor: isBatchProcessing
                                ? Colors.red.withValues(alpha: 0.1)
                                : AppTheme.primary.withValues(alpha: 0.1),
                            foregroundColor: isBatchProcessing
                                ? Colors.red
                                : AppTheme.primary,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isBatchProcessing) ...[
                                const SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.red,
                                  ),
                                ),
                                const SizedBox(width: 6),
                              ],
                              Text(
                                isBatchProcessing
                                    ? (service.cancelRequested
                                          ? t.summary.stopping
                                          : t.summary.stop_generating)
                                    : t.summary.generate_all,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        // 并发设置
                        PopupMenuButton<int>(
                          initialValue: _concurrencyLimit,
                          tooltip: t.summary.concurrency_limit,
                          onSelected: (val) {
                            setState(() => _concurrencyLimit = val);
                          },
                          itemBuilder: (context) => [1, 2, 3, 4, 5]
                              .map(
                                (e) => PopupMenuItem(
                                  value: e,
                                  child: Text(
                                    t.summary.concurrency_count(count: e),
                                  ),
                                ),
                              )
                              .toList(),
                          position: PopupMenuPosition.under,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.speed_rounded,
                                  size: 14,
                                  color: AppTheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  t.summary.concurrency_count(
                                    count: _concurrencyLimit,
                                  ),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // 数量标签
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            t.common.count_items(count: missing.length),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 600;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isWide ? 2 : 1,
                            mainAxisExtent: 96,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: missing.length,
                          itemBuilder: (context, index) {
                            final item = missing[index];
                            final key = item.label;
                            final status = generationStatus[key];
                            return MissingSummaryCard(
                              item: item,
                              status: status,
                              onGenerate: () => _generate(item),
                            );
                          },
                        );
                      },
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// 检查模型是否已配置且已启用，否则弹窗引导用户跳转设置
  bool _checkModelConfigured() {
    final apiConfig = ref.read(apiConfigServiceProvider);
    final providerId = apiConfig.globalSummaryProviderId;
    final modelId = apiConfig.globalSummaryModelId;

    // 检查是否已配置
    if (providerId.isEmpty || modelId.isEmpty) {
      _showGoToSettingsDialog(
        t.summary.model_not_configured,
        t.summary.model_not_configured_desc,
      );
      return false;
    }

    // 检查供应商是否已启用
    final provider = apiConfig.getProvider(providerId);
    if (provider == null || !provider.isEnabled) {
      _showGoToSettingsDialog(
        t.summary.service_disabled,
        t.summary.service_disabled_desc,
      );
      return false;
    }

    return true;
  }

  /// 显示引导跳转到设置页的通用弹窗
  void _showGoToSettingsDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              final isMobile = MediaQuery.of(context).size.width < 600;
              if (isMobile) {
                context.go('/settings-mobile');
              } else {
                context.push('/settings');
              }
            },
            child: Text(t.settings.go_to_settings),
          ),
        ],
      ),
    );
  }

  void _batchGenerate(List<MissingSummary> missing) {
    if (!_checkModelConfigured()) return;

    // 提前解析服务，传入单例，脱离 widget 生命周期
    final generator = ref.read(summaryGeneratorServiceProvider);
    final repository = ref.read(summaryRepositoryProvider);
    final refreshNotifier = ref.read(dataRefreshProvider.notifier);

    GenerationStateService().batchGenerate(
      items: missing,
      concurrencyLimit: _concurrencyLimit,
      generator: generator,
      repository: repository,
      refreshNotifier: refreshNotifier,
    );
  }

  void _generate(MissingSummary item) {
    if (!_checkModelConfigured()) return;

    final generator = ref.read(summaryGeneratorServiceProvider);
    final repository = ref.read(summaryRepositoryProvider);
    final refreshNotifier = ref.read(dataRefreshProvider.notifier);

    GenerationStateService().generateSingle(
      item: item,
      generator: generator,
      repository: repository,
      refreshNotifier: refreshNotifier,
    ).catchError((e) {
      if (mounted) {
        AppToast.showError(
          context,
          t.summary.generation_failed_error(label: item.label, e: e.toString()),
        );
      }
    });
  }

  /// 安全查询缺失列表，数据库未就绪时返回空列表而不崩溃
  Future<List<MissingSummary>> _safeGetAllMissing() async {
    try {
      return await ref
          .read(missingSummaryDetectorProvider)
          .getAllMissing(LocaleSettings.currentLocale);
    } catch (_) {
      return [];
    }
  }
}
