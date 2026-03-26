// RAG 记忆管理页面的可复用组件
//
// StatChip — 统计指标标签
// ActionChip — 操作按钮标签
// MemoryEntryCard — 记忆条目卡片

import 'package:baishou/core/services/api_config_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// ─── 统计指标 chip ──────────────────────────────────────────

class RagStatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const RagStatChip({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// 操作按钮 Chip
class RagActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool isLoading;

  const RagActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: MouseRegion(
        cursor: onTap != null
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              else
                Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 记忆条目卡片
class MemoryEntryCard extends StatelessWidget {
  final Map<String, dynamic> entry;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const MemoryEntryCard({
    super.key,
    required this.entry,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final dateFormat = DateFormat('MM/dd HH:mm');

    final text = entry['chunk_text'] as String? ?? '';
    final model = entry['model_id'] as String? ?? '';
    final createdAt = entry['created_at'] as int?;
    final timeStr = createdAt != null
        ? dateFormat.format(DateTime.fromMillisecondsSinceEpoch(createdAt))
        : '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 3),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      color: colorScheme.surfaceContainerLow,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        leading: Icon(
          Icons.data_object_rounded,
          size: 18,
          color: colorScheme.primary.withValues(alpha: 0.6),
        ),
        title: Text(
          text.length > 200 ? '${text.substring(0, 200)}...' : text,
          maxLines: 4,
          overflow: TextOverflow.ellipsis,
          style: textTheme.bodySmall?.copyWith(height: 1.4),
        ),
        subtitle: Text(
          '$model · $timeStr',
          style: textTheme.labelSmall?.copyWith(color: colorScheme.outline),
        ),
        onTap: onTap,
      ),
    );
  }
}

// ─── 新增的提取组件 ──────────────────────────────────────────

/// 检索参数滑块调节区
class RagMemoryRetrievalConfig extends ConsumerStatefulWidget {
  const RagMemoryRetrievalConfig({super.key});

  @override
  ConsumerState<RagMemoryRetrievalConfig> createState() =>
      _RagMemoryRetrievalConfigState();
}

class _RagMemoryRetrievalConfigState
    extends ConsumerState<RagMemoryRetrievalConfig> {
  late double _topK;
  late double _threshold;

  @override
  void initState() {
    super.initState();
    final config = ref.read(apiConfigServiceProvider);
    _topK = config.ragTopK.toDouble().clamp(10, 100);
    _threshold = config.ragSimilarityThreshold;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                t.agent.rag.retrieval_params,
                style: textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // TopK 滑块
          Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  'Top K',
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Slider(
                  value: _topK,
                  min: 10,
                  max: 100,
                  divisions: 9,
                  label: _topK.round().toString(),
                  onChanged: (v) => setState(() => _topK = v),
                  onChangeEnd: (v) =>
                      ref.read(apiConfigServiceProvider).setRagTopK(v.round()),
                ),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  _topK.round().toString(),
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          // 相似度阈值滑块
          Row(
            children: [
              SizedBox(
                width: 100,
                child: Text(
                  t.agent.rag.similarity_threshold,
                  style: textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Expanded(
                child: Slider(
                  value: _threshold,
                  min: 0.0,
                  max: 1.0,
                  divisions: 20,
                  label: _threshold.toStringAsFixed(2),
                  onChanged: (v) => setState(() => _threshold = v),
                  onChangeEnd: (v) => ref
                      .read(apiConfigServiceProvider)
                      .setRagSimilarityThreshold(v),
                ),
              ),
              SizedBox(
                width: 32,
                child: Text(
                  _threshold.toStringAsFixed(2),
                  style: textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 顶部维度监测与基本状态 Board
class RagMemoryStatsBoard extends ConsumerWidget {
  final int totalCount;
  final Map<String, dynamic> stats;
  final bool isDetectingDimension;
  final VoidCallback onDetectDimension;

  const RagMemoryStatsBoard({
    super.key,
    required this.totalCount,
    required this.stats,
    required this.isDetectingDimension,
    required this.onDetectDimension,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    // 从 DB 统计读取模型，空时回退到全局配置
    var modelDisplay =
        (stats['models'] as List?)
            ?.map((m) => (m as Map)['model_id'] ?? '')
            .where((s) => (s as String).isNotEmpty)
            .toSet()
            .join(', ') ??
        '';
    if (modelDisplay.isEmpty) {
      final apiConfig = ref.read(apiConfigServiceProvider);
      final configuredModel = apiConfig.globalEmbeddingModelId;
      modelDisplay = configuredModel.isNotEmpty
          ? configuredModel
          : t.common.not_configured;
    }
    // 从 DB 统计读取实际维度值
    final models = stats['models'] as List? ?? [];
    final dbDimension = models.isNotEmpty
        ? (models.first as Map)['dimension'] as int? ?? 0
        : 0;

    final configDimension = ref
        .watch(apiConfigServiceProvider)
        .globalEmbeddingDimension;
    final dimension = dbDimension > 0 ? dbDimension : configDimension;

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        RagStatChip(
          icon: Icons.layers_outlined,
          label: t.agent.rag.stat_total,
          value: '$totalCount',
          color: colorScheme.primary,
        ),
        RagStatChip(
          icon: Icons.model_training_outlined,
          label: t.agent.rag.stat_model,
          value: modelDisplay,
          color: colorScheme.tertiary,
        ),
        if (dimension > 0 || configDimension > 0)
          RagStatChip(
            icon: Icons.straighten_outlined,
            label: t.agent.rag.stat_dimension,
            value: '${dimension > 0 ? dimension : configDimension}',
            color: colorScheme.secondary,
          ),
        _buildDimensionStatusChip(context, ref, configDimension),
      ],
    );
  }

  Widget _buildDimensionStatusChip(
    BuildContext context,
    WidgetRef ref,
    int configDimension,
  ) {
    final apiConfig = ref.read(apiConfigServiceProvider);
    final hasModel = apiConfig.hasEmbeddingModel;

    if (configDimension > 0) {
      return GestureDetector(
        onTap: isDetectingDimension ? null : onDetectDimension,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDetectingDimension)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.green.shade700,
                    ),
                  )
                else
                  Icon(
                    Icons.check_circle_outline,
                    size: 14,
                    color: Colors.green.shade700,
                  ),
                const SizedBox(width: 4),
                Text(
                  t.agent.rag.dimension_detected(
                    dimension: configDimension.toString(),
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.green.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (!isDetectingDimension) ...[
                  const SizedBox(width: 4),
                  Icon(
                    Icons.refresh,
                    size: 12,
                    color: Colors.green.shade700,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    } else if (hasModel) {
      return GestureDetector(
        onTap: isDetectingDimension ? null : onDetectDimension,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDetectingDimension)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.orange.shade700,
                    ),
                  )
                else
                  Icon(
                    Icons.play_circle_outline,
                    size: 14,
                    color: Colors.orange.shade700,
                  ),
                const SizedBox(width: 4),
                Text(
                  isDetectingDimension
                      ? t.agent.rag.dimension_detecting
                      : t.agent.rag.dimension_click_detect,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.warning_amber_outlined,
              size: 14,
              color: Colors.red.shade700,
            ),
            const SizedBox(width: 4),
            Text(
              t.agent.rag.dimension_not_configured,
              style: TextStyle(
                fontSize: 11,
                color: Colors.red.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
  }
}
