/// 缺失总结卡片组件
///
/// 展示单条缺失总结的信息和生成按钮，支持加载/错误/正常三种状态。

import 'package:baishou/core/theme/app_theme.dart';
import 'package:baishou/features/summary/domain/services/missing_summary_detector.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';

class MissingSummaryCard extends StatelessWidget {
  final MissingSummary item;
  final String? status;
  final VoidCallback onGenerate;

  const MissingSummaryCard({
    super.key,
    required this.item,
    this.status,
    required this.onGenerate,
  });

  @override
  Widget build(BuildContext context) {
    final isError =
        status != null &&
        (status!.startsWith(t.summary.generation_failed) ||
            status!.startsWith(t.summary.content_empty) ||
            status == t.summary.tap_to_retry);
    final isLoading = status != null && !isError;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          // 图标区域
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.calendar_today_rounded,
              color: Color(0xFFF28B50),
              size: 20,
            ),
          ),
          const SizedBox(width: 16),

          // 文本区域
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Text(
                      '${item.startDate.month}月${item.startDate.day}日 - ${item.endDate.month}月${item.endDate.day}日',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF4E5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        t.summary.suggestion_generate,
                        style: const TextStyle(
                          color: Color(0xFFF28B50),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                if (status != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    status!,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: isError ? Colors.red : AppTheme.primary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),

          // 按钮区域
          if (isLoading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Material(
              color: isError
                  ? Colors.red.withValues(alpha: 0.1)
                  : const Color(0xFFF2EFFF),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: onGenerate,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(
                    isError
                        ? Icons.refresh_rounded
                        : Icons.auto_fix_high_rounded,
                    color: isError ? Colors.red : const Color(0xFF6C5CE7),
                    size: 18,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
