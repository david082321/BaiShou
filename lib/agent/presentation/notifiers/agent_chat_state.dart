/// Agent 聊天状态模型
///
/// 包含聊天页面的 UI 状态（消息、流式输出、工具执行、token 用量等）

import 'package:baishou/agent/models/chat_message.dart';

/// 工具执行记录
class ToolExecution {
  final String name;
  final int durationMs;
  const ToolExecution({required this.name, required this.durationMs});
}

/// 聊天页面 UI 状态
class AgentChatState {
  final String? sessionId;
  final List<ChatMessage> messages;
  final String streamingText;
  final bool isLoading;
  final String? activeToolName;
  final String? error;

  /// 当前轮已完成的工具执行记录（含耗时）
  final List<ToolExecution> completedTools;

  /// 当前会话累计费用（微美元，1 USD = 1,000,000 micros）
  final int totalCostMicros;

  /// 当前会话累计输入 token
  final int totalInputTokens;

  /// 当前会话累计输出 token
  final int totalOutputTokens;

  /// 最近一次 API 调用的上下文 token 数（即当前对话上下文大小）
  final int lastInputTokens;

  /// 当前选择的伙伴 ID（新对话创建时使用）
  final String? currentAssistantId;

  /// 当前会话使用的供应商 ID（快速切换模型时使用）
  final String? currentProviderId;

  /// 当前会话使用的模型 ID（快速切换模型时使用）
  final String? currentModelId;

  /// 是否还有更多历史消息可加载
  final bool hasMore;

  /// 是否正在加载更多历史记录
  final bool isLoadingMore;

  const AgentChatState({
    this.sessionId,
    this.messages = const [],
    this.streamingText = '',
    this.isLoading = false,
    this.activeToolName,
    this.error,
    this.completedTools = const [],
    this.totalCostMicros = 0,
    this.totalInputTokens = 0,
    this.totalOutputTokens = 0,
    this.lastInputTokens = 0,
    this.currentAssistantId,
    this.currentProviderId,
    this.currentModelId,
    this.hasMore = false,
    this.isLoadingMore = false,
  });

  AgentChatState copyWith({
    String? sessionId,
    List<ChatMessage>? messages,
    String? streamingText,
    bool? isLoading,
    String? Function()? activeToolName,
    String? Function()? error,
    List<ToolExecution>? completedTools,
    int? totalCostMicros,
    int? totalInputTokens,
    int? totalOutputTokens,
    int? lastInputTokens,
    String? Function()? currentAssistantId,
    String? Function()? currentProviderId,
    String? Function()? currentModelId,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return AgentChatState(
      sessionId: sessionId ?? this.sessionId,
      messages: messages ?? this.messages,
      streamingText: streamingText ?? this.streamingText,
      isLoading: isLoading ?? this.isLoading,
      activeToolName: activeToolName != null
          ? activeToolName()
          : this.activeToolName,
      error: error != null ? error() : this.error,
      completedTools: completedTools ?? this.completedTools,
      totalCostMicros: totalCostMicros ?? this.totalCostMicros,
      totalInputTokens: totalInputTokens ?? this.totalInputTokens,
      totalOutputTokens: totalOutputTokens ?? this.totalOutputTokens,
      lastInputTokens: lastInputTokens ?? this.lastInputTokens,
      currentAssistantId: currentAssistantId != null
          ? currentAssistantId()
          : this.currentAssistantId,
      currentProviderId: currentProviderId != null
          ? currentProviderId()
          : this.currentProviderId,
      currentModelId: currentModelId != null
          ? currentModelId()
          : this.currentModelId,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }
}
