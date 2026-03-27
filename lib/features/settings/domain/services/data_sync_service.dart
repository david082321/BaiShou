import 'dart:io';
import 'package:baishou/core/storage/data_archive_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:baishou/i18n/strings.g.dart';

/// 数据同步服务类
/// 核心逻辑复用 DataArchiveManager，确保与数据导出/导入/局域网传输的格式完全一致。
/// 物理全量打包 + 设备级偏好配置的导出/导入均由 DataArchiveManager 统一收口。
class DataSyncService {
  final DataArchiveManager _dataArchiveManager;

  DataSyncService({
    required DataArchiveManager dataArchiveManager,
  }) : _dataArchiveManager = dataArchiveManager;

  /// 创建一个包含所有数据的备份 ZIP 文件。
  /// 复用 DataArchiveManager 的逻辑——物理打包 BaiShou_Root + 设备级偏好配置。
  Future<String> createBackupZip() async {
    final zipFile = await _dataArchiveManager.exportToTempFile();
    if (zipFile == null) {
      throw Exception(t.settings.backup_create_failed);
    }
    return zipFile.path;
  }

  /// 从指定的 ZIP 文件路径还原数据。
  /// 复用 DataArchiveManager 的逻辑——覆盖模式导入，自动创建快照、恢复物理文件和设备级偏好。
  Future<void> restoreFromZip(String zipPath) async {
    final zipFile = File(zipPath);
    if (!await zipFile.exists()) {
      throw Exception(t.settings.backup_zip_not_found(path: zipPath));
    }

    final result = await _dataArchiveManager.importFromZip(
      zipFile,
      createSnapshotBefore: true,
    );
    if (!result.success) {
      throw Exception(result.error ?? t.settings.restore_failed_generic);
    }
  }
}

/// Riverpod Provider 定义
final dataSyncServiceProvider = Provider<DataSyncService>((ref) {
  return DataSyncService(
    dataArchiveManager: ref.watch(dataArchiveManagerProvider.notifier),
  );
});
