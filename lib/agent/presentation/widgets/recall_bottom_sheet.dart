/// 回忆唤醒弹窗
///
/// 在 Agent 聊天页面点击「唤醒回忆」按钮后弹出，
/// 用户通过滑块选择时间范围，一键将过去的回忆摘要发送给 AI。
/// 复用 ContextBuilder.buildLifeBookContext() 级联去重算法。

import 'package:baishou/core/theme/app_theme.dart';
import 'package:baishou/features/summary/domain/services/context_builder.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class RecallBottomSheet extends ConsumerStatefulWidget {
  /// 确认回调：返回构建好的回忆上下文文本
  final void Function(String contextText, int months) onConfirm;

  const RecallBottomSheet({super.key, required this.onConfirm});

  @override
  ConsumerState<RecallBottomSheet> createState() => _RecallBottomSheetState();

  /// 便捷方法：显示弹窗
  static void show(BuildContext context, WidgetRef ref, {
    required void Function(String contextText, int months) onConfirm,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => RecallBottomSheet(onConfirm: onConfirm),
    );
  }
}

class _RecallBottomSheetState extends ConsumerState<RecallBottomSheet> {
  int _months = 6;
  bool _isLoading = false;
  ContextResult? _preview;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    setState(() => _isLoading = true);
    try {
      final result = await ref
          .read(contextBuilderProvider)
          .buildLifeBookContext(months: _months);
      if (mounted) {
        setState(() {
          _preview = result;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleConfirm() {
    if (_preview == null || _preview!.text.isEmpty) return;
    widget.onConfirm(_preview!.text, _months);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 拖拽指示条
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 标题
          Row(
            children: [
              Icon(Icons.auto_stories_rounded,
                  color: AppTheme.primary, size: 22),
              const SizedBox(width: 8),
              Text(
                t.settings.recall_dialog_title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            t.settings.recall_dialog_desc,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),

          // 月份滑块
          Row(
            children: [
              Text(
                t.settings.recall_months_label,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                '$_months',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                t.summary.month_unit,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          Slider(
            value: _months.toDouble(),
            min: 1,
            max: 60,
            divisions: 59,
            activeColor: AppTheme.primary,
            onChanged: (v) {
              final newMonths = v.round();
              if (newMonths != _months) {
                setState(() => _months = newMonths);
                _loadPreview();
              }
            },
          ),

          // 统计预览
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (_preview != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_preview!.diaryCount > 0)
                    _StatBadge(Icons.book_rounded, _preview!.diaryCount,
                        t.summary.stats_daily, Colors.green),
                  if (_preview!.weekCount > 0)
                    _StatBadge(Icons.view_week_rounded, _preview!.weekCount,
                        t.summary.stats_weekly, Colors.indigo),
                  if (_preview!.monthCount > 0)
                    _StatBadge(Icons.grid_view_rounded, _preview!.monthCount,
                        t.summary.stats_monthly, Colors.blue),
                  if (_preview!.quarterCount > 0)
                    _StatBadge(Icons.date_range_rounded, _preview!.quarterCount,
                        t.summary.stats_quarterly, Colors.amber.shade700),
                  if (_preview!.yearCount > 0)
                    _StatBadge(Icons.calendar_today_rounded, _preview!.yearCount,
                        t.summary.stats_yearly, Colors.orange),
                ],
              ),
            ),

          // 发送按钮
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_preview != null && !_isLoading) ? _handleConfirm : null,
              icon: const Icon(Icons.send_rounded, size: 16),
              label: Text(t.settings.recall_send),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBadge extends StatelessWidget {
  final IconData icon;
  final int count;
  final String label;
  final Color color;

  const _StatBadge(this.icon, this.count, this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}
