import 'package:flutter/foundation.dart';
import 'package:baishou/agent/models/ai_provider_model.dart';
import 'package:baishou/agent/clients/openai_client.dart';
import 'package:baishou/agent/clients/gemini_client.dart';
import 'package:baishou/agent/clients/anthropic_client.dart';
import 'package:baishou/agent/models/chat_message.dart';
import 'package:baishou/agent/models/stream_event.dart';
import 'package:baishou/agent/models/tool_definition.dart';
import 'package:baishou/i18n/strings.g.dart';

/// AI 客户端的基础接口 (Strategy 模式)
/// 统一管理总结生成（generateContent）和 Agent 对话（chatStream）
abstract class AiClient {
  /// 生成完整的对话或内容（总结生成用）
  Future<String> generateContent({
    required String prompt,
    required String modelId,
  });

  /// 流式多轮对话 + Tool Calling（Agent 用）
  Stream<StreamEvent> chatStream({
    required List<ChatMessage> messages,
    required String modelId,
    List<ToolDefinition>? tools,
    double? temperature,
    bool enableWebSearch = false,
  });

  /// 生成文本向量嵌入
  ///
  /// 调用嵌入模型将 [input] 文本转换为浮点向量。
  /// 不支持嵌入的供应商应抛出 UnsupportedError。
  Future<List<double>> generateEmbedding({
    required String input,
    required String modelId,
  });

  /// 获取此服务商当前可用的所有模型列表
  Future<List<String>> fetchAvailableModels();

  /// 测试服务商的连接连通性
  Future<void> testConnection();
}

/// AI 客户端工厂 (Simple Factory 模式)
class AiClientFactory {
  static AiClient? _testClient;

  @visibleForTesting
  static void setTestClient(AiClient? client) {
    _testClient = client;
  }

  /// 根据提供的 [provider] 创建并挂载对应的专属 API Client
  static AiClient createClient(AiProviderModel provider) {
    if (_testClient != null) return _testClient!;

    // 本地推理引擎（Ollama / LM Studio）不一定需要 API Key
    final isLocalProvider = provider.type == ProviderType.ollama ||
        provider.type == ProviderType.lmstudio;

    if (provider.apiKey.isEmpty && !isLocalProvider) {
      throw Exception(t.ai.error_no_api_key);
    }

    switch (provider.type) {
      case ProviderType.gemini:
        return GeminiClient(provider: provider);
      case ProviderType.anthropic:
        return AnthropicClient(provider: provider);
      default:
        // OpenAI 标准协议族 (OpenAI, DeepSeek, Kimi, Ollama, Groq, SiliconFlow 等)
        return OpenAiClient(provider: provider);
    }
  }
}
