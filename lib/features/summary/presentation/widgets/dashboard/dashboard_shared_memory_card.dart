import 'package:baishou/core/theme/app_theme.dart';
import 'package:baishou/features/summary/domain/services/context_builder.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';

class DashboardSharedMemoryCard extends StatelessWidget {
  final ContextResult? result;
  final int currentMonths;
  final int maxMonths;
  final TextEditingController monthsController;
  final ValueChanged<int> onMonthsChanged;
  final VoidCallback onCopyContext;

  const DashboardSharedMemoryCard({
    super.key,
    required this.result,
    required this.currentMonths,
    required this.maxMonths,
    required this.monthsController,
    required this.onMonthsChanged,
    required this.onCopyContext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sliderMax = currentMonths > maxMonths
        ? currentMonths.toDouble()
        : maxMonths.toDouble();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.format_quote_rounded,
                size: 20,
                color: AppTheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                '${t.common.app_title} · ${t.summary.shared_memory}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            t.summary.shared_memory_desc,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          if (result != null) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildMiniStatBadge(
                  Icons.book_rounded,
                  result!.diaryCount,
                  t.summary.stats_daily,
                  Colors.green,
                ),
                _buildMiniStatBadge(
                  Icons.view_week_rounded,
                  result!.weekCount,
                  t.summary.stats_weekly,
                  Colors.indigo,
                ),
                _buildMiniStatBadge(
                  Icons.grid_view_rounded,
                  result!.monthCount,
                  t.summary.stats_monthly,
                  Colors.blue,
                ),
                _buildMiniStatBadge(
                  Icons.date_range_rounded,
                  result!.quarterCount,
                  t.summary.stats_quarterly,
                  Colors.amber.shade700,
                ),
                _buildMiniStatBadge(
                  Icons.calendar_today_rounded,
                  result!.yearCount,
                  t.summary.stats_yearly,
                  Colors.orange,
                ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          // 滑块选择范围
          Row(
            children: [
              Text(
                t.summary.range_selector,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              SizedBox(
                width: 36,
                child: TextField(
                  controller: monthsController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  onSubmitted: (v) {
                    final val = int.tryParse(v);
                    if (val != null && val > 0) {
                      onMonthsChanged(val);
                    } else {
                      monthsController.text = currentMonths.toString();
                    }
                  },
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                    border: InputBorder.none,
                  ),
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
            value: currentMonths.toDouble().clamp(1.0, sliderMax),
            min: 1,
            max: sliderMax,
            activeColor: AppTheme.primary,
            onChanged: (v) {
              final val = v.round();
              if (val != currentMonths) {
                monthsController.text = val.toString();
                onMonthsChanged(val);
              }
            },
          ),
          const SizedBox(height: 8),

          // 复制按钮
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onCopyContext,
              icon: const Icon(Icons.copy, size: 16),
              label: Text(t.summary.copy_memories),
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

  Widget _buildMiniStatBadge(
    IconData icon,
    int count,
    String label,
    Color color,
  ) {
    if (count == 0) return const SizedBox.shrink();
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
            style: TextStyle(fontSize: 12, color: color.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}
