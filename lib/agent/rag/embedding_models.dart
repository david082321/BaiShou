/// Embedding 相关数据模型
///
/// ChunkResult — 文本分块策略结果
/// MigrationProgress — 嵌入迁移进度

/// 文本分块策略
class ChunkResult {
  final int index;
  final String text;
  ChunkResult({required this.index, required this.text});
}

/// 嵌入迁移进度
class MigrationProgress {
  final int total;
  final int completed;
  final int failed;
  final String status;

  MigrationProgress({
    required this.total,
    required this.completed,
    this.failed = 0,
    this.status = '',
  });

  double get progress => total > 0 ? completed / total : 0;
  bool get isDone => completed + failed >= total && total > 0;
}
