import 'package:baishou/core/services/data_refresh_notifier.dart';
import 'package:baishou/features/summary/domain/services/missing_summary_detector.dart';
import 'package:baishou/features/summary/domain/services/summary_generator_service.dart';
import 'package:baishou/features/summary/domain/repositories/summary_repository.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/foundation.dart';

/// 管理 AI 生成状态的服务，用于跨页面持久化状态
/// 使用单例 + ValueNotifier 模式，不依赖 Riverpod 以避免版本/环境问题
///
/// 批量生成逻辑也托管在此，使其脱离 widget 生命周期，
/// 切换页面后回来不会中断。
class GenerationStateService {
  // 单例模式
  static final GenerationStateService _instance =
      GenerationStateService._internal();
  factory GenerationStateService() => _instance;
  GenerationStateService._internal();

  // 状态
  final ValueNotifier<Map<String, String>> statusNotifier = ValueNotifier({});

  /// 批量处理状态
  final ValueNotifier<bool> isBatchProcessing = ValueNotifier(false);
  bool _cancelRequested = false;
  bool get cancelRequested => _cancelRequested;

  Map<String, String> get statusMap => statusNotifier.value;

  void setStatus(String key, String status) {
    statusNotifier.value = {...statusNotifier.value, key: status};
  }

  void removeStatus(String key) {
    final newState = Map<String, String>.from(statusNotifier.value);
    newState.remove(key);
    statusNotifier.value = newState;
  }

  String? getStatus(String key) => statusNotifier.value[key];

  /// 请求取消批量生成
  void requestCancel() {
    _cancelRequested = true;
  }

  /// 批量生成（脱离 widget 生命周期）
  ///
  /// 调用后任务在单例中运行，即使 widget dispose 也不影响。
  /// [ref] 仅用于初始化时获取服务引用，之后不再使用。
  Future<void> batchGenerate({
    required List<MissingSummary> items,
    required int concurrencyLimit,
    required SummaryGeneratorService generator,
    required SummaryRepository repository,
    required DataRefreshNotifier refreshNotifier,
  }) async {
    if (isBatchProcessing.value) return;

    isBatchProcessing.value = true;
    _cancelRequested = false;

    final queue = List<MissingSummary>.from(items);
    final List<Future<void>> workers = [];

    Future<void> worker() async {
      while (queue.isNotEmpty && !_cancelRequested) {
        final item = queue.removeAt(0);
        await _generateSingle(
          item: item,
          generator: generator,
          repository: repository,
          cancelCheck: () => _cancelRequested,
          onSuccess: () => refreshNotifier.refresh(),
        );
      }
    }

    for (int i = 0; i < concurrencyLimit; i++) {
      workers.add(worker());
    }

    await Future.wait(workers);

    // 批量全部完成后，统一刷新一次
    refreshNotifier.refresh();
    isBatchProcessing.value = false;
    _cancelRequested = false;
  }

  /// 单条生成（供批量和单独触发共用）
  Future<void> generateSingle({
    required MissingSummary item,
    required SummaryGeneratorService generator,
    required SummaryRepository repository,
    required DataRefreshNotifier refreshNotifier,
    bool isBatch = false,
  }) async {
    await _generateSingle(
      item: item,
      generator: generator,
      repository: repository,
    );

    if (!isBatch) {
      refreshNotifier.refresh();
    }
  }

  /// 内部实现：不依赖任何 widget 或 ref
  Future<void> _generateSingle({
    required MissingSummary item,
    required SummaryGeneratorService generator,
    required SummaryRepository repository,
    bool Function()? cancelCheck,
    void Function()? onSuccess,
  }) async {
    final key = item.label;

    // 可以重新生成的"终态"状态集合
    final retryableStatuses = {t.summary.tap_to_retry};
    final retryablePrefix = [
      t.summary.generation_failed,
      t.summary.content_empty,
    ];

    final currentStatus = getStatus(key);
    final isRetryable =
        currentStatus == null ||
        retryableStatuses.contains(currentStatus) ||
        retryablePrefix.any((p) => currentStatus.startsWith(p));
    if (!isRetryable) return;

    setStatus(key, t.summary.preparing);

    try {
      final stream = generator.generate(item);
      String finalContent = '';

      await for (final status in stream) {
        if (cancelCheck?.call() == true) {
          setStatus(key, t.summary.tap_to_retry);
          break;
        }
        if (status.startsWith('STATUS:')) {
          setStatus(key, status.substring(7));
        } else {
          finalContent = status;
        }
      }

      if (cancelCheck?.call() == true) return;

      if (finalContent.isNotEmpty) {
        await repository.addSummary(
          type: item.type,
          startDate: item.startDate,
          endDate: item.endDate,
          content: finalContent,
        );
        removeStatus(key);
        onSuccess?.call();
      } else {
        setStatus(key, t.summary.tap_to_retry);
      }
    } catch (e) {
      debugPrint('GenerationStateService: Failed to generate ${item.label}: $e');
      setStatus(key, t.summary.tap_to_retry);
    }
  }
}
