import 'package:baishou/agent/models/chat_message.dart';
import 'package:baishou/agent/presentation/notifiers/agent_chat_state.dart';

/// 连续工具消息的分组标记
class ToolGroup {
  final List<ChatMessage> messages;
  const ToolGroup(this.messages);
}

class AgentChatMessageGrouper {
  /// 将消息列表预处理为展示项
  ///
  /// 核心逻辑：把 「空内容 assistant(toolCalls) + tool 结果」 这种连续序列
  /// 合并为一个 ToolGroup，这样多次工具调用不会拆分成多个独立卡片。
  ///
  /// 同时从 assistant 的 toolCalls 中提取工具名，回填到 tool 结果消息上
  /// （兼容旧数据）。
  static List<Object> buildDisplayItems(AgentChatState chatState) {
    if (chatState.messages.isEmpty) return [];

    final items = <Object>[];
    // chatState.messages 目前是按时间倒序的（最新在 0）。
    // 为了和原有的合并连续工具调用的顺时逻辑保持高度一致，我们先将其翻转为正序（先发生在前，即 index=0）。
    final messages = chatState.messages.reversed.toList();

    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];

      // 检测到空内容 assistant（仅包含 toolCalls）或 tool 消息
      // → 开始收集一组工具调用
      if (_isToolRelated(msg)) {
        final toolGroup = <ChatMessage>[];

        while (i < messages.length && _isToolRelated(messages[i])) {
          final current = messages[i];

          if (current.role == MessageRole.assistant &&
              current.toolCalls != null &&
              current.toolCalls!.isNotEmpty) {
            // 这是一个空内容 assistant 消息，包含 toolCalls 信息
            // 向后查找对应的 tool 结果并回填工具名
            final callMap = {
              for (final call in current.toolCalls!) call.id: call.name,
            };

            // 向后扫描紧邻的 tool 消息
            i++;
            while (i < messages.length &&
                messages[i].role == MessageRole.tool) {
              final toolMsg = messages[i];
              // 如果 toolName 为空，从 callMap 中回填
              if (toolMsg.toolName == null || toolMsg.toolName!.isEmpty) {
                final resolvedName =
                    callMap[toolMsg.toolCallId] ?? toolMsg.toolName;
                // 创建带工具名的副本（避免修改原对象）
                toolGroup.add(
                  ChatMessage(
                    id: toolMsg.id,
                    role: toolMsg.role,
                    content: toolMsg.content,
                    toolCallId: toolMsg.toolCallId,
                    toolName: resolvedName,
                    timestamp: toolMsg.timestamp,
                  ),
                );
              } else {
                toolGroup.add(toolMsg);
              }
              i++;
            }
            // 不 i++，因为 while 已经移动了
          } else if (current.role == MessageRole.tool) {
            // 单独的 tool 消息（没有前置 assistant）
            toolGroup.add(current);
            i++;
          } else {
            break;
          }
        }

        if (toolGroup.isNotEmpty) {
          items.add(ToolGroup(toolGroup));
        }
        // i 现在指向下一个非工具消息，但 for 的 i++ 还会执行，所以回退一步
        i--;
      } else {
        items.add(msg);
      }
    }

    // 最后，将合并好工具调用的 items 再次翻转回倒序，供 ListView(reverse: true) 使用
    return items.reversed.toList();
  }

  /// 判断消息是否属于工具调用序列的一部分
  static bool _isToolRelated(ChatMessage msg) {
    if (msg.role == MessageRole.tool) return true;
    // assistant 消息只要包含 toolCalls 就属于工具序列
    // （即使有文本内容如"让我搜索一下…"，也合入工具分组而不单独成泡）
    if (msg.role == MessageRole.assistant &&
        msg.toolCalls != null &&
        msg.toolCalls!.isNotEmpty) {
      return true;
    }
    return false;
  }
}
