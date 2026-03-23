/// 聊天副作用服务 — 标题生成、费用计算、附件管理
///
/// 从 AgentChatNotifier 抽取的辅助功能，遵循单一职责原则。

import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:baishou/agent/clients/ai_client.dart';
import 'package:baishou/agent/models/chat_message.dart';
import 'package:baishou/agent/models/message_attachment.dart';
import 'package:baishou/agent/models/stream_event.dart';
import 'package:baishou/agent/pricing/model_pricing_service.dart';
import 'package:baishou/agent/session/session_manager.dart';
import 'package:baishou/agent/presentation/notifiers/agent_chat_state.dart';
import 'package:flutter/foundation.dart';

/// 标题自动生成服务
class ChatTitleService {
  /// 根据用户消息和 AI 回复自动生成对话标题
  static Future<void> generate({
    required AiClient client,
    required String modelId,
    required String userMessage,
    required String assistantReply,
    required String sessionId,
    required SessionManager manager,
  }) async {
    try {
      final userPreview = userMessage.length > 200
          ? userMessage.substring(0, 200)
          : userMessage;
      final replyPreview = assistantReply.length > 200
          ? assistantReply.substring(0, 200)
          : assistantReply;

      String title = '';
      await for (final event in client.chatStream(
        messages: [
          ChatMessage.system(
            '根据以下对话生成一个简短的标题（10个字以内，不要标点符号，不要引号）。'
            '只输出标题本身，不要任何解释。',
          ),
          ChatMessage.user('用户: $userPreview\\n伙伴: $replyPreview'),
        ],
        modelId: modelId,
      )) {
        if (event is TextDelta) {
          title += event.text;
        }
      }

      title = title.trim();
      if (title.isNotEmpty && title.length <= 30) {
        await manager.updateSessionTitle(sessionId, title);
      }
    } catch (e) {
      debugPrint('Auto-generate title failed: $e');
    }
  }
}

/// 费用计算服务
class ChatCostService {
  /// 异步保存 token 用量和费用
  ///
  /// [onStateUpdate] 回调用于通知调用方更新 state（例如回填 cost 到消息）
  static Future<void> saveUsageAndUpdateCost({
    required String providerId,
    required String modelId,
    required TokenUsage usage,
    required String sessionId,
    required SessionManager manager,
    required AgentChatState currentState,
    List<ChatMessage>? annotatedMessages,
    required void Function(AgentChatState) onStateUpdate,
  }) async {
    try {
      final costUsd = await ModelPricingService.instance.calculateCost(
        providerId,
        modelId,
        usage,
      );

      final costMicros = costUsd != null ? (costUsd * 1000000).round() : 0;

      await manager.addUsage(
        sessionId: sessionId,
        inputTokens: usage.inputTokens,
        outputTokens: usage.outputTokens,
        costMicros: costMicros,
      );

      if (costMicros > 0) {
        if (costUsd != null && annotatedMessages != null) {
          final updatedMessages = currentState.messages.map((msg) {
            if (msg.inputTokens != null &&
                annotatedMessages.any((a) => a.id == msg.id)) {
              return msg.withUsage(cost: costUsd);
            }
            return msg;
          }).toList();

          for (final a in annotatedMessages) {
            await manager.updateMessageCost(a.id, costMicros);
          }

          onStateUpdate(currentState.copyWith(
            totalCostMicros: currentState.totalCostMicros + costMicros,
            messages: updatedMessages,
          ));
        } else {
          onStateUpdate(currentState.copyWith(
            totalCostMicros: currentState.totalCostMicros + costMicros,
          ));
        }
      }

      debugPrint(
        'Usage saved: ${usage.inputTokens} in / ${usage.outputTokens} out'
        ' = \$${costUsd?.toStringAsFixed(6) ?? "unknown"}',
      );
    } catch (e) {
      debugPrint('Save usage failed: $e');
    }
  }
}

/// 附件管理服务
class AttachmentService {
  /// 复制附件文件到应用私有目录
  ///
  /// 路径: {vaultPath}/attachments/{sessionId}/{uuid}.ext
  /// 确保移动端临时路径的文件被持久化。
  static Future<List<MessageAttachment>> copyToPrivate({
    required List<MessageAttachment> attachments,
    required String vaultPath,
    required String sessionId,
  }) async {
    final dir = Directory(p.join(vaultPath, 'attachments', sessionId));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final result = <MessageAttachment>[];
    for (final att in attachments) {
      try {
        final srcFile = File(att.filePath);
        if (!srcFile.existsSync()) {
          result.add(att);
          continue;
        }

        final ext = p.extension(att.fileName);
        final destName = '${att.id}$ext';
        final destPath = p.join(dir.path, destName);
        final destFile = File(destPath);

        if (att.filePath == destPath) {
          result.add(att);
          continue;
        }

        await srcFile.copy(destPath);
        result.add(att.copyWith(filePath: destFile.path));
      } catch (e) {
        debugPrint('附件复制失败: ${att.fileName}: $e');
        result.add(att);
      }
    }
    return result;
  }

  /// 清理会话附件目录
  static Future<void> cleanupSessionAttachments({
    required String vaultPath,
    required String sessionId,
  }) async {
    final dir = Directory(p.join(vaultPath, 'attachments', sessionId));
    if (dir.existsSync()) {
      try {
        await dir.delete(recursive: true);
        debugPrint('已清理附件目录: ${dir.path}');
      } catch (e) {
        debugPrint('清理附件目录失败: $e');
      }
    }
  }
}

