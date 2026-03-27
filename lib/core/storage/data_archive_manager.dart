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
    final fileName = 'BaiShou_Vault_Backup_${DateFormat('yyyyMMdd_HHmmss').format(now)}.zip';

    final outputPath = await FilePicker.platform.saveFile(
      dialogTitle: t.settings.select_save_location,
      fileName: fileName,
      allowedExtensions: ['zip'],
      type: FileType.custom,
      bytes: Platform.isAndroid || Platform.isIOS ? await zipFile.readAsBytes() : null,
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

  /// 隐式导出至系统临时目录，用于局域网快传或全量云同步
  /// 采用革命性的纯物理层面打包，100% 毫无损耗地拷贝 BaiShou_Root 下的所有文件！
  /// 同时将设备级偏好配置（SharedPreferences）序列化后一并写入 ZIP。
  Future<File?> exportToTempFile() async {
    final pathService = ref.read(storagePathServiceProvider);
    final rootDir = await pathService.getRootDirectory();

    final encoder = ZipFileEncoder();
    final tempDir = await getTemporaryDirectory();
    final tempPath = p.join(tempDir.path, 'BaiShou_Full_Archive_${DateTime.now().millisecondsSinceEpoch}.zip');
    
    // 生成原生 ZIP
    encoder.create(tempPath);
    
    // 只打包物理引擎需要的数据文件，避开可能循环嵌套的 snapshots 快照目录
    final entities = rootDir.listSync();
    for (final entity in entities) {
      final name = p.basename(entity.path);
      if (name == 'snapshots' || name == 'temp') continue;
      
      if (entity is Directory) {
        encoder.addDirectory(entity);
      } else if (entity is File) {
        encoder.addFile(entity);
      }
    }
    encoder.close();

    // 在已生成的 ZIP 中追加设备级偏好配置文件
    await _injectDevicePreferencesIntoZip(tempPath);

    return File(tempPath);
  }

  /// 将设备级偏好（SharedPreferences 中的配置）序列化为 JSON 并注入到 ZIP 中
  Future<void> _injectDevicePreferencesIntoZip(String zipPath) async {
    try {
      final configJson = _gatherDevicePreferences();
      final configBytes = utf8.encode(jsonEncode(configJson));

      // 读取已有的 ZIP，追加 config 文件，再重新写回
      final zipFile = File(zipPath);
      final zipBytes = await zipFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      archive.addFile(ArchiveFile('config/device_preferences.json', configBytes.length, configBytes));

      // 用户头像也一并写入
      final userProfile = ref.read(userProfileProvider);
      if (userProfile.avatarPath != null) {
        final avatarFile = File(userProfile.avatarPath!);
        if (avatarFile.existsSync()) {
          final avatarBytes = await avatarFile.readAsBytes();
          final ext = p.extension(userProfile.avatarPath!).replaceAll('.', '');
          archive.addFile(ArchiveFile('config/avatar.$ext', avatarBytes.length, avatarBytes));
        }
      }

      final newZipBytes = ZipEncoder().encode(archive);
      await zipFile.writeAsBytes(newZipBytes);
    } catch (e) {
      debugPrint('DataArchiveManager: Failed to inject device preferences: $e');
      // 配置注入失败不阻塞导出流程，物理数据仍然完整
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
      'seed_color': themeState.seedColor.toARGB32(),

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
      'ai_naming_model': apiConfig.getActiveProvider()?.defaultNamingModel ?? '',
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
      bool isVaultRoot = archive.any((f) => f.name.contains('.baishou/vault_registry.json'));
      
      // 降级兼容：旧版 JSON 格式备份包（含 manifest.json 而无 vault_registry.json）
      if (!isVaultRoot) {
        final isLegacyFormat = archive.any((f) => f.name == 'manifest.json' || f.name.endsWith('/manifest.json'));
        if (isLegacyFormat) {
          debugPrint('DataArchiveManager: Detected legacy JSON backup, delegating to LegacyArchiveImportService...');
          // 注意：此处不主动关闭数据库，直接走逻辑导入
          return await ref.read(legacyArchiveImportServiceProvider.notifier).importLegacyZip(archive, snapshotPath);
        }
        throw Exception(t.settings.restore_failed_generic);
      }

      // 3. 开始执行物理级全量恢复：先斩断当前所有打开的 SQLite 对象连接，释放文件锁
      await closeAppDatabase();
      await closeAllAgentDatabases();

      // 4. 物理级湮灭旧的工作区根目录！
      final rootDir = await pathService.getRootDirectory();

      // 提前提取设备级偏好配置（在湮灭旧目录之前保存好）
      Map<String, dynamic>? devicePreferences;
      final configFile = archive.findFile('config/device_preferences.json');
      if (configFile != null) {
        try {
          final configStr = utf8.decode(configFile.content);
          devicePreferences = jsonDecode(configStr) as Map<String, dynamic>;
        } catch (e) {
          debugPrint('DataArchiveManager: Failed to parse device preferences: $e');
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

      // 5. 让 Riverpod 的持久化 Provider 失效，从而强制挂载新物理文件
      ref.invalidate(appDatabaseProvider);
      ref.invalidate(agentDatabaseProvider);
      ref.invalidate(vaultServiceProvider);
      
      // 6. 恢复设备级偏好配置（API Key、主题色、同步设定等）
      if (devicePreferences != null) {
        await _restoreDevicePreferences(devicePreferences, avatarArchiveFile);
      }

      // 重新对齐并点火
      summarySyncService.setSyncEnabled(true);
      shadowIndexSyncService.setSyncEnabled(true);
      await summarySyncService.fullScanArchives();
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
          final localAvatarFile = File(p.join(
            avatarDir.path,
            'avatar_imported_${DateTime.now().millisecondsSinceEpoch}.$ext',
          ));
          await localAvatarFile.writeAsBytes(avatarFile.content);
          await ref.read(userProfileProvider.notifier).updateAvatar(localAvatarFile);
        } catch (e) {
          debugPrint('DataArchiveManager: Failed to restore avatar: $e');
        }
      }
    } catch (e) {
      debugPrint('DataArchiveManager: Failed to restore device preferences: $e');
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
