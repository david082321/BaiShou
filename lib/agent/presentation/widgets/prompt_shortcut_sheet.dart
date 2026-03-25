import 'package:baishou/agent/models/prompt_shortcut.dart';
import 'package:baishou/core/services/prompt_shortcut_service.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' as foundation;

class PromptShortcutSheet extends ConsumerWidget {
  final bool isDialog;
  const PromptShortcutSheet({super.key, this.isDialog = false});

  static Future<String?> show(BuildContext context) {
    if (foundation.defaultTargetPlatform == foundation.TargetPlatform.windows || 
        foundation.defaultTargetPlatform == foundation.TargetPlatform.macOS || 
        foundation.defaultTargetPlatform == foundation.TargetPlatform.linux) {
      return showDialog<String>(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
            child: const PromptShortcutSheet(isDialog: true),
          ),
        ),
      );
    }

    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const PromptShortcutSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    
    if (isDialog) {
      return Container(
        color: theme.colorScheme.surface,
        child: _buildContent(context, ref, null),
      );
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: _buildContent(context, ref, scrollController),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, WidgetRef ref, ScrollController? scrollController) {
    final shortcuts = ref.watch(promptShortcutServiceProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        if (!isDialog)
          // 拖拽控制条
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        
        // 标题与操作栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.bolt_rounded,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                '快捷指令',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => _showEditDialog(context, ref),
                icon: const Icon(Icons.add_circle_outline),
                tooltip: t.common.add,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        
        // 列表区域
        Expanded(
          child: shortcuts.isEmpty
              ? Center(
                  child: Text(
                    '暂无快捷指令',
                    style: TextStyle(color: theme.colorScheme.outline),
                  ),
                )
              : ReorderableListView.builder(
                  scrollController: scrollController,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemCount: shortcuts.length,
                  onReorder: (oldIdx, newIdx) {
                    ref
                        .read(promptShortcutServiceProvider.notifier)
                        .reorderShortcuts(oldIdx, newIdx);
                  },
                  itemBuilder: (context, index) {
                    final item = shortcuts[index];
                    return ListTile(
                      key: ValueKey(item.id),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 4,
                      ),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          item.icon,
                          style: const TextStyle(fontSize: 20),
                        ),
                      ),
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        item.content,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: theme.colorScheme.outline),
                      ),
                      trailing: PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        onSelected: (val) {
                          if (val == 'edit') {
                            _showEditDialog(context, ref, shortcut: item);
                          } else if (val == 'delete') {
                            ref
                                .read(promptShortcutServiceProvider.notifier)
                                .removeShortcut(item.id);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                const Icon(Icons.edit_outlined, size: 18),
                                const SizedBox(width: 8),
                                Text(t.common.edit),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete_outline,
                                    size: 18, 
                                    color: theme.colorScheme.error),
                                const SizedBox(width: 8),
                                Text(t.common.delete,
                                    style: TextStyle(
                                      color: theme.colorScheme.error,
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.of(context).pop(item.content);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref, {PromptShortcut? shortcut}) {
    showDialog(
      context: context,
      builder: (ctx) => _ShortcutEditDialog(
        shortcut: shortcut,
        onSave: (newItem) {
          if (shortcut == null) {
            ref.read(promptShortcutServiceProvider.notifier).addShortcut(newItem);
          } else {
            ref.read(promptShortcutServiceProvider.notifier).updateShortcut(newItem);
          }
        },
      ),
    );
  }
}

class _ShortcutEditDialog extends StatefulWidget {
  final PromptShortcut? shortcut;
  final ValueChanged<PromptShortcut> onSave;

  const _ShortcutEditDialog({
    this.shortcut,
    required this.onSave,
  });

  @override
  State<_ShortcutEditDialog> createState() => _ShortcutEditDialogState();
}

class _ShortcutEditDialogState extends State<_ShortcutEditDialog> {
  final _nameController = TextEditingController();
  final _contentController = TextEditingController();
  final _iconController = TextEditingController(text: '⚡');

  @override
  void initState() {
    super.initState();
    if (widget.shortcut != null) {
      _nameController.text = widget.shortcut!.name;
      _contentController.text = widget.shortcut!.content;
      _iconController.text = widget.shortcut!.icon;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contentController.dispose();
    _iconController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.shortcut != null;

    return AlertDialog(
      title: Text(isEdit ? '编辑指令' : '新建指令'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 56,
                  child: TextField(
                    controller: _iconController,
                    maxLength: 2,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20),
                    decoration: const InputDecoration(
                      labelText: '图标',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: '指令名称',
                      hintText: '例如: 总结提取',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _contentController,
              maxLines: 5,
              minLines: 3,
              decoration: const InputDecoration(
                labelText: '指令内容',
                hintText: '输入将要发送给AI的Prompt模板...',
                alignLabelWithHint: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.common.cancel),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim();
            final content = _contentController.text.trim();
            final icon = _iconController.text.trim();
            if (name.isEmpty || content.isEmpty) return;

            final newItem = widget.shortcut?.copyWith(
                  icon: icon.isEmpty ? '⚡' : icon,
                  name: name,
                  content: content,
                ) ??
                PromptShortcut(
                  icon: icon.isEmpty ? '⚡' : icon,
                  name: name,
                  content: content,
                );

            widget.onSave(newItem);
            Navigator.of(context).pop();
          },
          child: Text(t.common.confirm),
        ),
      ],
    );
  }
}

