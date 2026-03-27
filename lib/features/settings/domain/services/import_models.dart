/// 导入相关数据模型
///
/// ImportResult — 导入操作的结果

/// 导入结果
class ImportResult {
  /// ZIP 中包含的文件数量
  final int fileCount;

  /// 是否成功恢复了设备级偏好配置
  final bool profileRestored;

  /// 导入前创建的快照路径（如果有）
  final String? snapshotPath;

  /// 错误信息（null 表示成功）
  final String? error;

  const ImportResult({
    this.fileCount = 0,
    this.profileRestored = false,
    this.snapshotPath,
    this.error,
  });

  bool get success => error == null;
}
