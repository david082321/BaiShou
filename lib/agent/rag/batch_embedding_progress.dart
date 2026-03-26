import 'package:flutter_riverpod/flutter_riverpod.dart';

enum RagProgressType { none, batchEmbed, migration }

/// RAG 后台任务的全局进度状态
class RagProgressState {
  final RagProgressType type;
  final bool isRunning;
  final int progress;
  final int total;
  final String statusText;

  const RagProgressState({
    this.type = RagProgressType.none,
    this.isRunning = false,
    this.progress = 0,
    this.total = 0,
    this.statusText = '',
  });

  RagProgressState copyWith({
    RagProgressType? type,
    bool? isRunning,
    int? progress,
    int? total,
    String? statusText,
  }) {
    return RagProgressState(
      type: type ?? this.type,
      isRunning: isRunning ?? this.isRunning,
      progress: progress ?? this.progress,
      total: total ?? this.total,
      statusText: statusText ?? this.statusText,
    );
  }
}

/// RAG 后台任务全局进度管理
///
/// 用于在 RAG 设置面板持久化展示全量嵌入、模型迁移等后台任务进度。
class RagProgressNotifier extends Notifier<RagProgressState> {
  DateTime? _lastUpdateTime;

  @override
  RagProgressState build() => const RagProgressState();

  void startBatch(int total) {
    _lastUpdateTime = DateTime.now();
    state = RagProgressState(
      type: RagProgressType.batchEmbed,
      isRunning: true,
      progress: 0,
      total: total,
    );
  }

  void updateBatch(int progress) {
    if (state.type == RagProgressType.batchEmbed) {
      final now = DateTime.now();
      // 限流：每 50ms 刷新一次前端 UI，或是进度 100% 必须刷新
      if (_lastUpdateTime == null ||
          now.difference(_lastUpdateTime!).inMilliseconds > 50 ||
          progress == state.total) {
        _lastUpdateTime = now;
        state = state.copyWith(progress: progress);
      }
    }
  }

  void startMigration() {
    _lastUpdateTime = DateTime.now();
    state = const RagProgressState(
      type: RagProgressType.migration,
      isRunning: true,
      progress: 0,
      total: 0,
      statusText: '',
    );
  }

  void updateMigration(int progress, int total, String statusText) {
    if (state.type == RagProgressType.migration) {
      final now = DateTime.now();
      if (_lastUpdateTime == null ||
          now.difference(_lastUpdateTime!).inMilliseconds > 50 ||
          progress == total) {
        _lastUpdateTime = now;
        state = state.copyWith(
          progress: progress,
          total: total,
          statusText: statusText,
        );
      }
    }
  }

  void finish() {
    state = const RagProgressState();
  }
}

final ragProgressProvider =
    NotifierProvider<RagProgressNotifier, RagProgressState>(
      RagProgressNotifier.new,
    );
