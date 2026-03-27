import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/core/database/app_database.dart' hide Diary, Summary;
import 'package:baishou/core/database/tables/summaries.dart';
import 'package:baishou/core/services/data_refresh_notifier.dart';
import 'package:baishou/core/storage/storage_path_provider.dart';
import 'package:baishou/core/storage/vault_service.dart';
import 'package:baishou/features/diary/data/vault_index_notifier.dart';
import 'package:baishou/features/diary/domain/entities/diary.dart';
import 'package:baishou/features/index/data/shadow_index_sync_service.dart';
import 'package:baishou/features/summary/domain/services/summary_sync_service.dart';
import 'package:baishou/features/settings/domain/services/import_models.dart';
import 'package:baishou/features/settings/domain/services/import_service.dart';
import 'package:baishou/features/storage/domain/services/journal_file_service.dart';
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:flutter/foundation.dart' hide Summary;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'legacy_archive_import_service.g.dart';

/// 处理白守旧版格式（v1/v2 JSON结构）备份包的导入
@Riverpod(keepAlive: true)
class LegacyArchiveImportService extends _$LegacyArchiveImportService {
  @override
  void build() {}

  /// 旧版 JSON 格式备份包的兼容导入
  ///
  /// 旧版格式结构：
  /// - manifest.json (schema_version, export_date 等元数据)
  /// - data/diaries.json, data/summaries.json
  /// - data/ai_assistants.json, data/agent_sessions.json, data/agent_messages.json, data/agent_parts.json
  /// - data/agent_embeddings.json
  /// - config/user_profile.json
  /// - attachments/
  Future<ImportResult> importLegacyZip(Archive archive, String? snapshotPath) async {
    final vaultIndex = ref.read(vaultIndexProvider.notifier);
    final shadowIndexSyncService = ref.read(shadowIndexSyncServiceProvider.notifier);
    final summarySyncService = ref.read(summarySyncServiceProvider.notifier);

    try {
      // --- 辅助函数：从 Archive 中读取并解析 JSON ---
      dynamic parseJsonFromArchive(String relativePath) {
        final file = archive.findFile(relativePath);
        if (file == null || !file.isFile) return null;
        try {
          return jsonDecode(utf8.decode(file.content));
        } catch (_) {
          return null;
        }
      }

      // 1. 读取 manifest 获取 schema_version
      final manifest = parseJsonFromArchive('manifest.json') as Map<String, dynamic>?;
      final schemaVersion = manifest?['schema_version'] as int? ?? 0;
      debugPrint('LegacyArchiveImportService: Legacy import schema_version=$schemaVersion');

      // 2. 读取各数据文件
      final diariesJson = parseJsonFromArchive('data/diaries.json') as List<dynamic>?;
      final summariesJson = parseJsonFromArchive('data/summaries.json') as List<dynamic>?;
      final config = parseJsonFromArchive('config/user_profile.json') as Map<String, dynamic>?;
      final aiAssistants = parseJsonFromArchive('data/ai_assistants.json') as List<dynamic>?;
      final agentSessions = parseJsonFromArchive('data/agent_sessions.json') as List<dynamic>?;
      final agentMessages = parseJsonFromArchive('data/agent_messages.json') as List<dynamic>?;
      final agentParts = parseJsonFromArchive('data/agent_parts.json') as List<dynamic>?;
      final agentEmbeddings = parseJsonFromArchive('data/agent_embeddings.json') as List<dynamic>?;

      // 3. 清空现有数据（覆盖模式）
      final agentDb = ref.read(agentDatabaseProvider);
      await agentDb.clearAllAgentData();

      // 4. 导入日记 → 写入物理 Journal 文件（由 fullScanVault 索引到数据库）
      int diariesImported = 0;
      if (diariesJson != null && diariesJson.isNotEmpty) {
        diariesImported = await _importLegacyDiaries(diariesJson, schemaVersion);
      }

      // 5. 导入总结 → 直接批量插入数据库
      int summariesImported = 0;
      if (summariesJson != null && summariesJson.isNotEmpty) {
        summariesImported = await _importLegacySummaries(summariesJson);
      }

      // 6. 导入 Agent 附属数据（AI 助手、会话、消息、Part、Embedding）
      await _importLegacyAgentData(
        agentDb: agentDb,
        aiAssistants: aiAssistants,
        agentSessions: agentSessions,
        agentMessages: agentMessages,
        agentParts: agentParts,
        agentEmbeddings: agentEmbeddings,
      );

      // 7. 复制物理附件到当前 Vault
      await _importLegacyAttachments(archive);

      // 8. 恢复设备级偏好配置
      if (config != null) {
        try {
          // 调用 ImportService 处理旧版的 user_profile.json
          // 旧版的头像存储在 config['avatar_base64'] 中，ImportService 会自动处理
          final importService = ref.read(importServiceProvider);
          await importService.restoreConfig(config);
        } catch (e) {
          debugPrint('LegacyArchiveImportService: Failed to restore device preferences: $e');
        }
      }

      // 9. 重新对齐并点火
      ref.invalidate(appDatabaseProvider);
      ref.invalidate(agentDatabaseProvider);
      summarySyncService.setSyncEnabled(true);
      shadowIndexSyncService.setSyncEnabled(true);
      await summarySyncService.fullScanArchives();
      await shadowIndexSyncService.fullScanVault(skipRag: true);
      await vaultIndex.forceReload();
      ref.read(dataRefreshProvider.notifier).refresh();

      return ImportResult(
        fileCount: diariesImported + summariesImported,
        profileRestored: config != null,
        snapshotPath: snapshotPath,
      );
    } catch (e) {
      debugPrint('LegacyArchiveImportService: Legacy import error: $e');
      try {
        summarySyncService.setSyncEnabled(true);
        shadowIndexSyncService.setSyncEnabled(true);
        await shadowIndexSyncService.fullScanVault(skipRag: true);
        await vaultIndex.forceReload();
      } catch (_) {}
      rethrow;
    }
  }

  /// 旧版日记导入：解析 JSON → 按天分组合并 → 写入 Journal 物理文件
  Future<int> _importLegacyDiaries(List<dynamic> diariesJson, int schemaVersion) async {
    final journalFileService = ref.read(journalFileServiceProvider.notifier);
    final DateFormat dayFormatter = DateFormat('yyyy-MM-dd');
    final DateFormat timeFormatter = DateFormat('HH:mm:ss');

    final parsedDiaries = <Diary>[];
    for (final item in diariesJson) {
      final map = item as Map<String, dynamic>;
      final date = DateTime.parse(map['date'] as String);
      final rawId = map['id'];
      final int parsedId = rawId is int ? rawId : (int.tryParse(rawId?.toString() ?? '') ?? 0);

      parsedDiaries.add(Diary(
        id: parsedId,
        date: date,
        content: map['content'] as String? ?? '',
        tags: (map['tags'] as List<dynamic>?)?.cast<String>() ?? [],
        createdAt: map['created_at'] != null ? DateTime.parse(map['created_at'] as String) : DateTime.now(),
        updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at'] as String) : DateTime.now(),
        weather: map['weather'] as String?,
        mood: map['mood'] as String?,
        location: map['location'] as String?,
        locationDetail: map['location_detail'] as String?,
        isFavorite: map['is_favorite'] as bool? ?? false,
        mediaPaths: (map['media_paths'] as List<dynamic>?)?.cast<String>() ?? [],
      ));
    }

    // 按天分组并合并
    final Map<String, List<Diary>> groupedDiaries = {};
    for (final diary in parsedDiaries) {
      final dayKey = dayFormatter.format(diary.date);
      groupedDiaries.putIfAbsent(dayKey, () => []).add(diary);
    }

    for (final entry in groupedDiaries.entries) {
      final list = entry.value;
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));

      final buffer = StringBuffer();
      final mergedTags = <String>{};
      final mergedMediaPaths = <String>{};

      for (int i = 0; i < list.length; i++) {
        final d = list[i];
        if (schemaVersion < 1) {
          buffer.writeln('##### ${timeFormatter.format(d.createdAt)}\n');
        }
        buffer.writeln(d.content.trim());
        if (i < list.length - 1) {
          buffer.writeln(schemaVersion < 1 ? '\n---\n' : '');
        }
        mergedTags.addAll(d.tags);
        mergedMediaPaths.addAll(d.mediaPaths);
      }

      final latestDiary = list.last;
      final superDiary = latestDiary.copyWith(
        content: buffer.toString().trim(),
        tags: mergedTags.toList(),
        mediaPaths: mergedMediaPaths.toList(),
      );
      await journalFileService.writeJournal(superDiary);
    }

    debugPrint('LegacyArchiveImportService: Legacy imported ${parsedDiaries.length} diaries into ${groupedDiaries.length} daily files.');
    return parsedDiaries.length;
  }

  /// 旧版总结导入：解析 JSON → 批量插入数据库
  Future<int> _importLegacySummaries(List<dynamic> summariesJson) async {
    final appDb = ref.read(appDatabaseProvider);
    
    for (final item in summariesJson) {
      final map = item as Map<String, dynamic>;
      final typeStr = map['type'] as String? ?? 'weekly';
      final type = SummaryType.values.firstWhere(
        (t) => t.name == typeStr,
        orElse: () => SummaryType.weekly,
      );
      final startDate = DateTime.parse(map['start_date'] as String);
      final endDate = DateTime.parse(map['end_date'] as String);
      final content = map['content'] as String? ?? '';
      final sourceIds = (map['source_ids'] as List<dynamic>?)?.cast<String>() ?? [];
      
      await appDb.into(appDb.summaries).insertOnConflictUpdate(
        SummariesCompanion.insert(
          type: type,
          startDate: startDate,
          endDate: endDate,
          content: content,
          sourceIds: Value(sourceIds.join(',')),
          generatedAt: Value(DateTime.now()),
        ),
      );
    }

    debugPrint('LegacyArchiveImportService: Legacy imported ${summariesJson.length} summaries.');
    return summariesJson.length;
  }

  /// 旧版 Agent 数据导入
  Future<void> _importLegacyAgentData({
    required AgentDatabase agentDb,
    List<dynamic>? aiAssistants,
    List<dynamic>? agentSessions,
    List<dynamic>? agentMessages,
    List<dynamic>? agentParts,
    List<dynamic>? agentEmbeddings,
  }) async {
    await agentDb.batch((batch) {
      if (aiAssistants != null) {
        for (final e in aiAssistants) {
          batch.insert(
            agentDb.agentAssistants,
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
              compressTokenThreshold: Value(e['compress_token_threshold'] as int? ?? 60000),
              compressKeepTurns: Value(e['compress_keep_turns'] as int? ?? 3),
              sortOrder: Value(e['sort_order'] as int? ?? 0),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      }
      if (agentSessions != null) {
        for (final e in agentSessions) {
          batch.insert(
            agentDb.agentSessions,
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
      if (agentMessages != null) {
        for (final e in agentMessages) {
          batch.insert(
            agentDb.agentMessages,
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
      if (agentParts != null) {
        for (final e in agentParts) {
          batch.insert(
            agentDb.agentParts,
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

    // RAG 向量数据需要 Base64 反序列化
    if (agentEmbeddings != null) {
      final mapped = agentEmbeddings.map((e) {
        final Map<String, dynamic> row = Map<String, dynamic>.from(e as Map);
        if (row['embedding'] is String) {
          row['embedding'] = base64Decode(row['embedding'] as String);
        }
        return row;
      }).toList();
      await agentDb.importEmbeddingsRaw(mapped);
    }

    await agentDb.rebuildFtsIndex();
    debugPrint('LegacyArchiveImportService: Legacy Agent data imported.');
  }

  /// 旧版附件导入：从 archive 的 attachments/ 目录复制到当前 Vault 的 attachments/
  Future<void> _importLegacyAttachments(Archive archive) async {
    final pathService = ref.read(storagePathServiceProvider);
    final currentVault = ref.read(vaultServiceProvider).value;
    if (currentVault == null) return;

    final destVaultDir = await pathService.getVaultDirectory(currentVault.name);
    final destAttachDir = Directory(p.join(destVaultDir.path, 'attachments'));

    bool hasAttachments = false;
    for (final file in archive) {
      if (file.isFile && file.name.startsWith('attachments/')) {
        hasAttachments = true;
        final relativePath = file.name.substring('attachments/'.length);
        if (relativePath.isEmpty) continue;
        final targetFile = File(p.join(destAttachDir.path, relativePath));
        if (!targetFile.parent.existsSync()) {
          targetFile.parent.createSync(recursive: true);
        }
        await targetFile.writeAsBytes(file.content);
      }
    }
    if (hasAttachments) {
      debugPrint('LegacyArchiveImportService: Legacy attachments copied.');
    }
  }
}
