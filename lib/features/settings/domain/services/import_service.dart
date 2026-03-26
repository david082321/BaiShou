import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:baishou/core/database/tables/summaries.dart';
import 'package:baishou/core/services/api_config_service.dart';
import 'package:baishou/core/theme/theme_service.dart';
import 'package:baishou/agent/models/ai_provider_model.dart';
import 'package:baishou/features/diary/data/repositories/diary_repository_impl.dart';
import 'package:baishou/features/diary/domain/entities/diary.dart';
import 'package:baishou/features/diary/domain/repositories/diary_repository.dart';
import 'package:baishou/features/settings/domain/services/data_sync_config_service.dart';
import 'package:baishou/features/settings/domain/services/user_profile_service.dart';
import 'package:baishou/features/summary/data/repositories/summary_repository_impl.dart';
import 'package:baishou/features/summary/domain/entities/summary.dart';
import 'package:baishou/features/summary/domain/repositories/summary_repository.dart';
import 'package:flutter/foundation.dart' hide Summary;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:baishou/features/storage/domain/services/journal_file_service.dart';
import 'package:baishou/features/settings/domain/services/import_models.dart';
import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/core/storage/storage_path_provider.dart';
import 'package:baishou/core/storage/vault_service.dart';
import 'package:drift/drift.dart' show InsertMode, Value;
export 'package:baishou/features/settings/domain/services/import_models.dart';

/// 在 Isolate 中运行的解析函数
/// 接收 zip 路径与传入的 tempDir 路径
Future<ParsedImportData> parseZipData(Map<String, String> args) async {
  final zipFilePath = args['zip']!;
  final tempDir = Directory(args['temp']!);

  // 使用 archive_io 直接解压到磁盘
  await extractFileToDisk(zipFilePath, tempDir.path);

  // 辅助函数：读取并解析 JSON 文件
  dynamic parseJsonFile(String relativePath) {
    final file = File(path.join(tempDir.path, relativePath));
    if (!file.existsSync()) return null;
    try {
      final content = file.readAsStringSync();
      return jsonDecode(content);
    } catch (_) {
      return null;
    }
  }

  // 1. 读取并验证 manifest
  final manifest = parseJsonFile('manifest.json');

  // 2. 读取其他数据
  final diaries = parseJsonFile('data/diaries.json') as List<dynamic>?;
  final summaries = parseJsonFile('data/summaries.json') as List<dynamic>?;
  final config =
      parseJsonFile('config/user_profile.json') as Map<String, dynamic>?;

  // 3. 读取跨平台 Agent 数据与 RAG
  return ParsedImportData(
    manifest: manifest as Map<String, dynamic>,
    diaries: diaries,
    summaries: summaries,
    config: config,
    aiAssistants: parseJsonFile('data/ai_assistants.json') as List<dynamic>?,
    agentSessions: parseJsonFile('data/agent_sessions.json') as List<dynamic>?,
    agentMessages: parseJsonFile('data/agent_messages.json') as List<dynamic>?,
    agentParts: parseJsonFile('data/agent_parts.json') as List<dynamic>?,
    agentEmbeddings:
        parseJsonFile('data/agent_embeddings.json') as List<dynamic>?,
  );
}

class ImportService {
  final DiaryRepository _diaryRepository;
  final SummaryRepository _summaryRepository;
  final UserProfileNotifier _profileNotifier;
  final ThemeNotifier _themeNotifier;
  final ApiConfigService _apiConfig;
  final DataSyncConfigService _dataSyncConfig;
  final JournalFileService _journalFileService;
  final AgentDatabase _agentDatabase;
  final VaultService _vaultService;
  final StoragePathService _storagePathService;

  ImportService({
    required DiaryRepository diaryRepository,
    required SummaryRepository summaryRepository,
    required UserProfileNotifier profileNotifier,
    required ThemeNotifier themeNotifier,
    required ApiConfigService apiConfig,
    required DataSyncConfigService dataSyncConfig,
    required JournalFileService journalFileService,
    required AgentDatabase agentDatabase,
    required VaultService vaultService,
    required StoragePathService storagePathService,
  }) : _diaryRepository = diaryRepository,
       _summaryRepository = summaryRepository,
       _profileNotifier = profileNotifier,
       _themeNotifier = themeNotifier,
       _apiConfig = apiConfig,
       _dataSyncConfig = dataSyncConfig,
       _journalFileService = journalFileService,
       _agentDatabase = agentDatabase,
       _vaultService = vaultService,
       _storagePathService = storagePathService;

  /// 从 ZIP 文件导入备份（覆盖模式：先自动创建快照，再清空数据，最后写入）
  Future<ImportResult> importFromZip(File zipFile) async {
    final stopwatch = Stopwatch()..start();
    debugPrint('Import: Starting import process from ${zipFile.path}');

    final tempZipFile = File(
      path.join(
        Directory.systemTemp.path,
        'import_tmp_${DateTime.now().millisecondsSinceEpoch}.zip',
      ),
    );
    // [NEW] 外置临时抽取主目录以便管理物理附件
    final tempBaseDir = Directory.systemTemp.createTempSync('baishou_import_');

    try {
      debugPrint('Import: Copying ZIP to temporary location...');
      await zipFile.copy(tempZipFile.path);

      debugPrint('Import: Parsing ZIP data in Isolate...');
      // 1. 传递临时文件路径给 isolate
      final parsedData =
          await compute(parseZipData, {
            'zip': tempZipFile.path,
            'temp': tempBaseDir.path,
          }).timeout(
            const Duration(minutes: 2),
            onTimeout: () {
              throw TimeoutException(t.settings.parse_timeout);
            },
          );
      debugPrint('Import: ZIP parsed in ${stopwatch.elapsedMilliseconds}ms');

      // 2. 验证版本
      final schemaVersion = parsedData.manifest['schema_version'] as int? ?? 0;
      if (schemaVersion > 2) {
        return ImportResult(
          error: t.settings.schema_version_too_high(
            version: schemaVersion.toString(),
          ),
        );
      }

      // 3. (自动快照职责已上浮至 DataArchiveManager，此处跳过)
      String? snapshotPath;

      // 4. 清空现有数据（覆盖模式）
      debugPrint('Import: Deleting existing diaries...');
      await _diaryRepository.deleteAllDiaries();
      debugPrint('Import: Deleting existing summaries...');
      await _summaryRepository.deleteAllSummaries();
      debugPrint('Import: Clearing all Agent data...');
      await _agentDatabase.clearAllAgentData();

      // 5. 导入日记
      int diariesImported = 0;
      if (parsedData.diaries != null) {
        debugPrint(
          'Import: Starting batch save for ${parsedData.diaries!.length} diaries...',
        );
        diariesImported = await _importDiaries(
          parsedData.diaries!,
          schemaVersion,
        );
        debugPrint('Import: Diaries batch save complete');
      }

      // 6. 导入总结
      int summariesImported = 0;
      if (parsedData.summaries != null) {
        debugPrint(
          'Import: Starting batch save for ${parsedData.summaries!.length} summaries...',
        );
        summariesImported = await _importSummaries(parsedData.summaries!);
        debugPrint('Import: Summaries batch save complete');
      }

      // [NEW] 6.5 导入 Agent 附属层级与物理附件合并转移 + FTS 索引重建
      await _importAgentData(parsedData, tempBaseDir.path);

      // 7. 返回结果
      return ImportResult(
        diariesImported: diariesImported,
        summariesImported: summariesImported,
        profileRestored: parsedData.config != null,
        configData: parsedData.config,
        snapshotPath: snapshotPath,
      );
    } catch (e) {
      debugPrint('Import error: $e');
      if (e.toString().contains('manifest.json')) {
        return ImportResult(error: t.settings.invalid_backup_missing_manifest);
      }
      return ImportResult(
        error: t.settings.import_failed_with_error(error: e.toString()),
      );
    } finally {
      // 8. 触发索引全量同步 (已上浮至 DataArchiveManager 处理，此处跳过)
      // 9. 彻底清理临时文件逻辑
      if (tempZipFile.existsSync()) {
        try {
          tempZipFile.deleteSync();
          debugPrint('Import: Temporary ZIP deleted');
        } catch (e) {
          debugPrint('Import: Failed to delete temporary ZIP: $e');
        }
      }
      if (tempBaseDir.existsSync()) {
        try {
          tempBaseDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    }
  }

  // --- 私有方法 ---

  Future<int> _importDiaries(
    List<dynamic> diariesJson,
    int schemaVersion,
  ) async {
    // 1. 解析所有日记对象
    final parsedDiaries = <Diary>[];
    for (final item in diariesJson) {
      final map = item as Map<String, dynamic>;
      final date = DateTime.parse(map['date'] as String);
      final rawId = map['id'];
      final int parsedId = rawId is int
          ? rawId
          : (int.tryParse(rawId?.toString() ?? '') ?? 0);

      parsedDiaries.add(
        Diary(
          id: parsedId,
          date: date,
          content: map['content'] as String? ?? '',
          tags: (map['tags'] as List<dynamic>?)?.cast<String>() ?? [],
          createdAt: map['created_at'] != null
              ? DateTime.parse(map['created_at'] as String)
              : DateTime.now(),
          updatedAt: map['updated_at'] != null
              ? DateTime.parse(map['updated_at'] as String)
              : DateTime.now(),
          weather: map['weather'] as String?,
          mood: map['mood'] as String?,
          location: map['location'] as String?,
          locationDetail: map['location_detail'] as String?,
          isFavorite: map['is_favorite'] as bool? ?? false,
          mediaPaths:
              (map['media_paths'] as List<dynamic>?)?.cast<String>() ?? [],
        ),
      );
    }

    // 2. 按天分组并写入物理文件（不写入数据库，由 fullScanVault 处理）
    if (parsedDiaries.isNotEmpty) {
      debugPrint(
        'Import: Grouping and merging ${parsedDiaries.length} diaries...',
      );

      final Map<String, List<Diary>> groupedDiaries = {};
      final DateFormat dayFormatter = DateFormat('yyyy-MM-dd');
      final DateFormat timeFormatter = DateFormat('HH:mm:ss');

      for (final diary in parsedDiaries) {
        final dayKey = dayFormatter.format(diary.date);
        groupedDiaries.putIfAbsent(dayKey, () => []).add(diary);
      }

      int mergedCount = 0;
      for (final entry in groupedDiaries.entries) {
        final list = entry.value;

        // 统一按创建时间自下而上升序排列
        list.sort((a, b) => a.createdAt.compareTo(b.createdAt));

        final buffer = StringBuffer();
        final mergedTags = <String>{};
        final mergedMediaPaths = <String>{};

        for (int i = 0; i < list.length; i++) {
          final d = list[i];

          // 核心逻辑修复：
          // 如果是 v1 (schema_version < 1) 以下的备份，它是一天散落多条日记的结构，需要拼装标题。
          // 如果是 v2 (schema_version >= 1) 及以上的备份，导出的 content 已经是合并完成的物理 markdown 原文（自带了标题），无需画蛇添足。
          if (schemaVersion < 1) {
            buffer.writeln('##### ${timeFormatter.format(d.createdAt)}\n');
          }
          buffer.writeln(d.content.trim());

          if (i < list.length - 1) {
            if (schemaVersion < 1) {
              buffer.writeln('\n---\n');
            } else {
              buffer.writeln();
            }
          }

          mergedTags.addAll(d.tags);
          mergedMediaPaths.addAll(d.mediaPaths);
        }

        // 构建合并后的日记实体（或单篇但也带时间戳标题的实体）
        final latestDiary = list.last;
        final superDiary = latestDiary.copyWith(
          content: buffer.toString().trim(),
          tags: mergedTags.toList(),
          mediaPaths: mergedMediaPaths.toList(),
        );

        await _journalFileService.writeJournal(superDiary);
        mergedCount++;
      }
      debugPrint('Import: Merged into $mergedCount physical daily files.');
    }

    return parsedDiaries.length;
  }

  Future<int> _importSummaries(List<dynamic> summariesJson) async {
    final parsedSummaries = <Summary>[];

    for (final item in summariesJson) {
      final map = item as Map<String, dynamic>;
      final typeStr = map['type'] as String? ?? 'weekly';
      final type = SummaryType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () => SummaryType.weekly,
      );
      final startDate = DateTime.parse(map['start_date'] as String);
      final endDate = DateTime.parse(map['end_date'] as String);
      final rawId = map['id'];
      final int parsedId = rawId is int
          ? rawId
          : (int.tryParse(rawId?.toString() ?? '') ?? 0);

      parsedSummaries.add(
        Summary(
          id: parsedId,
          type: type,
          startDate: startDate,
          endDate: endDate,
          content: map['content'] as String? ?? '',
          sourceIds:
              (map['source_ids'] as List<dynamic>?)?.cast<String>() ?? [],
          generatedAt: DateTime.now(),
        ),
      );
    }

    // 批量插入（数据已被清空，无需去重）
    if (parsedSummaries.isNotEmpty) {
      const batchSize = 100;
      for (var i = 0; i < parsedSummaries.length; i += batchSize) {
        final end = (i + batchSize < parsedSummaries.length)
            ? i + batchSize
            : parsedSummaries.length;
        await _summaryRepository.batchAddSummaries(
          parsedSummaries.sublist(i, end),
        );
      }
    }

    return parsedSummaries.length;
  }

  Future<void> _importAgentData(ParsedImportData data, String tempPath) async {
    // 恢复 SQLite 主要结构（使用 batch API）
    await _agentDatabase.batch((batch) {
      if (data.aiAssistants != null) {
        for (final e in data.aiAssistants!) {
          batch.insert(
            _agentDatabase.agentAssistants,
            AgentAssistantsCompanion.insert(
              id: e['id'] as String,
              name: e['name'] as String? ?? '',
              emoji: Value(e['emoji'] as String?),
              description: Value(e['description'] as String? ?? ''),
              avatarPath: Value(e['avatar_path'] as String?),
              systemPrompt: Value(e['system_prompt'] as String? ?? ''),
              isDefault: Value(e['is_default'] as bool? ?? false),
              contextWindow: Value(e['context_window'] as int? ?? 20),
              providerId: Value(e['provider_id'] as String?),
              modelId: Value(e['model_id'] as String?),
              compressTokenThreshold: Value(
                e['compress_token_threshold'] as int? ?? 60000,
              ),
              compressKeepTurns: Value(e['compress_keep_turns'] as int? ?? 3),
              sortOrder: Value(e['sort_order'] as int? ?? 0),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      }
      if (data.agentSessions != null) {
        for (final e in data.agentSessions!) {
          batch.insert(
            _agentDatabase.agentSessions,
            AgentSessionsCompanion.insert(
              id: e['id'] as String,
              vaultName: e['vault_name'] as String? ?? '',
              providerId: e['provider_id'] as String? ?? '',
              modelId: e['model_id'] as String? ?? '',
              title: Value(e['title'] as String? ?? ''),
              assistantId: Value(e['assistant_id'] as String?),
              isPinned: Value(e['is_pinned'] as bool? ?? false),
              systemPrompt: Value(e['system_prompt'] as String?),
              totalInputTokens: Value(e['total_input_tokens'] as int? ?? 0),
              totalOutputTokens: Value(e['total_output_tokens'] as int? ?? 0),
              totalCostMicros: Value(e['total_cost_micros'] as int? ?? 0),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      }
      if (data.agentMessages != null) {
        for (final e in data.agentMessages!) {
          batch.insert(
            _agentDatabase.agentMessages,
            AgentMessagesCompanion.insert(
              id: e['id'] as String? ?? '',
              sessionId: e['session_id'] as String? ?? '',
              role: e['role'] as String? ?? 'user',
              orderIndex: e['order_index'] as int? ?? 0,
              isSummary: Value(e['is_summary'] as bool? ?? false),
              askId: Value(e['ask_id'] as String?),
              providerId: Value(e['provider_id'] as String?),
              modelId: Value(e['model_id'] as String?),
              inputTokens: Value(e['input_tokens'] as int?),
              outputTokens: Value(e['output_tokens'] as int?),
              costMicros: Value(e['cost_micros'] as int?),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      }
      if (data.agentParts != null) {
        for (final e in data.agentParts!) {
          batch.insert(
            _agentDatabase.agentParts,
            AgentPartsCompanion.insert(
              id: e['id'] as String? ?? '',
              messageId: e['message_id'] as String? ?? '',
              sessionId: e['session_id'] as String? ?? '',
              type: e['type'] as String? ?? 'text',
              data: e['data'] as String? ?? '',
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      }
    });

    // 恢复 RAG 向量并进行反向 Base64 解封装
    if (data.agentEmbeddings != null) {
      final mapped = data.agentEmbeddings!.map((e) {
        final Map<String, dynamic> row = Map<String, dynamic>.from(e);
        if (row['embedding'] is String) {
          row['embedding'] = base64Decode(row['embedding'] as String);
        }
        return row;
      }).toList();
      await _agentDatabase.importEmbeddingsRaw(mapped);
    }

    // 拷贝物理附件
    final currentVault = _vaultService.state.value;
    if (currentVault != null) {
      final extractedAttachDir = Directory(path.join(tempPath, 'attachments'));
      if (extractedAttachDir.existsSync()) {
        final destVaultDir = await _storagePathService.getVaultDirectory(
          currentVault.name,
        );
        final destAttachDir = Directory(
          path.join(destVaultDir.path, 'attachments'),
        );
        if (destAttachDir.existsSync()) {
          destAttachDir.deleteSync(recursive: true);
        }
        destAttachDir.createSync(recursive: true);

        final files = extractedAttachDir.listSync(recursive: true);
        for (final entity in files) {
          if (entity is File) {
            final relPath = path.relative(
              entity.path,
              from: extractedAttachDir.path,
            );
            final targetPath = path.join(destAttachDir.path, relPath);
            final targetFile = File(targetPath);
            if (!targetFile.parent.existsSync()) {
              targetFile.parent.createSync(recursive: true);
            }
            await entity.copy(targetPath);
          }
        }
      }
    }

    // 触发全文索引重建
    await _agentDatabase.rebuildFtsIndex();
  }

  /// 恢复用户配置（主题、API Key 等）
  /// 注意：此方法会触发主题变更，必须在所有 Dialog 关闭后再调用
  Future<void> restoreConfig(Map<String, dynamic> config) async {
    // 恢复昵称
    final nickname = config['nickname'] as String?;
    if (nickname != null && nickname.isNotEmpty) {
      await _profileNotifier.updateNickname(nickname);
    }

    // 恢复主题色
    final seedColorValue = config['seed_color'] as int?;
    if (seedColorValue != null) {
      await _themeNotifier.setSeedColor(Color(seedColorValue));
    }

    // 恢复深色模式
    final themeModeIndex = config['theme_mode'] as int?;
    if (themeModeIndex != null &&
        themeModeIndex >= 0 &&
        themeModeIndex < ThemeMode.values.length) {
      await _themeNotifier.setThemeMode(ThemeMode.values[themeModeIndex]);
    }

    // 恢复 AI 配置
    final aiProvidersList = config['ai_providers_list'] as List<dynamic>?;

    if (aiProvidersList != null) {
      // 1. 导入多供应商新架构数据
      for (final pMap in aiProvidersList) {
        var provider = AiProviderModel.fromMap(pMap as Map<String, dynamic>);

        // 避免在一端配置好而另一端为空时互相覆盖置空
        final existingProvider = _apiConfig.getProvider(provider.id);
        if (existingProvider != null) {
          final shouldKeepUrl =
              provider.baseUrl.isEmpty && existingProvider.baseUrl.isNotEmpty;
          final shouldKeepKey =
              provider.apiKey.isEmpty && existingProvider.apiKey.isNotEmpty;

          if (shouldKeepUrl || shouldKeepKey) {
            provider = provider.copyWith(
              baseUrl: shouldKeepUrl
                  ? existingProvider.baseUrl
                  : provider.baseUrl,
              apiKey: shouldKeepKey ? existingProvider.apiKey : provider.apiKey,
            );
          }
        }

        await _apiConfig.updateProvider(provider);
      }

      // 2. 恢复新的全局默认模型设定
      final globalDialogueProviderId =
          config['global_dialogue_provider_id'] as String?;
      final globalDialogueModelId =
          config['global_dialogue_model_id'] as String?;
      if (globalDialogueProviderId != null && globalDialogueModelId != null) {
        await _apiConfig.setGlobalDialogueModel(
          globalDialogueProviderId,
          globalDialogueModelId,
        );
      }

      final globalNamingProviderId =
          config['global_naming_provider_id'] as String?;
      final globalNamingModelId = config['global_naming_model_id'] as String?;
      if (globalNamingProviderId != null && globalNamingModelId != null) {
        await _apiConfig.setGlobalNamingModel(
          globalNamingProviderId,
          globalNamingModelId,
        );
      }

      final globalSummaryProviderId =
          config['global_summary_provider_id'] as String?;
      final globalSummaryModelId = config['global_summary_model_id'] as String?;
      if (globalSummaryProviderId != null && globalSummaryModelId != null) {
        await _apiConfig.setGlobalSummaryModel(
          globalSummaryProviderId,
          globalSummaryModelId,
        );
      }

      // 3. 恢复兜底活跃供应商
      final aiProviderId = config['ai_provider'] as String?;
      if (aiProviderId != null && aiProviderId.isNotEmpty) {
        await _apiConfig.setActiveProviderId(aiProviderId);
      }
    } else {
      // 兼容旧版本数据导入的逻辑
      final aiProviderId = config['ai_provider'] as String?;

      // Fallbacks for older import versions
      if (aiProviderId == null || aiProviderId.isEmpty) {
        final geminiKey = config['gemini_api_key'] as String?;
        final openaiKey = config['openai_api_key'] as String?;

        if (geminiKey != null && geminiKey.isNotEmpty) {
          final existingGemini = _apiConfig.getProvider('gemini');
          if (existingGemini != null) {
            await _apiConfig.updateProvider(
              existingGemini.copyWith(
                apiKey: geminiKey,
                baseUrl:
                    config['gemini_base_url'] as String? ??
                    existingGemini.baseUrl,
                defaultDialogueModel:
                    config['ai_model'] as String? ??
                    existingGemini.defaultDialogueModel,
                defaultNamingModel:
                    config['ai_naming_model'] as String? ??
                    existingGemini.defaultNamingModel,
              ),
            );
            await _apiConfig.setActiveProviderId('gemini');
          }
        } else if (openaiKey != null && openaiKey.isNotEmpty) {
          final existingOpenAI = _apiConfig.getProvider('openai');
          if (existingOpenAI != null) {
            await _apiConfig.updateProvider(
              existingOpenAI.copyWith(
                apiKey: openaiKey,
                baseUrl:
                    config['openai_base_url'] as String? ??
                    existingOpenAI.baseUrl,
                defaultDialogueModel:
                    config['ai_model'] as String? ??
                    existingOpenAI.defaultDialogueModel,
                defaultNamingModel:
                    config['ai_naming_model'] as String? ??
                    existingOpenAI.defaultNamingModel,
              ),
            );
            await _apiConfig.setActiveProviderId('openai');
          }
        }
      } else {
        // It's a newer version where we can just look up the active provider string ID directly
        await _apiConfig.setActiveProviderId(aiProviderId);
        final existingProvider = _apiConfig.getProvider(aiProviderId);

        if (existingProvider != null) {
          final importedApiKey = config['api_key'] as String?;
          final importedBaseUrl = config['base_url'] as String?;
          final importedAiModel = config['ai_model'] as String?;
          final importedNamingModel = config['ai_naming_model'] as String?;

          await _apiConfig.updateProvider(
            existingProvider.copyWith(
              apiKey: importedApiKey ?? existingProvider.apiKey,
              baseUrl: importedBaseUrl ?? existingProvider.baseUrl,
              defaultDialogueModel:
                  importedAiModel ?? existingProvider.defaultDialogueModel,
              defaultNamingModel:
                  importedNamingModel ?? existingProvider.defaultNamingModel,
            ),
          );
        }
      }
    }

    // --- 恢复数据同步服务配置 (WebDAV, S3 等) ---
    final syncTargetIndex = config['sync_target'] as int?;
    if (syncTargetIndex != null &&
        syncTargetIndex >= 0 &&
        syncTargetIndex < 3) {
      // 这里的 3 暂时代替 SyncTarget.values.length，因为 SyncTarget 枚举没有直接被这里强依赖
      // 或者我们可以安全地使用索引，由于我们在 ImportService 开头导入了 data_sync_config_service
      await _dataSyncConfig.setSyncTarget(SyncTarget.values[syncTargetIndex]);
    }

    final webdavUrl = config['webdav_url'] as String?;
    if (webdavUrl != null) {
      await _dataSyncConfig.saveWebdavConfig(
        url: webdavUrl,
        username: config['webdav_username'] as String? ?? '',
        password: config['webdav_password'] as String? ?? '',
        path: config['webdav_path'] as String? ?? '/baishou_backup',
      );
    }

    final s3Endpoint = config['s3_endpoint'] as String?;
    if (s3Endpoint != null) {
      await _dataSyncConfig.saveS3Config(
        endpoint: s3Endpoint,
        region: config['s3_region'] as String? ?? '',
        bucket: config['s3_bucket'] as String? ?? '',
        path: config['s3_path'] as String? ?? '/baishou_backup',
        accessKey: config['s3_access_key'] as String? ?? '',
        secretKey: config['s3_secret_key'] as String? ?? '',
      );
    }

    // 恢复头像（Base64 解码后保存到本地）
    final avatarBase64 = config['avatar_base64'] as String?;
    final avatarExt = config['avatar_ext'] as String? ?? 'jpg';
    if (avatarBase64 != null && avatarBase64.isNotEmpty) {
      try {
        final avatarBytes = base64Decode(avatarBase64);
        final appDir = await getApplicationDocumentsDirectory();
        final avatarDir = Directory(path.join(appDir.path, 'avatars'));
        if (!avatarDir.existsSync()) {
          await avatarDir.create(recursive: true);
        }
        final avatarFile = File(
          path.join(
            avatarDir.path,
            'avatar_imported_${DateTime.now().millisecondsSinceEpoch}.$avatarExt',
          ),
        );
        await avatarFile.writeAsBytes(avatarBytes);
        await _profileNotifier.updateAvatar(avatarFile);
      } catch (_) {
        // 头像恢复失败不影响整体导入
      }
    }
  }
}

final importServiceProvider = Provider<ImportService>((ref) {
  return ImportService(
    diaryRepository: ref.watch(diaryRepositoryProvider),
    summaryRepository: ref.watch(summaryRepositoryProvider),
    profileNotifier: ref.watch(userProfileProvider.notifier),
    themeNotifier: ref.watch(themeProvider.notifier),
    apiConfig: ref.watch(apiConfigServiceProvider),
    dataSyncConfig: ref.watch(dataSyncConfigServiceProvider),
    journalFileService: ref.watch(journalFileServiceProvider.notifier),
    agentDatabase: ref.watch(agentDatabaseProvider),
    vaultService: ref.watch(vaultServiceProvider.notifier),
    storagePathService: ref.watch(storagePathServiceProvider),
  );
});
