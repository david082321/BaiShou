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
                      : TextButton(
                          onPressed: () => _switchVault(vault.name),
                          child: const Text('切换'),
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
