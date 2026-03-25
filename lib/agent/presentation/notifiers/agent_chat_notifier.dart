/// Agent 聊天状态管理
///
/// 管理当前对话的消息列表、流式输出、工具执行状态
///
/// SOLID 拆分：
/// - State 模型 → agent_chat_state.dart
/// - 模型解析 → model_resolver.dart
/// - 副作用服务 → chat_side_effects.dart

import 'dart:async';
import 'package:baishou/i18n/strings.g.dart';
import 'package:baishou/agent/clients/ai_client.dart';
import 'package:baishou/agent/models/ai_provider_model.dart';
import 'package:baishou/agent/models/chat_message.dart';
import 'package:baishou/agent/models/message_attachment.dart';
import 'package:baishou/agent/runner/agent_runner.dart';
import 'package:baishou/agent/session/compression_service.dart';
import 'package:baishou/agent/session/context_window.dart';
import 'package:baishou/agent/session/session_manager.dart';
import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:baishou/agent/tools/tool_repository.dart';
import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/agent/session/assistant_repository.dart';
import 'package:baishou/agent/rag/embedding_service.dart';
import 'package:baishou/agent/prompts/system_prompt_builder.dart';
import 'package:baishou/agent/presentation/notifiers/agent_chat_state.dart';
import 'package:baishou/agent/presentation/notifiers/model_resolver.dart';
import 'package:baishou/agent/presentation/notifiers/chat_side_effects.dart';
import 'package:baishou/core/services/api_config_service.dart';
import 'package:baishou/core/storage/storage_path_provider.dart';
import 'package:baishou/core/storage/vault_service.dart';
import 'package:baishou/features/settings/domain/services/user_profile_service.dart';
import 'package:baishou/agent/rag/memory_deduplication_service.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

// 向后兼容：重新导出 AgentChatState 和 ToolExecution
export 'package:baishou/agent/presentation/notifiers/agent_chat_state.dart';

part 'agent_chat_notifier.g.dart';

@riverpod
class AgentChatNotifier extends _$AgentChatNotifier {
  /// 当前运行 ID（用于中止当前会话的生成）
  int _currentRunId = 0;

  /// 每个会话的状态缓存（支持切换后保持生成）
  final Map<String, AgentChatState> _sessionStateCache = {};

  @override
  AgentChatState build() {
    _initDefaultAssistant();
    return const AgentChatState();
  }

  // ========================================================================
  // 会话管理
  // ========================================================================

  /// 加载已有会话
  Future<void> loadSession(String sessionId) async {
    if (state.sessionId != null && state.sessionId!.isNotEmpty) {
      _sessionStateCache[state.sessionId!] = state;
    }

    final cached = _sessionStateCache[sessionId];
    if (cached != null) {
      if (cached.isLoading) {
        state = cached;
        return;
      }
      _sessionStateCache.remove(sessionId);
    }

    final manager = ref.read(sessionManagerProvider);
    final messages = await manager.getMessages(
      sessionId,
      limit: 20,
      descending: true,
    );
    final session = await manager.getSession(sessionId);
    final lastInput = await manager.getLastInputTokens(sessionId);
    state = state.copyWith(
      sessionId: sessionId,
      messages: messages,
      isLoading: false,
      streamingText: '',
      activeToolName: () => null,
      error: () => null,
      completedTools: const [],
      totalCostMicros: session?.totalCostMicros ?? 0,
      totalInputTokens: session?.totalInputTokens ?? 0,
      totalOutputTokens: session?.totalOutputTokens ?? 0,
      lastInputTokens: lastInput,
      currentAssistantId: () => session?.assistantId,
      currentProviderId: () => session?.providerId,
      currentModelId: () => session?.modelId,
      hasMore: messages.length == 20,
      isLoadingMore: false,
    );
  }

  /// 加载更多历史记录
  Future<void> loadMore() async {
    final sessionId = state.sessionId;
    if (sessionId == null || state.isLoadingMore || !state.hasMore) return;

    state = state.copyWith(isLoadingMore: true);
    final manager = ref.read(sessionManagerProvider);
    final moreMessages = await manager.getMessages(
      sessionId,
      limit: 20,
      offset: state.messages.length,
      descending: true,
    );

    state = state.copyWith(
      messages: [...state.messages, ...moreMessages],
      hasMore: moreMessages.length == 20,
      isLoadingMore: false,
    );
  }

  /// 清空当前对话
  void clearChat() {
    _currentRunId++;
    if (state.sessionId != null) {
      _sessionStateCache.remove(state.sessionId);
    }
    state = const AgentChatState();
  }

  /// 停止当前正在进行的生成
  void stopGeneration() {
    if (!state.isLoading) return;
    _currentRunId++;
    final sessionId = state.sessionId;
    if (sessionId != null) {
      final currentState = _getSessionState(sessionId);
      _updateSessionCache(
        sessionId,
        currentState.copyWith(
          isLoading: false,
          streamingText: '',
          activeToolName: () => null,
          completedTools: const [],
        ),
      );
    } else {
      state = state.copyWith(
        isLoading: false,
        streamingText: '',
        activeToolName: () => null,
        completedTools: const [],
      );
    }
  }

  // ========================================================================
  // 伙伴 & 模型设置
  // ========================================================================

  void setAssistant(String? id) {
    state = state.copyWith(currentAssistantId: () => id);
  }

  void setCurrentAssistantId(String id) => setAssistant(id);

  void setCurrentModel({required String providerId, required String modelId}) {
    state = state.copyWith(
      currentProviderId: () => providerId,
      currentModelId: () => modelId,
    );
  }

  // ========================================================================
  // 消息发送
  // ========================================================================

  /// 发送消息并运行 Agent
  Future<void> sendMessage({
    required String text,
    String? persona,
    String? guidelines,
    List<MessageAttachment>? attachments,
  }) async {
    if (text.trim().isEmpty && (attachments == null || attachments.isEmpty)) return;
    if (state.isLoading) return;

    _currentRunId++;
    final runId = _currentRunId;
    state = state.copyWith(error: () => null, isLoading: true);

    final manager = ref.read(sessionManagerProvider);
    final apiConfig = ref.read(apiConfigServiceProvider);

    final vaultInfo = await ref.read(vaultServiceProvider.future);
    final vaultName = vaultInfo?.name ?? 'Personal';
    final storageService = ref.read(storagePathServiceProvider);
    final vaultDir = await storageService.getVaultDirectory(vaultName);
    final vaultPath = vaultDir.path;

    // 模型解析（使用 ModelResolver 消除重复）
    final resolved = await ModelResolver.resolve(
      apiConfig: apiConfig,
      assistantRepo: ref.read(assistantRepositoryProvider),
      assistantId: state.currentAssistantId,
      sessionProviderId: state.currentProviderId,
      sessionModelId: state.currentModelId,
    );

    final provider = apiConfig.getProvider(resolved.providerId);
    if (provider == null || resolved.modelId.isEmpty) {
      state = state.copyWith(
        error: () => t.agent.chat.err_no_model,
        isLoading: false,
      );
      return;
    }

    // 创建新会话
    String sessionId = state.sessionId ?? '';
    bool isNewSession = false;

    if (sessionId.isEmpty) {
      isNewSession = true;
      sessionId = await manager.createSession(
        vaultName: vaultName,
        providerId: resolved.providerId,
        modelId: resolved.modelId,
        assistantId: state.currentAssistantId,
      );
      state = state.copyWith(sessionId: sessionId);
    }

    // 复制附件到私有目录
    List<MessageAttachment>? persistedAttachments;
    if (attachments != null && attachments.isNotEmpty) {
      persistedAttachments = await AttachmentService.copyToPrivate(
        attachments: attachments,
        vaultPath: vaultPath,
        sessionId: sessionId,
      );
    }

    // 添加用户消息到 UI
    final userMsg = ChatMessage.user(text, attachments: persistedAttachments);
    final updatedMessages = [userMsg, ...state.messages];
    state = state.copyWith(messages: updatedMessages);
    _sessionStateCache[sessionId] = state;

    await manager.addMessage(sessionId, userMsg);

    await _runAgentLoop(
      sessionId: sessionId,
      runId: runId,
      askId: userMsg.id,
      vaultName: vaultName,
      vaultPath: vaultPath,
      providerId: resolved.providerId,
      modelId: resolved.modelId,
      provider: provider,
      isNewSession: isNewSession,
      userMessageContent: userMsg.content ?? '',
      persona: persona,
      guidelines: guidelines,
    );
  }

  /// 重发用户消息
  Future<void> resendUserMessage(String userMessageId) async {
    final sessionId = state.sessionId;
    if (sessionId == null || state.isLoading) return;

    final manager = ref.read(sessionManagerProvider);
    final apiConfig = ref.read(apiConfigServiceProvider);

    // 删除该用户消息之后的所有消息
    final userMsgIndex = state.messages.indexWhere(
      (m) => m.id == userMessageId,
    );
    if (userMsgIndex == -1) return;

    final msgsAfter = state.messages.sublist(0, userMsgIndex);
    if (msgsAfter.isNotEmpty) {
      final idsToDelete = msgsAfter.map((m) => m.id).toList();
      await manager.deleteMessagesByIds(idsToDelete);
      state = state.copyWith(
        messages: state.messages.sublist(userMsgIndex),
      );
      _sessionStateCache[sessionId] = state;
    }

    // 模型解析
    final resolved = await ModelResolver.resolve(
      apiConfig: apiConfig,
      assistantRepo: ref.read(assistantRepositoryProvider),
      assistantId: state.currentAssistantId,
      sessionProviderId: state.currentProviderId,
      sessionModelId: state.currentModelId,
    );

    final provider = apiConfig.getProvider(resolved.providerId);
    if (provider == null || resolved.modelId.isEmpty) {
      state = state.copyWith(error: () => t.agent.chat.err_no_model);
      return;
    }

    final vaultInfo = await ref.read(vaultServiceProvider.future);
    final vaultName = vaultInfo?.name ?? 'Personal';
    final storageService = ref.read(storagePathServiceProvider);
    final vaultDir = await storageService.getVaultDirectory(vaultName);

    _currentRunId++;
    final runId = _currentRunId;
    state = state.copyWith(error: () => null, isLoading: true);
    _sessionStateCache[sessionId] = state;

    final userMsg = state.messages.firstWhere(
      (m) => m.id == userMessageId,
      orElse: () => ChatMessage.user(''),
    );

    await _runAgentLoop(
      sessionId: sessionId,
      runId: runId,
      askId: userMessageId,
      vaultName: vaultName,
      vaultPath: vaultDir.path,
      providerId: resolved.providerId,
      modelId: resolved.modelId,
      provider: provider,
      isNewSession: false,
      userMessageContent: userMsg.content ?? '',
    );
  }

  /// 重新生成 AI 回复
  Future<void> regenerateResponse(String assistantMessageId) async {
    final msg = state.messages.firstWhere(
      (m) => m.id == assistantMessageId,
      orElse: () => ChatMessage.assistant(),
    );
    if (msg.askId == null) return;
    await resendUserMessage(msg.askId!);
  }

  /// 编辑用户消息并重新发送
  Future<void> editAndResend(String messageId, String newText) async {
    if (newText.trim().isEmpty) return;
    final sessionId = state.sessionId;
    if (sessionId == null || state.isLoading) return;

    final manager = ref.read(sessionManagerProvider);
    await manager.deleteMessagesFromAndAfter(sessionId, messageId);

    final msgIndex = state.messages.indexWhere((m) => m.id == messageId);
    if (msgIndex != -1) {
      final truncated = state.messages.sublist(0, msgIndex);
      state = state.copyWith(messages: truncated, error: () => null);
      _sessionStateCache[sessionId] = state;
    }

    await sendMessage(text: newText);
  }

  // ========================================================================
  // Agent 运行循环
  // ========================================================================

  Future<void> _runAgentLoop({
    required String sessionId,
    required int runId,
    required String askId,
    required String vaultName,
    required String vaultPath,
    required String providerId,
    required String modelId,
    required dynamic provider,
    required bool isNewSession,
    required String userMessageContent,
    String? persona,
    String? guidelines,
  }) async {
    final manager = ref.read(sessionManagerProvider);
    final apiConfig = ref.read(apiConfigServiceProvider);
    final tools = _buildToolRegistry();

    // 解析 System Prompt
    String? resolvedPersona;
    int? assistantContextWindow;
    bool hasAssistant = false;

    final db = ref.read(agentDatabaseProvider);
    final assistantRepo = ref.read(assistantRepositoryProvider);
    final session = await (db.select(
      db.agentSessions,
    )..where((t) => t.id.equals(sessionId))).getSingleOrNull();
    if (session?.assistantId != null) {
      final assistant = await assistantRepo.get(session!.assistantId!);
      if (assistant != null) {
        hasAssistant = true;
        resolvedPersona = assistant.systemPrompt.isNotEmpty
            ? assistant.systemPrompt
            : null;
        assistantContextWindow = assistant.contextWindow;
      }
    }

    if (!hasAssistant) {
      resolvedPersona = persona ?? apiConfig.agentPersona;
    }

    // 读取用户身份卡
    final userProfile = ref.read(userProfileProvider);

    final systemPrompt = SystemPromptBuilder.build(
      persona: resolvedPersona,
      guidelines: hasAssistant
          ? null
          : (guidelines ?? apiConfig.agentGuidelines),
      userProfileBlock: userProfile.toMarkdownBlock(),
      vaultName: vaultName,
      tools: tools,
    );

    // 创建 Agent Runner
    final client = AiClientFactory.createClient(provider);
    final runner = AgentRunner(
      client: client,
      tools: tools,
      config: AgentConfig(
        modelId: modelId,
        systemPrompt: systemPrompt,
        enableWebSearch: provider.webSearchMode == WebSearchMode.builtin,
      ),
    );

    // 滑动窗口上下文
    final windowSize =
        assistantContextWindow ?? apiConfig.agentContextWindowSize;
    final dbMessages = await manager.getMessages(
      sessionId,
      limit: windowSize,
      descending: true,
    );

    final compressor = ref.read(compressionServiceProvider);
    final snapshot = await compressor.getLatestSnapshot(sessionId);
    String? compressionSummary;

    List<ChatMessage> messagesForWindow = dbMessages
        .where((m) => m.role != MessageRole.system)
        .toList()
        .reversed
        .toList();

    if (snapshot != null) {
      final cutoffIndex = messagesForWindow.indexWhere(
        (m) => m.id == snapshot.coveredUpToMessageId,
      );
      if (cutoffIndex >= 0 && cutoffIndex < messagesForWindow.length - 1) {
        messagesForWindow = messagesForWindow.sublist(cutoffIndex + 1);
        compressionSummary = snapshot.summaryText;
      }
    }

    final contextMessages = ContextWindow.fromMemory(
      messages: messagesForWindow,
      config: ContextWindowConfig(recentCount: windowSize),
      compressionSummary: compressionSummary,
    );

    // 构建工具上下文（合并全局 RAG 参数和 per-tool 用户配置）
    final toolUserConfig = <String, dynamic>{
      'rag_top_k': apiConfig.ragTopK,
      'rag_similarity_threshold': apiConfig.ragSimilarityThreshold,
    };
    // 合并所有已启用工具的用户配置（例如 web_search 的 engine、max_results）
    for (final tool in tools.ids) {
      final perToolConfig = apiConfig.getToolConfig(tool);
      if (perToolConfig.isNotEmpty) {
        toolUserConfig.addAll(perToolConfig);
      }
    }

    try {
      final assistantMessages = <ChatMessage>[];

      await for (final event in runner.run(
        messages: contextMessages,
        context: ToolContext(
          sessionId: sessionId,
          vaultPath: vaultPath,
          userConfig: toolUserConfig,
          embeddingService: EmbeddingService(
            ref.read(apiConfigServiceProvider),
            ref.read(agentDatabaseProvider),
          ),
          deduplicationService: MemoryDeduplicationService(
            ref.read(embeddingServiceProvider),
            ref.read(agentDatabaseProvider),
            ref.read(apiConfigServiceProvider),
          ),
        ),
        askId: askId,
      )) {
        if (_currentRunId != runId) return;

        final currentState = _getSessionState(sessionId);

        switch (event) {
          case AgentTextDelta(:final text):
            _updateSessionCache(
              sessionId,
              currentState.copyWith(
                streamingText: currentState.streamingText + text,
              ),
            );
            break;

          case AgentToolStart(:final toolCall):
            _updateSessionCache(
              sessionId,
              currentState.copyWith(activeToolName: () => toolCall.name),
            );
            break;

          case AgentToolComplete(:final toolCall, :final durationMs):
            _updateSessionCache(
              sessionId,
              currentState.copyWith(
                activeToolName: () => null,
                completedTools: [
                  ...currentState.completedTools,
                  ToolExecution(name: toolCall.name, durationMs: durationMs),
                ],
              ),
            );
            break;

          case AgentComplete(:final text, :final messages, :final usage):
            assistantMessages.addAll(messages);

            final annotatedMessages = <ChatMessage>[];
            for (final msg in assistantMessages) {
              if (msg.role == MessageRole.assistant &&
                  msg.content != null &&
                  msg.content!.isNotEmpty) {
                annotatedMessages.add(
                  msg.withUsage(
                    inputTokens: usage?.inputTokens,
                    outputTokens: usage?.outputTokens,
                    contextMessages: List.unmodifiable(contextMessages),
                  ),
                );
              } else {
                annotatedMessages.add(msg);
              }
            }

            if (annotatedMessages.isNotEmpty) {
              await manager.addMessages(
                sessionId,
                annotatedMessages,
                providerId: providerId,
                modelId: modelId,
              );
            }

            final latestState = _getSessionState(sessionId);
            final newInputTokens =
                latestState.totalInputTokens + (usage?.inputTokens ?? 0);
            final newOutputTokens =
                latestState.totalOutputTokens + (usage?.outputTokens ?? 0);

            _updateSessionCache(
              sessionId,
              latestState.copyWith(
                messages: [
                  ...annotatedMessages.reversed,
                  ...latestState.messages,
                ],
                streamingText: '',
                isLoading: false,
                activeToolName: () => null,
                completedTools: const [],
                totalInputTokens: newInputTokens,
                totalOutputTokens: newOutputTokens,
                lastInputTokens: usage?.inputTokens ?? latestState.lastInputTokens,
              ),
            );

            // 异步副作用：标题生成
            if (isNewSession && text.isNotEmpty) {
              ChatTitleService.generate(
                client: client,
                modelId: modelId,
                userMessage: userMessageContent,
                assistantReply: text,
                sessionId: sessionId,
                manager: manager,
              );
            }

            // 异步副作用：费用计算
            if (usage != null) {
              ChatCostService.saveUsageAndUpdateCost(
                providerId: providerId,
                modelId: modelId,
                usage: usage,
                sessionId: sessionId,
                manager: manager,
                currentState: _getSessionState(sessionId),
                annotatedMessages: annotatedMessages,
                onStateUpdate: (newState) =>
                    _updateSessionCache(sessionId, newState),
              );
            }

            // 异步副作用：压缩检查
            if (usage != null && session?.assistantId != null) {
              final assist = await assistantRepo.get(session!.assistantId!);
              final threshold = assist?.compressTokenThreshold ?? 0;
              if (threshold > 0) {
                final currentContextTokens = usage.inputTokens;
                final needs = compressor.shouldCompress(
                  currentContextTokens,
                  threshold,
                );
                if (needs) {
                  () async {
                    try {
                      await compressor.compress(
                        sessionId,
                        threshold: threshold,
                        keepTurns: assist?.compressKeepTurns,
                      );
                    } catch (e) {
                      debugPrint('CompressionService: Error: $e');
                    }
                  }();
                }
              }
            }
            break;

          case AgentError(:final error):
            _updateSessionCache(
              sessionId,
              currentState.copyWith(
                error: () => error.toString(),
                isLoading: false,
                streamingText: '',
                activeToolName: () => null,
              ),
            );
            break;

          case AgentStepInfo():
            break;
        }
      }
    } catch (e) {
      debugPrint('AgentChatNotifier error: $e');
      final currentState = _getSessionState(sessionId);
      _updateSessionCache(
        sessionId,
        currentState.copyWith(
          error: () => e.toString(),
          isLoading: false,
          streamingText: '',
          activeToolName: () => null,
        ),
      );
    }
  }

  // ========================================================================
  // 内部工具方法
  // ========================================================================

  ToolRegistry _buildToolRegistry() {
    return ref.read(toolRepositoryProvider.notifier).buildRegistry();
  }

  void _updateSessionCache(String sessionId, AgentChatState newState) {
    _sessionStateCache[sessionId] = newState;
    if (state.sessionId == sessionId) {
      state = newState;
    }
  }

  AgentChatState _getSessionState(String sessionId) {
    return _sessionStateCache[sessionId] ?? state;
  }

  Future<void> _initDefaultAssistant() async {
    try {
      final assistantRepo = ref.read(assistantRepositoryProvider);
      final defaultAssistant = await assistantRepo.getDefault();
      if (defaultAssistant != null) {
        state = state.copyWith(
          currentAssistantId: () => defaultAssistant.id.toString(),
        );
      }
    } catch (_) {}
  }

  /// 清理会话附件目录
  static Future<void> cleanupSessionAttachments({
    required String vaultPath,
    required String sessionId,
  }) => AttachmentService.cleanupSessionAttachments(
    vaultPath: vaultPath,
    sessionId: sessionId,
  );
}
