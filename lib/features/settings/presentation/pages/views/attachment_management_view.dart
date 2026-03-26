import 'package:baishou/features/storage/domain/services/attachment_service.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:baishou/core/widgets/app_toast.dart';

class AttachmentManagementView extends ConsumerStatefulWidget {
  const AttachmentManagementView({super.key});

  @override
  ConsumerState<AttachmentManagementView> createState() =>
      _AttachmentManagementViewState();
}

class _AttachmentManagementViewState
    extends ConsumerState<AttachmentManagementView> {
  /// false = 全部附件, true = 仅孤立附件
  bool _showOrphansOnly = false;

  /// 已勾选的 sessionId 集合
  final Set<String> _selectedIds = {};

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
  Widget build(BuildContext context) {
    final attachmentState = ref.watch(attachmentListProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: attachmentState.when(
        data: (allAttachments) {
          // 统计
          int totalSize = 0;
          int orphanSize = 0;
          int totalFiles = 0;
          final orphans = <AttachmentFolderInfo>[];

          for (final folder in allAttachments) {
            totalSize += folder.totalBytes;
            totalFiles += folder.fileCount;
            if (folder.isOrphan) {
              orphanSize += folder.totalBytes;
              orphans.add(folder);
            }
          }

          // 当前展示列表
          final displayList = _showOrphansOnly ? orphans : allAttachments;

          return Column(
            children: [
              // ─── 顶部概览卡片 ───
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: _buildOverviewCard(
                  theme,
                  totalSize,
                  orphanSize,
                  totalFiles,
                  orphans.length,
                ),
              ),

              // ─── Tab 切换 + 操作栏 ───
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    // Tab 切换
                    _buildTabButton(
                      theme,
                      label: t.settings.attachment_tab_all,
                      count: allAttachments.length,
                      isActive: !_showOrphansOnly,
                      onTap: () => setState(() {
                        _showOrphansOnly = false;
                        _selectedIds.clear();
                      }),
                    ),
                    const SizedBox(width: 8),
                    _buildTabButton(
                      theme,
                      label: t.settings.attachment_tab_orphans,
                      count: orphans.length,
                      isActive: _showOrphansOnly,
                      onTap: () => setState(() {
                        _showOrphansOnly = true;
                        _selectedIds.clear();
                      }),
                    ),
                    const Spacer(),
                    // 全选 / 取消全选
                    if (displayList.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() {
                          if (_selectedIds.length == displayList.length) {
                            _selectedIds.clear();
                          } else {
                            _selectedIds.addAll(
                              displayList.map((f) => f.sessionId),
                            );
                          }
                        }),
                        child: Text(
                          _selectedIds.length == displayList.length
                              ? t.settings.attachment_deselect_all
                              : t.settings.attachment_select_all,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                  ],
                ),
              ),

              // ─── 列表主体 ───
              Expanded(
                child: displayList.isEmpty
                    ? _buildEmptyState(theme)
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        itemCount: displayList.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 4),
                        itemBuilder: (context, index) {
                          final folder = displayList[index];
                          final isChecked = _selectedIds.contains(
                            folder.sessionId,
                          );
                          return _buildFolderTile(theme, folder, isChecked);
                        },
                      ),
              ),

              // ─── 底部操作栏 ───
              if (_selectedIds.isNotEmpty) _buildBottomBar(theme, displayList),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              '${t.common.error}: $err',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
        ),
      ),
    );
  }

  // ─── 概览卡片 ───────────────────────────────────────────────

  Widget _buildOverviewCard(
    ThemeData theme,
    int totalSize,
    int orphanSize,
    int totalFiles,
    int orphanCount,
  ) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
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
              t.settings.attachment_total_count,
              '$totalFiles',
              theme.colorScheme.onSurface,
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
              orphanCount > 0
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurface,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatColumn(
    ThemeData theme,
    String label,
    String value,
    Color valueColor,
  ) {
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: valueColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // ─── Tab 按钮 ──────────────────────────────────────────────

  Widget _buildTabButton(
    ThemeData theme, {
    required String label,
    required int count,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.4,
                ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelMedium?.copyWith(
                color: isActive
                    ? theme.colorScheme.onPrimaryContainer
                    : theme.colorScheme.onSurfaceVariant,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isActive
                    ? theme.colorScheme.primary.withValues(alpha: 0.15)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 空状态 ────────────────────────────────────────────────

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _showOrphansOnly
                ? Icons.check_circle_outline
                : Icons.folder_off_outlined,
            size: 48,
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _showOrphansOnly
                ? t.settings.attachment_no_orphans
                : t.settings.attachment_no_attachments,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 文件夹列表项 ──────────────────────────────────────────

  Widget _buildFolderTile(
    ThemeData theme,
    AttachmentFolderInfo folder,
    bool isChecked,
  ) {
    return Card(
      elevation: 0,
      color: isChecked
          ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
          : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          if (isChecked) {
            _selectedIds.remove(folder.sessionId);
          } else {
            _selectedIds.add(folder.sessionId);
          }
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              // 勾选框
              Checkbox(
                value: isChecked,
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selectedIds.add(folder.sessionId);
                  } else {
                    _selectedIds.remove(folder.sessionId);
                  }
                }),
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),

              // 文件夹图标
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: folder.isOrphan
                      ? theme.colorScheme.errorContainer.withValues(alpha: 0.4)
                      : theme.colorScheme.primaryContainer.withValues(
                          alpha: 0.4,
                        ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  folder.isOrphan
                      ? Icons.folder_off_outlined
                      : Icons.folder_outlined,
                  color: folder.isOrphan
                      ? theme.colorScheme.error
                      : theme.colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),

              // 信息列
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 标题行
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            folder.sessionTitle ?? folder.sessionId,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (folder.isOrphan) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.errorContainer,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              t.settings.attachment_orphan_label,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onErrorContainer,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${folder.fileCount} files',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // 大小
              Text(
                _formatBytes(folder.totalBytes),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── 底部操作栏 ────────────────────────────────────────────

  Widget _buildBottomBar(
    ThemeData theme,
    List<AttachmentFolderInfo> displayList,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Text(
              t.settings.attachment_delete_selected(
                count: _selectedIds.length.toString(),
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _confirmDeleteSelected(displayList),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(t.common.delete),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── 批量删除确认 ──────────────────────────────────────────

  Future<void> _confirmDeleteSelected(
    List<AttachmentFolderInfo> displayList,
  ) async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.settings.attachment_clear_confirm_title),
        content: Text(
          t.settings.attachment_delete_selected_confirm(
            count: count.toString(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(t.common.cancel),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(ctx).pop(true),
            icon: const Icon(Icons.delete_forever, size: 18),
            label: Text(t.common.delete),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final service = ref.read(attachmentServiceProvider);
      int freedBytes = 0;

      for (final id in _selectedIds) {
        final folder = displayList.where((f) => f.sessionId == id).firstOrNull;
        if (folder != null) {
          freedBytes += folder.totalBytes;
        }
        await service.deleteAttachmentFolder(id);
      }

      if (!mounted) return;

      _selectedIds.clear();
      ref.invalidate(attachmentListProvider);

      AppToast.showSuccess(
        context,
        t.settings.attachment_clear_completed(size: _formatBytes(freedBytes)),
      );
    }
  }
}
