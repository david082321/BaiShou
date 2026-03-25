import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';

class AgentChatErrorPanel extends StatelessWidget {
  final String error;
  final bool isLoading;
  final VoidCallback onRetry;

  const AgentChatErrorPanel({
    super.key,
    required this.error,
    required this.isLoading,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 16,
                color: theme.colorScheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _friendlyError(error),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onErrorContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: isLoading ? null : onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(t.agent.chat.retry),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onErrorContainer,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 将原始错误信息转换为用户友好的提示
  static String _friendlyError(String raw) {
    // 使用正则匹配 HTTP 状态码（避免误匹配端口号/时间戳等）
    final statusMatch = RegExp(
      r'(?:status\s*(?:code)?|HTTP)\s*:?\s*(\d{3})',
    ).firstMatch(raw);
    final statusCode = statusMatch != null
        ? int.tryParse(statusMatch.group(1)!)
        : null;

    String? friendly;
    if (statusCode != null) {
      if (statusCode == 400) friendly = t.agent.chat.err_format;
      if (statusCode == 401 || statusCode == 403) {
        friendly = t.agent.chat.err_unauthorized;
      }
      if (statusCode == 429) friendly = t.agent.chat.err_too_many_requests;
      if (statusCode >= 500 && statusCode <= 503) {
        friendly = t.agent.chat.err_server;
      }
    }
    if (raw.contains('timeout') || raw.contains('TimeoutException')) {
      friendly = t.agent.chat.err_timeout;
    }
    if (raw.contains('SocketException') || raw.contains('Connection refused')) {
      friendly = t.agent.chat.err_network;
    }

    // 拼接友好提示 + 原始错误（方便排查）
    final truncated = raw.length > 200 ? '${raw.substring(0, 200)}...' : raw;
    return friendly != null ? '$friendly\n$truncated' : truncated;
  }
}
