/// 导入相关数据模型
///
/// ImportResult — 导入操作的结果
/// ParsedImportData — Isolate 解析后的结构化数据

/// 导入结果
class ImportResult {
  final int diariesImported;
  final int summariesImported;
  final bool profileRestored;
  final Map<String, dynamic>? configData;
  final String? snapshotPath;
  final String? error;

  const ImportResult({
    this.diariesImported = 0,
    this.summariesImported = 0,
    this.profileRestored = false,
    this.configData,
    this.snapshotPath,
    this.error,
  });

  bool get success => error == null;
}

/// 解析后的导入数据 (用于 isolate 传输)
class ParsedImportData {
  final Map<String, dynamic> manifest;
  final List<dynamic>? diaries;
  final List<dynamic>? summaries;
  final Map<String, dynamic>? config;

  ParsedImportData({
    required this.manifest,
    this.diaries,
    this.summaries,
    this.config,
  });
}
