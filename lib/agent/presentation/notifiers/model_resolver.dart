/// 模型解析器 — 解析当前会话应该使用的 AI 模型
///
/// 优先级：会话级快速切换 > 伙伴绑定 > 全局默认

import 'package:baishou/core/services/api_config_service.dart';
import 'package:baishou/agent/session/assistant_repository.dart';

/// 模型解析结果
class ResolvedModel {
  final String providerId;
  final String modelId;

  const ResolvedModel({required this.providerId, required this.modelId});
}

/// 模型解析器（无状态工具类）
class ModelResolver {
  /// 解析当前会话应使用的模型
  ///
  /// 优先级：
  /// 1. 会话级快速切换（sessionProviderId / sessionModelId）
  /// 2. 伙伴绑定模型（assistantId → assistant.providerId / modelId）
  /// 3. 全局默认（apiConfig.globalDialogue*）
  static Future<ResolvedModel> resolve({
    required ApiConfigService apiConfig,
    required AssistantRepository assistantRepo,
    String? assistantId,
    String? sessionProviderId,
    String? sessionModelId,
  }) async {
    // 基础：全局默认
    String providerId = apiConfig.globalDialogueProviderId;
    String modelId = apiConfig.globalDialogueModelId;

    // 1. 伙伴绑定模型
    if (assistantId != null) {
      final assistant = await assistantRepo.get(assistantId);
      if (assistant != null &&
          assistant.providerId != null &&
          assistant.modelId != null &&
          assistant.providerId!.isNotEmpty &&
          assistant.modelId!.isNotEmpty) {
        providerId = assistant.providerId!;
        modelId = assistant.modelId!;
      }
    }

    // 2. 会话级快速切换（最高优先级）
    if (sessionProviderId != null &&
        sessionProviderId.isNotEmpty &&
        sessionModelId != null &&
        sessionModelId.isNotEmpty) {
      providerId = sessionProviderId;
      modelId = sessionModelId;
    }

    return ResolvedModel(providerId: providerId, modelId: modelId);
  }
}
