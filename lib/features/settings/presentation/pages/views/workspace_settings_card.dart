import 'package:baishou/core/storage/vault_service.dart';
import 'package:baishou/core/widgets/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 工作空间管理设置卡片
class WorkspaceSettingsCard extends ConsumerStatefulWidget {
  const WorkspaceSettingsCard({super.key});

  @override
  ConsumerState<WorkspaceSettingsCard> createState() =>
      _WorkspaceSettingsCardState();
}

class _WorkspaceSettingsCardState extends ConsumerState<WorkspaceSettingsCard> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vaultState = ref.watch(vaultServiceProvider);
    final vaultService = ref.read(vaultServiceProvider.notifier);
    final theme = Theme.of(context);

    // 等待初始化
    if (vaultState.isLoading) {
      return const SizedBox.shrink();
    }

    final activeVault = vaultState.value;
    final allVaults = vaultService.getAllVaults();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          ExpansionTile(
            leading: const Icon(Icons.workspaces_outline),
            title: const Text('工作空间 (Workspaces)'),
            subtitle: Text('当前空间: ${activeVault?.name ?? '未知'}'),
            children: [
              for (final vault in allVaults)
                ListTile(
                  leading: const Icon(Icons.folder_special),
                  title: Text(vault.name),
                  subtitle: Text(
                    '上次访问: ${vault.lastAccessedAt.toString().split('.')[0]}',
                  ),
                  trailing: activeVault?.name == vault.name
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) {
                            if (value == 'switch') {
                              _switchVault(vault.name);
                            } else if (value == 'delete') {
                              _deleteVault(vault.name);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'switch',
                              child: Row(
                                children: [
                                  Icon(Icons.login, size: 20),
                                  SizedBox(width: 8),
                                  Text('切换至此空间'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_forever,
                                      size: 20, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('删除空间',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('创建新空间'),
                onTap: _showCreateVaultDialog,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _switchVault(String name) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Text('正在切换工作空间...'),
            ],
          ),
        ),
      );

      final service = ref.read(vaultServiceProvider.notifier);
      await service.switchVault(name);

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // 关闭 loading
        AppToast.showSuccess(context, '成功切换至空间 [$name]');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        AppToast.showError(context, '切换失败: $e');
      }
    }
  }

  Future<void> _deleteVault(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        String inputName = '';
        return StatefulBuilder(
          builder: (context, setState) {
            final isMatch = inputName.trim() == name;
            return AlertDialog(
              title: const Text(
                '删除工作空间',
                style: TextStyle(color: Colors.red),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '您确定要永久删除工作空间 [$name] 吗？\n'
                    '此操作将销毁该空间下的所有日志记录和关联档案，且不可恢复！\n',
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '请输入工作空间名称以确认删除：',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: name,
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      setState(() {
                        inputName = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: isMatch ? () => Navigator.of(ctx).pop(true) : null,
                  child: const Text('确认删除'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirm != true) return;

    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('正在销毁工作空间...'),
              ],
            ),
          ),
        );
      }

      final service = ref.read(vaultServiceProvider.notifier);
      await service.deleteVault(name);

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // 关闭 loading
        AppToast.showSuccess(context, '已成功销毁工作空间 [$name]');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop(); // 关闭 loading
        AppToast.showError(context, '删除失败: $e');
      }
    }
  }

  Future<void> _showCreateVaultDialog() async {
    _nameController.clear();
    final name = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('创建新工作空间'),
          content: TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: '空间名称',
              hintText: '例如：工作、副业、灵感',
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final txt = _nameController.text.trim();
                if (txt.isNotEmpty) {
                  Navigator.of(context).pop(txt);
                }
              },
              child: const Text('创建并切换'),
            ),
          ],
        );
      },
    );

    if (name != null && name.isNotEmpty) {
      await _switchVault(name);
    }
  }
}
