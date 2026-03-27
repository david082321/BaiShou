import 'dart:convert';
import 'dart:io';
import 'package:baishou/core/services/data_refresh_notifier.dart';

import 'package:baishou/features/diary/data/vault_index_notifier.dart';
import 'package:baishou/features/index/data/shadow_index_sync_service.dart';
import 'package:baishou/features/summary/domain/services/summary_sync_service.dart';
import 'package:baishou/features/settings/domain/services/import_service.dart';
import 'package:baishou/core/storage/storage_path_provider.dart';
import 'package:baishou/core/database/app_database.dart' hide Diary, Summary;
import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/core/storage/legacy_archive_import_service.dart';
import 'package:baishou/core/storage/vault_service.dart';
import 'package:baishou/core/services/api_config_service.dart';
import 'package:baishou/features/settings/domain/services/data_sync_config_service.dart';
import 'package:baishou/features/settings/domain/services/user_profile_service.dart';
import 'package:baishou/core/theme/theme_service.dart';
import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart' hide Summary;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:baishou/i18n/strings.g.dart';

part 'data_archive_manager.g.dart';

/// 全局数据归档管理器
/// 统一收口导出、导入、快照操作。协调各底层服务的数据流转与状态同步。
/// 导出时自动序列化设备级偏好配置（API Key、主题色、同步设定等）到 ZIP 内部。
/// 导入时自动从 ZIP 中恢复设备级偏好配置。
@Riverpod(keepAlive: true)
class DataArchiveManager extends _$DataArchiveManager {
  VaultIndex get _vaultIndex => ref.read(vaultIndexProvider.notifier);
  ShadowIndexSyncService get _shadowIndexSyncService =>
      ref.read(shadowIndexSyncServiceProvider.notifier);

  @override
  void build() {}

  /// 导出为本地 ZIP 文件（提供给用户选择保存位置）
  Future<File?> exportToUserDevice() async {
    final zipFile = await exportToTempFile();
    if (zipFile == null) return null;

    final now = DateTime.now();
    final fileName =
        'BaiShou_Vault_Backup_${DateFormat('yyyyMMdd_HHmmss').format(now)}.zip';

    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: t.settings.select_save_location,
      fileName: fileName,
      allowedExtensions: ['zip'],
      type: FileType.custom,
      bytes: Platform.isAndroid || Platform.isIOS
          ? await zipFile.readAsBytes()
          : null,
    );

    if (outputPath != null) {
      final destFile = File(outputPath);
      if (!Platform.isAndroid && !Platform.isIOS) {
        await zipFile.copy(destFile.path);
      }
      return destFile;
    }
    return null;
  }

  Future<File?> exportToTempFile() async {
    final pathService = ref.read(storagePathServiceProvider);
    final tempDir = await getTemporaryDirectory();
    final zipFileName =
        'BaiShou_Full_Archive_${DateTime.now().millisecondsSinceEpoch}';

    final archive = Archive();
    final tempPath = p.join(tempDir.path, '$zipFileName.tmp');
    final finalPath = p.join(tempDir.path, '$zipFileName.zip');

    void addEntitySafely(FileSystemEntity entity, String relativePath) {
      if (entity is Directory) {
        try {
          for (final child in entity.listSync()) {
            final childName = p.basename(child.path);
            addEntitySafely(child, '$relativePath/$childName');
          }
        } catch (e) {
          debugPrint(
            'DataArchiveManager: Failed to list directory $relativePath: $e',
          );
        }
      } else if (entity is File) {
        try {
          debugPrint('DataArchiveManager: ADDING FILE: $relativePath');
          // 核心修复：坚决禁用 InputFileStream ！！！
          // InputFileStream 会把文件句柄（File Descriptor）一直以挂起的状态保持在内存中，直到最后的 ZipEncoder 消费时才释放。
          // 在物理迁移场景下若有超过 500 个以上的文件（包括日记、总结等），Windows 系统会极其容易撞到单进程 512 句柄锁上限。
          // 一旦触达，这里会静默 throw 并跳过后续文件（如包含 Archives），导致总结丢失。
          // 现在直接阻塞式一次性将所有字节捞入 Heap 再交给 Archive，瞬间斩断文件锁，对于日常百兆内数据轻而易举。
          final bytes = entity.readAsBytesSync();
          archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
        } catch (e) {
          debugPrint(
            'DataArchiveManager: Skipped locked file $relativePath: $e',
          );
        }
      }
    }

    final rootDir = await pathService.getRootDirectory();
    debugPrint('DataArchiveManager: ROOT DIR IS ${rootDir.path}');
    final entities = rootDir.listSync();
    debugPrint(
      'DataArchiveManager: ENTITIES ARE $entities',
    ); // 只打包物理引擎需要的数据文件，避开可能循环嵌套的 snapshots 快照目录
    for (final entity in entities) {
      final name = p.basename(entity.path);
      if (name == 'snapshots' || name == 'temp') continue;
      if (name.startsWith('BaiShou_Full_Archive_')) continue;
      addEntitySafely(entity, name);
    }

    // 在已生成的 ZIP 流中直接追加设备级偏好配置文件，避免将整个 ZIP 读入内存(防止 OOM)
    try {
      final configJson = _gatherDevicePreferences();
      final configBytes = utf8.encode(jsonEncode(configJson));
      archive.addFile(
        ArchiveFile(
          'config/device_preferences.json',
          configBytes.length,
          configBytes,
        ),
      );
      debugPrint('DataArchiveManager: ADDING CONFIG');

      // 用户头像也一并写入
      final userProfile = ref.read(userProfileProvider);
      if (userProfile.avatarPath != null) {
        final avatarFile = File(userProfile.avatarPath!);
        if (avatarFile.existsSync()) {
          final bytes = avatarFile.readAsBytesSync();
          final ext = p.extension(userProfile.avatarPath!).replaceAll('.', '');
          archive.addFile(ArchiveFile('config/avatar.$ext', bytes.length, bytes));
          debugPrint('DataArchiveManager: ADDING AVATAR');
        }
      }

      // 伙伴头像：扫描 appDir/avatars/ 目录，打包到 assistant_avatars/
      final appDir = await getApplicationDocumentsDirectory();
      final assistantAvatarsDir = Directory(p.join(appDir.path, 'avatars'));
      if (assistantAvatarsDir.existsSync()) {
        for (final entity in assistantAvatarsDir.listSync()) {
          if (entity is File) {
            try {
              final bytes = entity.readAsBytesSync();
              final name = p.basename(entity.path);
              archive.addFile(
                ArchiveFile('assistant_avatars/$name', bytes.length, bytes),
              );
              debugPrint('DataArchiveManager: ADDING ASSISTANT AVATAR: $name');
            } catch (e) {
              debugPrint(
                'DataArchiveManager: Skipped assistant avatar ${entity.path}: $e',
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint('DataArchiveManager: Failed to inject device preferences: $e');
    }

    final outputStream = OutputFileStream(tempPath);
    ZipEncoder().encode(archive, output: outputStream);
    outputStream.close();

    // 清理临时生成的文件
    try {
      final configTempFile = File(
        p.join(tempDir.path, 'temp_device_preferences.json'),
      );
      if (configTempFile.existsSync()) configTempFile.deleteSync();
    } catch (_) {}

    // 最终重命名为目标的 .zip
    final zipFile = File(tempPath);
    try {
      return await zipFile.rename(finalPath);
    } catch (e) {
      // 容错: 跨区映射等极端情况下 rename 失败，走 copy + delete
      await zipFile.copy(finalPath);
      zipFile.delete().ignore();
      return File(finalPath);
    }
  }

  /// 从各服务收集设备级偏好配置，返回可序列化的 Map
  Map<String, dynamic> _gatherDevicePreferences() {
    final apiConfig = ref.read(apiConfigServiceProvider);
    final dataSyncConfig = ref.read(dataSyncConfigServiceProvider);
    final userProfile = ref.read(userProfileProvider);
    final themeState = ref.read(themeProvider);

    return {
      // 用户身份
      'nickname': userProfile.nickname,
      'identity_facts': userProfile.identityFacts,

      // 主题
      'theme_mode': themeState.mode.index,
      'seed_color': themeState.seedColor.value,

      // AI 多供应商架构
      'ai_providers_list': apiConfig
          .getProviders()
          .map((p) => p.toMap())
          .toList(),
      'global_dialogue_provider_id': apiConfig.globalDialogueProviderId,
      'global_dialogue_model_id': apiConfig.globalDialogueModelId,
      'global_naming_provider_id': apiConfig.globalNamingProviderId,
      'global_naming_model_id': apiConfig.globalNamingModelId,
      'global_summary_provider_id': apiConfig.globalSummaryProviderId,
      'global_summary_model_id': apiConfig.globalSummaryModelId,
      // 兼容旧字段
      'ai_provider': apiConfig.activeProviderId,
      'ai_model': apiConfig.getActiveProvider()?.defaultDialogueModel ?? '',
      'ai_naming_model':
          apiConfig.getActiveProvider()?.defaultNamingModel ?? '',
      'api_key': apiConfig.getActiveProvider()?.apiKey ?? '',
      'base_url': apiConfig.getActiveProvider()?.baseUrl ?? '',

      // 数据同步服务配置 (WebDAV, S3 等)
      'sync_target': dataSyncConfig.syncTarget.index,
      'webdav_url': dataSyncConfig.webdavUrl,
      'webdav_username': dataSyncConfig.webdavUsername,
      'webdav_password': dataSyncConfig.webdavPassword,
      'webdav_path': dataSyncConfig.webdavPath,
      's3_endpoint': dataSyncConfig.s3Endpoint,
      's3_access_key': dataSyncConfig.s3AccessKey,
      's3_secret_key': dataSyncConfig.s3SecretKey,
      's3_bucket': dataSyncConfig.s3Bucket,
      's3_region': dataSyncConfig.s3Region,
      's3_path': dataSyncConfig.s3Path,

      // 全局 Embedding 配置
      'global_embedding_provider_id': apiConfig.globalEmbeddingProviderId,
      'global_embedding_model_id': apiConfig.globalEmbeddingModelId,
      'global_embedding_dimension': apiConfig.globalEmbeddingDimension,

      // AI 伙伴环境偏好
      'monthly_summary_source': apiConfig.monthlySummarySource,
      'agent_context_window_size': apiConfig.agentContextWindowSize,
      'companion_compress_tokens': apiConfig.companionCompressTokens,
      'companion_truncate_tokens': apiConfig.companionTruncateTokens,
      'agent_persona': apiConfig.agentPersona,
      'agent_guidelines': apiConfig.agentGuidelines,

      // 工具及 RAG 体系配置
      'disabled_tool_ids': apiConfig.disabledToolIds,
      'rag_global_enabled': apiConfig.ragEnabled,
      'rag_top_k': apiConfig.ragTopK,
      'rag_similarity_threshold': apiConfig.ragSimilarityThreshold,
      'summary_prompt_instructions': apiConfig.summaryInstructions ?? '',
      'all_summary_instructions': apiConfig.exportAllSummaryInstructions(),
      'all_tool_configs': apiConfig.exportAllToolConfigs(),

      // MCP Server 配置
      'mcp_server_enabled': apiConfig.mcpEnabled,
      'mcp_server_port': apiConfig.mcpPort,

      // 实时网络搜索配置
      'web_search_engine': apiConfig.webSearchEngine,
      'web_search_max_results': apiConfig.webSearchMaxResults,
      'web_search_rag_enabled': apiConfig.webSearchRagEnabled,
      'tavily_api_key': apiConfig.tavilyApiKey,
      'web_search_rag_max_chunks': apiConfig.webSearchRagMaxChunks,
      'web_search_rag_chunks_per_source': apiConfig.webSearchRagChunksPerSource,
      'web_search_plain_snippet_length': apiConfig.webSearchPlainSnippetLength,
    };
  }

  /// 从物理 ZIP 全量迁移并注入数据，并彻底重置所有的本地状态与 UI
  /// 同时自动恢复 ZIP 中携带的设备级偏好配置（API Key、主题、同步设定等）
  Future<ImportResult> importFromZip(
    File zipFile, {
    bool createSnapshotBefore = true,
  }) async {
    final vaultIndex = _vaultIndex;
    final shadowIndexSyncService = _shadowIndexSyncService;
    final summarySyncService = ref.read(summarySyncServiceProvider.notifier);
    final pathService = ref.read(storagePathServiceProvider);

    try {
      String? snapshotPath;
      if (createSnapshotBefore) {
        final snapshotFile = await createSnapshot();
        snapshotPath = snapshotFile?.path;
      }

      // 1. 先清空 UI 内存，防止脏读
      vaultIndex.clear();
      summarySyncService.setSyncEnabled(false);
      shadowIndexSyncService.setSyncEnabled(false);
      await summarySyncService.waitForScan();
      await shadowIndexSyncService.waitForScan();

      // 2. 检查解压包的合法性并确定导入策略
      final bytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);
      bool isVaultRoot = archive.any(
        (f) => f.name
            .replaceAll('\\', '/')
            .contains('.baishou/vault_registry.json'),
      );

      // 降级兼容：旧版 JSON 格式备份包（含 manifest.json 而无 vault_registry.json）
      if (!isVaultRoot) {
        final isLegacyFormat = archive.any(
          (f) => f.name.replaceAll('\\', '/').endsWith('manifest.json'),
        );
        if (isLegacyFormat) {
          debugPrint(
            'DataArchiveManager: Detected legacy JSON backup, delegating to LegacyArchiveImportService...',
          );
          // 注意：此处不主动关闭数据库，直接走逻辑导入
          return await ref
              .read(legacyArchiveImportServiceProvider.notifier)
              .importLegacyZip(archive, snapshotPath);
        }
        throw Exception(t.settings.restore_failed_generic);
      }

      // 3. 开始执行物理级全量恢复：先斩断当前所有打开的 SQLite 对象连接，释放文件锁
      await closeAppDatabase();
      await closeAllAgentDatabases();

      // 4. 删除旧的工作区根目录
      final rootDir = await pathService.getRootDirectory();

      // 提前提取设备级偏好配置（在湮灭旧目录之前保存好）
      Map<String, dynamic>? devicePreferences;
      final configFile = archive.findFile('config/device_preferences.json');
      if (configFile != null) {
        try {
          final configStr = utf8.decode(configFile.content);
          devicePreferences = jsonDecode(configStr) as Map<String, dynamic>;
        } catch (e) {
          debugPrint(
            'DataArchiveManager: Failed to parse device preferences: $e',
          );
        }
      }

      // 提取头像文件
      ArchiveFile? avatarArchiveFile;
      for (final f in archive) {
        if (f.name.startsWith('config/avatar.') && !f.isFile) continue;
        if (f.name.startsWith('config/avatar.')) {
          avatarArchiveFile = f;
          break;
        }
      }

      // 重启并清空
      if (rootDir.existsSync()) {
        try {
          rootDir.deleteSync(recursive: true);
        } catch (e) {
          debugPrint('Fatal file lock error while wiping root: $e');
        }
      }
      rootDir.createSync(recursive: true);

      // 4. 将解压包的所有血管注入宿主机器（物理重叠）
      // 跳过 config/ 目录下的设备级配置文件（它们不属于工作区物理结构）
      final filteredArchive = Archive();
      for (final file in archive) {
        if (file.name.startsWith('config/')) continue;
        filteredArchive.addFile(file);
      }
      extractArchiveToDisk(filteredArchive, rootDir.path);

      // 4.5 【关键修复】跨端路径重映射
      // vault_registry.json 中的 path 字段存储的是源设备的绝对路径（如 Windows 的 C:\Users\...）。
      // 当 ZIP 被解压到另一台设备（如 Android）时，这些路径在目标设备上根本不存在。
      // 如果不修正，后续的 fullScanArchives / fullScanVault 会因路径无效而扫描为空，
      // 导致总结等数据在数据库中被清零。
      try {
        final registryDir = Directory(
          p.join(rootDir.path, StoragePathService.systemFolderName),
        );
        final registryFile = File(
          p.join(registryDir.path, 'vault_registry.json'),
        );
        if (registryFile.existsSync()) {
          final content = await registryFile.readAsString();
          final List<dynamic> vaults = jsonDecode(content);
          bool modified = false;
          for (int i = 0; i < vaults.length; i++) {
            final vault = vaults[i] as Map<String, dynamic>;
            final vaultName = vault['name'] as String;
            // 用当前设备的实际根目录重新拼接路径
            final correctPath = p.join(rootDir.path, vaultName);
            if (vault['path'] != correctPath) {
              vault['path'] = correctPath;
              modified = true;
            }
          }
          if (modified) {
            await registryFile.writeAsString(jsonEncode(vaults));
            debugPrint(
              'DataArchiveManager: Remapped ${vaults.length} vault paths in registry to local device.',
            );
          }
        }
      } catch (e) {
        debugPrint(
          'DataArchiveManager: Failed to remap vault registry paths: $e',
        );
      }

      // 5. 恢复设备级偏好配置（API Key、主题色、同步设定等）
      // 必须在 invalidate 之前执行，因为 invalidate 会触发 provider 重建，
      // 可能引发并发修改异常导致后续步骤被中断。
      if (devicePreferences != null) {
        await _restoreDevicePreferences(devicePreferences, avatarArchiveFile);
      }

      // 5.5 恢复伙伴头像：从 assistant_avatars/ 提取到 appDir/avatars/
      // 并修正数据库中的 avatarPath（跨端路径重映射）
      String? localAvatarsPath;
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final avatarsDir = Directory(p.join(appDir.path, 'avatars'));
        localAvatarsPath = avatarsDir.path;
        final assistantAvatarFiles =
            archive.where((f) => f.name.startsWith('assistant_avatars/') && f.isFile);

        if (assistantAvatarFiles.isNotEmpty) {
          if (!avatarsDir.existsSync()) {
            avatarsDir.createSync(recursive: true);
          }
          for (final avatarEntry in assistantAvatarFiles) {
            final fileName = p.basename(avatarEntry.name);
            final localFile = File(p.join(avatarsDir.path, fileName));
            await localFile.writeAsBytes(avatarEntry.content);
            debugPrint('DataArchiveManager: Restored assistant avatar: $fileName');
          }
        }
      } catch (e) {
        debugPrint('DataArchiveManager: Failed to restore assistant avatars: $e');
      }

      // 6. 让 Riverpod 的持久化 Provider 失效，从而强制挂载新物理文件
      ref.invalidate(appDatabaseProvider);
      ref.invalidate(agentDatabaseProvider);
      ref.invalidate(vaultServiceProvider);

      // 等待 provider 重建稳定后再触发扫描
      await Future.delayed(const Duration(milliseconds: 200));

      // 6.5 修正伙伴头像的跨端路径：
      // agent_assistants 表中的 avatar_path 列是源设备的绝对路径，
      // 需要将目录部分替换为本地 avatars 目录。
      if (localAvatarsPath != null) {
        try {
          final agentDb = ref.read(agentDatabaseProvider);
          final rows = await agentDb.customSelect(
            'SELECT id, avatar_path FROM agent_assistants WHERE avatar_path IS NOT NULL',
          ).get();
          for (final row in rows) {
            final oldPath = row.read<String>('avatar_path');
            // 取出文件名（兼容 Windows 和 Unix 路径分隔符）
            final fileName = oldPath.split(RegExp(r'[/\\]')).last;
            final newPath = p.join(localAvatarsPath, fileName);
            if (oldPath != newPath) {
              await agentDb.customStatement(
                'UPDATE agent_assistants SET avatar_path = ? WHERE id = ?',
                [newPath, row.read<String>('id')],
              );
              debugPrint(
                'DataArchiveManager: Remapped assistant avatar path: '
                '$oldPath -> $newPath',
              );
            }
          }
        } catch (e) {
          debugPrint('DataArchiveManager: Failed to remap assistant avatar paths: $e');
        }
      }

      // 重新对齐并点火
      summarySyncService.setSyncEnabled(true);
      shadowIndexSyncService.setSyncEnabled(true);
      await summarySyncService.fullScanArchives(force: true);
      await shadowIndexSyncService.fullScanVault();
      await vaultIndex.forceReload();

      ref.read(dataRefreshProvider.notifier).refresh();

      return ImportResult(
        fileCount: archive.length,
        profileRestored: devicePreferences != null,
        snapshotPath: snapshotPath,
      );
    } catch (e) {
      debugPrint('DataArchiveManager Import Error: $e');
      try {
        summarySyncService.setSyncEnabled(true);
        shadowIndexSyncService.setSyncEnabled(true);
        await shadowIndexSyncService.fullScanVault();
        await vaultIndex.forceReload();
      } catch (_) {}
      rethrow;
    }
  }

  /// 恢复设备级偏好配置（从 ZIP 中提取的 JSON 数据）
  Future<void> _restoreDevicePreferences(
    Map<String, dynamic> config,
    ArchiveFile? avatarFile,
  ) async {
    try {
      final importService = ref.read(importServiceProvider);
      await importService.restoreConfig(config);

      // 恢复头像（从 ZIP 中提取的二进制文件）
      if (avatarFile != null && avatarFile.content.isNotEmpty) {
        try {
          final ext = p.extension(avatarFile.name).replaceAll('.', '');
          final appDir = await getApplicationDocumentsDirectory();
          final avatarDir = Directory(p.join(appDir.path, 'avatars'));
          if (!avatarDir.existsSync()) {
            await avatarDir.create(recursive: true);
          }
          final localAvatarFile = File(
            p.join(
              avatarDir.path,
              'avatar_imported_${DateTime.now().millisecondsSinceEpoch}.$ext',
            ),
          );
          await localAvatarFile.writeAsBytes(avatarFile.content);
          await ref
              .read(userProfileProvider.notifier)
              .updateAvatar(localAvatarFile);
        } catch (e) {
          debugPrint('DataArchiveManager: Failed to restore avatar: $e');
        }
      }
    } catch (e) {
      debugPrint(
        'DataArchiveManager: Failed to restore device preferences: $e',
      );
      // 配置恢复失败不阻塞导入流程——工作区数据已经完整恢复
    }
  }

  /// 主动生成系统快照，存入应用的私有 snapshots 目录
  Future<File?> createSnapshot() async {
    try {
      final snapshotFile = await exportToTempFile();
      if (snapshotFile != null) {
        final appDir = await getApplicationDocumentsDirectory();
        final snapshotDir = Directory(p.join(appDir.path, 'snapshots'));
        if (!snapshotDir.existsSync()) {
          await snapshotDir.create(recursive: true);
        }
        final now = DateTime.now();
        final snapshotName =
            'snapshot_${DateFormat('yyyyMMdd_HHmmss').format(now)}.zip';
        final destFile = File(p.join(snapshotDir.path, snapshotName));
        await snapshotFile.copy(destFile.path);

        try {
          await snapshotFile.delete();
        } catch (_) {}

        debugPrint('DataArchiveManager: Snapshot created at ${destFile.path}');
        return destFile;
      }
    } catch (e) {
      debugPrint('DataArchiveManager: Failed to create snapshot: $e');
    }
    return null;
  }

  /// 获取历史快照列表 (可限定返回的最大数量)
  Future<List<File>> listSnapshots({int maxCount = 5}) async {
    final appDir = await getApplicationDocumentsDirectory();
    final snapshotDir = Directory(p.join(appDir.path, 'snapshots'));
    if (!snapshotDir.existsSync()) {
      return [];
    }

    final entities = snapshotDir.listSync().whereType<File>().toList();
    // 按修改时间降序排列 (最新的在前)
    entities.sort(
      (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
    );

    // 如果超过最大数量，自动清理旧快照
    if (entities.length > maxCount) {
      final toDelete = entities.sublist(maxCount);
      for (final file in toDelete) {
        try {
          await file.delete();
        } catch (_) {}
      }
      return entities.sublist(0, maxCount);
    }

    return entities;
  }
}
