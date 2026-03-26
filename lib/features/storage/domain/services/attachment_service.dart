import 'dart:io';
import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/core/storage/storage_path_provider.dart';
import 'package:baishou/core/storage/vault_service.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'attachment_service.g.dart';

class AttachmentFolderInfo {
  final String sessionId;
  final String? sessionTitle;
  final int fileCount;
  final int totalBytes;
  final List<File> files;

  const AttachmentFolderInfo({
    required this.sessionId,
    this.sessionTitle,
    required this.fileCount,
    required this.totalBytes,
    required this.files,
  });

  bool get isOrphan => sessionTitle == null;
}

class AttachmentService {
  final AgentDatabase _db;
  final StoragePathService _pathService;
  final String _vaultName;

  AttachmentService(this._db, this._pathService, this._vaultName);

  /// 扫描当前空间的附件目录，区分正常会话与孤立附件
  Future<List<AttachmentFolderInfo>> scanAttachments() async {
    final vaultDir = await _pathService.getVaultDirectory(_vaultName);
    final attBaseDir = Directory(p.join(vaultDir.path, 'attachments'));
    
    if (!(await attBaseDir.exists())) {
      return [];
    }

    final result = <AttachmentFolderInfo>[];
    
    // 异步遍历所有的 sessionId 文件夹
    final entities = await attBaseDir.list().toList();
    for (final entity in entities) {
      if (entity is Directory) {
        final sessionId = p.basename(entity.path);
        
        // 查询数据库看会话是否存在
        final session = await (_db.select(_db.agentSessions)..where((t) => t.id.equals(sessionId))).getSingleOrNull();
        
        // 统计文件夹内文件
        int totalBytes = 0;
        final files = <File>[];
        try {
          final subEntities = await entity.list(recursive: true).toList();
          for (final sub in subEntities) {
            if (sub is File) {
              files.add(sub);
              totalBytes += await sub.length();
            }
          }
        } catch (_) {}

        if (files.isEmpty) {
          // 如果是个空文件夹，直接顺手删了
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
          continue;
        }

        result.add(AttachmentFolderInfo(
          sessionId: sessionId,
          sessionTitle: session?.title,
          fileCount: files.length,
          totalBytes: totalBytes,
          files: files,
        ));
      }
    }

    return result;
  }

  /// 删除指定的附件文件夹
  Future<void> deleteAttachmentFolder(String sessionId) async {
    final vaultDir = await _pathService.getVaultDirectory(_vaultName);
    final attDir = Directory(p.join(vaultDir.path, 'attachments', sessionId));
    if (attDir.existsSync()) {
      await attDir.delete(recursive: true);
    }
  }

  /// 一键清理所有孤立的附件文件夹
  Future<int> clearAllOrphans() async {
    int clearedBytes = 0;
    final folders = await scanAttachments();
    for (final folder in folders.where((f) => f.isOrphan)) {
      clearedBytes += folder.totalBytes;
      await deleteAttachmentFolder(folder.sessionId);
    }
    return clearedBytes;
  }
}

@riverpod
AttachmentService attachmentService(Ref ref) {
  final db = ref.watch(agentDatabaseProvider);
  final pathService = ref.watch(storagePathServiceProvider);
  final vaultName = ref.watch(activeVaultNameProvider) ?? 'Personal';
  return AttachmentService(db, pathService, vaultName);
}

@riverpod
class AttachmentList extends _$AttachmentList {
  @override
  FutureOr<List<AttachmentFolderInfo>> build() {
    return ref.watch(attachmentServiceProvider).scanAttachments();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(attachmentServiceProvider).scanAttachments());
  }
}

