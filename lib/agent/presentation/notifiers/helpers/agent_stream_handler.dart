import 'package:baishou/agent/clients/ai_client.dart';
import 'package:baishou/agent/models/chat_message.dart';
import 'package:baishou/agent/runner/agent_runner.dart';
import 'package:baishou/agent/session/compression_service.dart';
import 'package:baishou/agent/session/session_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:baishou/agent/presentation/notifiers/agent_chat_state.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:baishou/agent/session/assistant_repository.dart';
import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/agent/presentation/notifiers/chat_side_effects.dart';

class AgentStreamHandler {
  /// 处理并消费 Runner 输出的流，并更新状态、计算使用统计与执行额外副作用
  static Future<void> handleStream({
    required Ref ref,
    required Stream<AgentEvent> stream,
    required String sessionId,
    required int runId,
    required int Function() getCurrentRunId,
    required AgentChatState Function(String) getSessionState,
    required void Function(String, AgentChatState) updateSessionState,
    required String providerId,
    required String modelId,
    required bool isNewSession,
    required String userMessageContent,
    required List<ChatMessage> contextMessages,
    required AiClient client,
    required void Function(Map<String, dynamic>) onDiaryWriteSuccess,
  }) async {
    final manager = ref.read(sessionManagerProvider);
    final compressor = ref.read(compressionServiceProvider);
    final assistantRepo = ref.read(assistantRepositoryProvider);
    final db = ref.read(agentDatabaseProvider);

    try {
      final assistantMessages = <ChatMessage>[];

      await for (final event in stream) {
        if (getCurrentRunId() != runId) return;

        final currentState = getSessionState(sessionId);

        switch (event) {
          case AgentTextDelta(:final text):
            updateSessionState(
              sessionId,
              currentState.copyWith(
                streamingText: currentState.streamingText + text,
              ),
            );
            break;

          case AgentToolStart(:final toolCall):
            updateSessionState(
              sessionId,
              currentState.copyWith(activeToolName: () => toolCall.name),
            );
            break;

          case AgentToolComplete(
            :final toolCall,
            :final result,
            :final durationMs,
          ):
            updateSessionState(
              sessionId,
              currentState.copyWith(
                activeToolName: () => null,
                completedTools: [
                  ...currentState.completedTools,
                  ToolExecution(name: toolCall.name, durationMs: durationMs),
                ],
              ),
            );

            // 日记编辑/删除成功后，触发外部回调刷新索引
            if ((toolCall.name == 'diary_edit' ||
                    toolCall.name == 'diary_delete') &&
                result.success) {
              onDiaryWriteSuccess(toolCall.arguments);
            }
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

            final latestState = getSessionState(sessionId);
            final newInputTokens =
                latestState.totalInputTokens + (usage?.inputTokens ?? 0);
            final newOutputTokens =
                latestState.totalOutputTokens + (usage?.outputTokens ?? 0);

            updateSessionState(
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
                lastInputTokens:
                    usage?.inputTokens ?? latestState.lastInputTokens,
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
                currentState: getSessionState(sessionId),
                annotatedMessages: annotatedMessages,
                onStateUpdate: (newState) =>
                    updateSessionState(sessionId, newState),
              );
            }

            // 异步副作用：压缩检查
            if (usage != null) {
              final session = await (db.select(
                db.agentSessions,
              )..where((t) => t.id.equals(sessionId))).getSingleOrNull();
              if (session?.assistantId != null) {
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
            }
            break;

          case AgentError(:final error):
            updateSessionState(
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
            // Ignored StepInfo events
            break;
        }
      }
    } catch (e) {
      debugPrint('AgentStreamHandler error: $e');
      final currentState = getSessionState(sessionId);
      updateSessionState(
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
}
