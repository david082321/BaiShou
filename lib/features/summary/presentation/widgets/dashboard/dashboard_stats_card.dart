import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';

class DashboardStatsCard extends StatelessWidget {
  final int totalDiaryCount;
  final int totalWeeklyCount;
  final int totalMonthlyCount;
  final int totalQuarterlyCount;
  final int totalYearlyCount;

  const DashboardStatsCard({
    super.key,
    required this.totalDiaryCount,
    required this.totalWeeklyCount,
    required this.totalMonthlyCount,
    required this.totalQuarterlyCount,
    required this.totalYearlyCount,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              Icon(Icons.analytics_rounded,
                  size: 20, color: Colors.green.shade600),
              const SizedBox(width: 8),
              Text(
                '${t.common.app_title} · ${t.summary.stats_panel}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 统计项
          Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildStatTile(
                      theme,
                      icon: Icons.book_rounded,
                      count: totalDiaryCount,
                      label: t.summary.stats_daily,
                      color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatTile(
                      theme,
                      icon: Icons.view_week_rounded,
                      count: totalWeeklyCount,
                      label: t.summary.stats_weekly,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildStatTile(
                      theme,
                      icon: Icons.grid_view_rounded,
                      count: totalMonthlyCount,
                      label: t.summary.stats_monthly,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatTile(
                      theme,
                      icon: Icons.date_range_rounded,
                      count: totalQuarterlyCount,
                      label: t.summary.stats_quarterly,
                      color: Colors.amber.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildStatTile(
                theme,
                icon: Icons.calendar_today_rounded,
                count: totalYearlyCount,
                label: t.summary.stats_yearly,
                color: Colors.orange,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(
    ThemeData theme, {
    required IconData icon,
    required int count,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                count.toString(),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
