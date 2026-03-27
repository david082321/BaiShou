import 'dart:convert';
import 'dart:io';


import 'package:baishou/core/services/api_config_service.dart';
import 'package:baishou/core/theme/theme_service.dart';
import 'package:baishou/agent/models/ai_provider_model.dart';
import 'package:baishou/features/settings/domain/services/data_sync_config_service.dart';
import 'package:baishou/features/settings/domain/services/user_profile_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
export 'package:baishou/features/settings/domain/services/import_models.dart';

/// 设备级偏好配置恢复服务
/// 负责将 ZIP 中携带的 SharedPreferences 配置（API Key、主题色、同步设定等）恢复到当前设备。
/// 由 DataArchiveManager 在物理全量导入完成后调用。
class ImportService {
  final UserProfileNotifier _profileNotifier;
  final ThemeNotifier _themeNotifier;
  final ApiConfigService _apiConfig;
  final DataSyncConfigService _dataSyncConfig;

  ImportService({
    required UserProfileNotifier profileNotifier,
    required ThemeNotifier themeNotifier,
    required ApiConfigService apiConfig,
    required DataSyncConfigService dataSyncConfig,
  }) : _profileNotifier = profileNotifier,
       _themeNotifier = themeNotifier,
       _apiConfig = apiConfig,
       _dataSyncConfig = dataSyncConfig;

  /// 恢复用户配置（主题、API Key 等）
  /// 注意：此方法会触发主题变更，必须在所有 Dialog 关闭后再调用
  Future<void> restoreConfig(Map<String, dynamic> config) async {
    // 恢复昵称
    final nickname = config['nickname'] as String?;
    if (nickname != null && nickname.isNotEmpty) {
      await _profileNotifier.updateNickname(nickname);
    }

    // 恢复身份卡事实
    final identityFacts = config['identity_facts'];
    if (identityFacts is Map) {
      final facts = identityFacts.map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      );
      await _profileNotifier.updateAllFacts(facts);
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

    // --- 恢复全局 Embedding 配置 ---
    final globalEmbeddingProviderId =
        config['global_embedding_provider_id'] as String?;
    final globalEmbeddingModelId =
        config['global_embedding_model_id'] as String?;
    if (globalEmbeddingProviderId != null && globalEmbeddingModelId != null) {
      await _apiConfig.setGlobalEmbeddingModel(
        globalEmbeddingProviderId,
        globalEmbeddingModelId,
      );
      final globalEmbeddingDimension =
          config['global_embedding_dimension'] as int?;
      if (globalEmbeddingDimension != null) {
        await _apiConfig.setGlobalEmbeddingDimension(globalEmbeddingDimension);
      }
    }

    // --- 恢复 AI 伙伴环境偏好 ---
    if (config['monthly_summary_source'] != null) {
      await _apiConfig.setMonthlySummarySource(
        config['monthly_summary_source'] as String,
      );
    }
    if (config['agent_context_window_size'] != null) {
      await _apiConfig.setAgentContextWindowSize(
        config['agent_context_window_size'] as int,
      );
    }
    if (config['companion_compress_tokens'] != null) {
      await _apiConfig.setCompanionCompressTokens(
        config['companion_compress_tokens'] as int,
      );
    }
    if (config['companion_truncate_tokens'] != null) {
      await _apiConfig.setCompanionTruncateTokens(
        config['companion_truncate_tokens'] as int,
      );
    }
    if (config['agent_persona'] != null) {
      await _apiConfig.setAgentPersona(config['agent_persona'] as String);
    }
    if (config['agent_guidelines'] != null) {
      await _apiConfig.setAgentGuidelines(config['agent_guidelines'] as String);
    }

    // --- 恢复工具及 RAG 体系配置 ---
    if (config['disabled_tool_ids'] != null) {
      await _apiConfig.setDisabledToolIds(
        (config['disabled_tool_ids'] as List<dynamic>).cast<String>(),
      );
    }
    if (config['rag_global_enabled'] != null) {
      await _apiConfig.setRagEnabled(config['rag_global_enabled'] as bool);
    }
    if (config['rag_top_k'] != null) {
      _apiConfig.setRagTopK(config['rag_top_k'] as int);
    }
    if (config['rag_similarity_threshold'] != null) {
      _apiConfig.setRagSimilarityThreshold(
        (config['rag_similarity_threshold'] as num).toDouble(),
      );
    }
    if (config['summary_prompt_instructions'] != null &&
        (config['summary_prompt_instructions'] as String).isNotEmpty) {
      await _apiConfig.setSummaryInstructions(
        'legacy',
        config['summary_prompt_instructions'] as String,
      );
    }
    if (config['all_summary_instructions'] != null) {
      await _apiConfig.importAllSummaryInstructions(
        Map<String, String>.from(config['all_summary_instructions'] as Map),
      );
    }
    if (config['all_tool_configs'] != null) {
      await _apiConfig.importAllToolConfigs(
        Map<String, dynamic>.from(config['all_tool_configs'] as Map),
      );
    }

    // --- 恢复 MCP Server 配置 ---
    if (config['mcp_server_enabled'] != null) {
      await _apiConfig.setMcpEnabled(config['mcp_server_enabled'] as bool);
    }
    if (config['mcp_server_port'] != null) {
      await _apiConfig.setMcpPort(config['mcp_server_port'] as int);
    }

    // --- 恢复实时网络搜索配置 ---
    if (config['web_search_engine'] != null) {
      await _apiConfig.setWebSearchEngine(
        config['web_search_engine'] as String,
      );
    }
    if (config['web_search_max_results'] != null) {
      await _apiConfig.setWebSearchMaxResults(
        config['web_search_max_results'] as int,
      );
    }
    if (config['web_search_rag_enabled'] != null) {
      await _apiConfig.setWebSearchRagEnabled(
        config['web_search_rag_enabled'] as bool,
      );
    }
    if (config['tavily_api_key'] != null) {
      await _apiConfig.setTavilyApiKey(config['tavily_api_key'] as String);
    }
    if (config['web_search_rag_max_chunks'] != null) {
      await _apiConfig.setWebSearchRagMaxChunks(
        config['web_search_rag_max_chunks'] as int,
      );
    }
    if (config['web_search_rag_chunks_per_source'] != null) {
      await _apiConfig.setWebSearchRagChunksPerSource(
        config['web_search_rag_chunks_per_source'] as int,
      );
    }
    if (config['web_search_plain_snippet_length'] != null) {
      await _apiConfig.setWebSearchPlainSnippetLength(
        config['web_search_plain_snippet_length'] as int,
      );
    }
    final syncTargetIndex = config['sync_target'] as int?;
    if (syncTargetIndex != null &&
        syncTargetIndex >= 0 &&
        syncTargetIndex < 3) {
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

    // 恢复头像（从 Base64 格式 — 兼容旧版备份包）
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
    profileNotifier: ref.watch(userProfileProvider.notifier),
    themeNotifier: ref.watch(themeProvider.notifier),
    apiConfig: ref.watch(apiConfigServiceProvider),
    dataSyncConfig: ref.watch(dataSyncConfigServiceProvider),
  );
});
