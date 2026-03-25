import 'package:baishou/core/theme/app_theme.dart';
import 'package:baishou/features/summary/domain/entities/summary.dart';
import 'package:baishou/features/summary/presentation/widgets/summary_gallery_tab.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:baishou/core/database/tables/summaries.dart';
import 'package:flutter/material.dart';

class DashboardGallerySection extends StatelessWidget {
  final TabController galleryTabController;
  final Summary? selectedSummary;
  final ValueChanged<Summary?> onSelect;
  final VoidCallback onDelete;

  const DashboardGallerySection({
    super.key,
    required this.galleryTabController,
    required this.selectedSummary,
    required this.onSelect,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        // 标签栏
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TabBar(
                  controller: galleryTabController,
                  isScrollable: true,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicatorWeight: 2,
                  indicatorColor: AppTheme.primary,
                  labelColor: AppTheme.primary,
                  unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                  labelStyle: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  dividerHeight: 0,
                  tabAlignment: TabAlignment.start,
                  splashBorderRadius: BorderRadius.circular(8),
                  tabs: [
                    Tab(text: t.summary.tab_weekly),
                    Tab(text: t.summary.tab_monthly),
                    Tab(text: t.summary.tab_quarterly),
                    Tab(text: t.summary.tab_yearly),
                  ],
                ),
              ),
            ],
          ),
        ),
        // 画廊内容
        Expanded(
          child: TabBarView(
            controller: galleryTabController,
            children: [
              GalleryTab(
                type: SummaryType.weekly,
                selectedSummary: selectedSummary,
                onSelect: onSelect,
                onDelete: onDelete,
              ),
              GalleryTab(
                type: SummaryType.monthly,
                selectedSummary: selectedSummary,
                onSelect: onSelect,
                onDelete: onDelete,
              ),
              GalleryTab(
                type: SummaryType.quarterly,
                selectedSummary: selectedSummary,
                onSelect: onSelect,
                onDelete: onDelete,
              ),
              GalleryTab(
                type: SummaryType.yearly,
                selectedSummary: selectedSummary,
                onSelect: onSelect,
                onDelete: onDelete,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
