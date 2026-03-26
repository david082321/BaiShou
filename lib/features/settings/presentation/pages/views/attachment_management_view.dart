import 'package:baishou/features/storage/domain/services/attachment_service.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:baishou/core/widgets/app_toast.dart';

class AttachmentManagementView extends ConsumerWidget {
  const AttachmentManagementView({super.key});

  String _formatBytes(int bytes) {
    if (bytes <= 0) return "0 B";
    const suffixes = ["B", "KB", "MB", "GB", "TB"];
    var i = 0;
    double d = bytes.toDouble();
    while (d >= 1024 && i < suffixes.length - 1) {
      d /= 1024;
      i++;
    }
    return '${d.toStringAsFixed(2)} ${suffixes[i]}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentState = ref.watch(attachmentListProvider);

    return Scaffold(
      body: attachmentState.when(
        data: (attachments) {
          int totalSize = 0;
          int orphanSize = 0;
          final orphans = <AttachmentFolderInfo>[];

          for (final doc in attachments) {
            totalSize += doc.totalBytes;
            if (doc.isOrphan) {
              orphanSize += doc.totalBytes;
              orphans.add(doc);
            }
          }

          final theme = Theme.of(context);

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16.0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildOverviewCard(
                      context, 
                      theme, 
                      totalSize, 
                      orphanSize, 
                      orphans.length,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      t.settings.attachment_management_desc,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    if (orphans.isNotEmpty)
                      _buildOrphansList(context, theme, orphans, ref)
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32.0),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.check_circle_outline,
                                  size: 48, color: theme.colorScheme.primary),
                              const SizedBox(height: 16),
                              Text(t.settings.attachment_no_orphans),
                            ],
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '${t.common.error}: $err',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildOverviewCard(
    BuildContext context,
    ThemeData theme,
    int totalSize,
    int orphanSize,
    int orphansCount,
  ) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn(
                  theme,
                  t.settings.attachment_total_size,
                  _formatBytes(totalSize),
                  theme.colorScheme.primary,
                ),
                Container(
                  height: 40,
                  width: 1,
                  color: theme.colorScheme.outlineVariant,
                ),
                _buildStatColumn(
                  theme,
                  t.settings.attachment_orphans_size,
                  _formatBytes(orphanSize),
                  orphansCount > 0
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurface,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(
      ThemeData theme, String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: valueColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildOrphansList(
    BuildContext context,
    ThemeData theme,
    List<AttachmentFolderInfo> orphans,
    WidgetRef ref,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          onPressed: () => _confirmClearOrphans(context, ref, orphans),
          icon: const Icon(Icons.delete_sweep),
          label: Text(t.settings.attachment_clear_orphans),
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.errorContainer,
            foregroundColor: theme.colorScheme.onErrorContainer,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          t.settings.attachment_clear_orphans_desc,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: orphans.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final doc = orphans[index];
            return ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: Text(doc.sessionId),
              subtitle: Text('${doc.fileCount} 文件'),
              trailing: Text(
                _formatBytes(doc.totalBytes),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Future<void> _confirmClearOrphans(
    BuildContext context,
    WidgetRef ref,
    List<AttachmentFolderInfo> orphans,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.settings.attachment_clear_confirm_title),
        content: Text(t.settings.attachment_clear_confirm_desc),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.delete_forever),
            label: Text(t.common.delete),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      int freedBytes = 0;
      for (final orphan in orphans) {
        freedBytes += orphan.totalBytes;
      }

      await ref.read(attachmentServiceProvider).clearAllOrphans();
      ref.invalidate(attachmentListProvider);

      if (context.mounted) {
        AppToast.showSuccess(
          context,
          t.settings.attachment_clear_completed(size: _formatBytes(freedBytes)),
        );
      }
    }
  }
}
