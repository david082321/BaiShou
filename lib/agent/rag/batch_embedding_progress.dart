import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全量嵌入进度的全局状态
class BatchEmbeddingProgress {
  final bool isRunning;
  final int progress;
  final int total;

  const BatchEmbeddingProgress({
    this.isRunning = false,
    this.progress = 0,
    this.total = 0,
  });

  BatchEmbeddingProgress copyWith({
    bool? isRunning,
    int? progress,
    int? total,
  }) {
    return BatchEmbeddingProgress(
      isRunning: isRunning ?? this.isRunning,
      progress: progress ?? this.progress,
      total: total ?? this.total,
    );
  }
}

/// 全量嵌入进度的全局状态管理
///
/// 将嵌入进度提升到 Provider 层，避免切换页面后状态丢失。
class BatchEmbeddingProgressNotifier extends Notifier<BatchEmbeddingProgress> {
  @override
  BatchEmbeddingProgress build() => const BatchEmbeddingProgress();

  void start(int total) {
    state = BatchEmbeddingProgress(isRunning: true, progress: 0, total: total);
  }

  void updateProgress(int progress) {
    state = state.copyWith(progress: progress);
  }

  void finish() {
    state = const BatchEmbeddingProgress();
  }
}

final batchEmbeddingProgressProvider =
    NotifierProvider<BatchEmbeddingProgressNotifier, BatchEmbeddingProgress>(
  BatchEmbeddingProgressNotifier.new,
);
