import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/agent/rag/embedding_service.dart';
import 'package:baishou/core/services/api_config_service.dart';
import 'package:baishou/core/widgets/app_toast.dart';
import 'package:baishou/features/diary/data/repositories/diary_repository_impl.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

class RagMemoryDialogs {
  /// 清空所有记忆
  static Future<bool> clearAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.agent.rag.clear_all_title),
        content: Text(t.agent.rag.clear_all_content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.agent.rag.clear_confirm),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final embeddingService = EmbeddingService(
        ref.read(apiConfigServiceProvider),
        ref.read(agentDatabaseProvider),
      );
      await embeddingService.clearAllEmbeddings();
      return true;
    }
    return false;
  }

  /// 展示记忆条目完整内容
  static void showFullContent(
    BuildContext context,
    String text,
    String model,
    String timeStr,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.data_object_rounded, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$model · $timeStr',
                style: Theme.of(context).textTheme.titleSmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(height: 1.6),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.common.cancel),
          ),
        ],
      ),
    );
  }

  /// 手动触发维度检测
  static Future<bool> detectDimension(
    BuildContext context,
    WidgetRef ref,
  ) async {
    bool success = false;
    try {
      final embeddingService = EmbeddingService(
        ref.read(apiConfigServiceProvider),
        ref.read(agentDatabaseProvider),
      );
      await ref.read(apiConfigServiceProvider).setGlobalEmbeddingDimension(0);
      final dimension = await embeddingService.detectDimension();
      if (context.mounted) {
        if (dimension > 0) {
          AppToast.showSuccess(
            context,
            t.agent.rag.detect_success(dimension: dimension.toString()),
          );
          success = true;
        } else {
          AppToast.showError(context, t.agent.rag.detect_failed);
        }
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.showError(
          context,
          t.agent.rag.detect_error(error: e.toString()),
        );
      }
    }
    return success;
  }

  /// 清空当前维度的向量
  static Future<bool> clearCurrentDimension(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final apiConfig = ref.read(apiConfigServiceProvider);
    final dimension = apiConfig.globalEmbeddingDimension;
    if (dimension <= 0) {
      AppToast.showError(context, t.agent.rag.clear_dim_no_config);
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.agent.rag.clear_dim_title),
        content: Text(
          t.agent.rag.clear_dim_content(dimension: dimension.toString()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              t.agent.rag.clear_dim_confirm,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = ref.read(agentDatabaseProvider);
      final deleted = await db.clearEmbeddingsByDimension(dimension);
      if (context.mounted) {
        AppToast.showSuccess(
          context,
          t.agent.rag.clear_dim_success(
            deleted: deleted.toString(),
            dimension: dimension.toString(),
          ),
        );
      }
      return true;
    }
    return false;
  }

  /// 批量嵌入所有日记
  static Future<bool> batchEmbedDiaries({
    required BuildContext context,
    required WidgetRef ref,
    required ValueChanged<int> onTotal,
    required ValueChanged<int> onProgress,
  }) async {
    final embeddingService = EmbeddingService(
      ref.read(apiConfigServiceProvider),
      ref.read(agentDatabaseProvider),
    );
    if (!embeddingService.isConfigured) {
      AppToast.showError(context, t.agent.rag.embedding_not_configured);
      return false;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.agent.rag.batch_embed_title),
        content: Text(t.agent.rag.batch_embed_content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.agent.rag.batch_embed_start),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      final diaryRepo = ref.read(diaryRepositoryProvider);
      final diaries = await diaryRepo.getAllDiaries();
      onTotal(diaries.length);

      int embedded = 0;
      int progressCounter = 0;
      for (final diary in diaries) {
        if (diary.content.trim().isEmpty) {
          progressCounter++;
          onProgress(progressCounter);
          continue;
        }
        final dateLabel = DateFormat('yyyy-MM-dd').format(diary.date);
        await embeddingService.embedText(
          text: '$dateLabel: ${diary.content}',
          sessionId: 'diary_batch',
          customId: 'diary_${diary.id}',
        );
        embedded++;
        progressCounter++;
        onProgress(progressCounter);
      }

      if (context.mounted) {
        AppToast.showSuccess(
          context,
          t.agent.rag.batch_embed_success(count: embedded.toString()),
        );
      }
      return true;
    } catch (e) {
      if (context.mounted) {
        AppToast.showError(
          context,
          t.agent.rag.batch_embed_error(error: e.toString()),
        );
      }
      return false;
    }
  }

  /// 手动添加记忆
  static Future<bool> addManualMemory(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.agent.rag.add_memory_title),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: controller,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: t.agent.rag.add_memory_hint,
              border: const OutlineInputBorder(),
            ),
            autofocus: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(t.agent.rag.add_memory_save),
          ),
        ],
      ),
    );

    if (result != null && result.trim().isNotEmpty) {
      final embeddingService = EmbeddingService(
        ref.read(apiConfigServiceProvider),
        ref.read(agentDatabaseProvider),
      );
      if (!embeddingService.isConfigured) {
        if (context.mounted) {
          AppToast.showError(context, t.agent.rag.embedding_not_configured);
        }
        return false;
      }

      await embeddingService.embedText(
        text: result.trim(),
        sessionId: 'manual_memory',
      );

      if (context.mounted) {
        AppToast.showSuccess(context, t.agent.rag.add_memory_success);
      }
      return true;
    }
    return false;
  }
}
