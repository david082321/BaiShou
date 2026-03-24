import 'dart:io';

import 'package:baishou/core/storage/storage_path_provider.dart';
import 'package:baishou/core/storage/vault_service.dart';
import 'package:baishou/core/storage/permission_service.dart';
import 'package:baishou/core/widgets/app_toast.dart';
import 'package:baishou/features/diary/data/vault_index_notifier.dart';
import 'package:baishou/features/index/data/shadow_index_sync_service.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 存储路径管理设置卡片
class StorageSettingsCard extends ConsumerStatefulWidget {
  const StorageSettingsCard({super.key});

  @override
  ConsumerState<StorageSettingsCard> createState() =>
      _StorageSettingsCardState();
}

class _StorageSettingsCardState extends ConsumerState<StorageSettingsCard> {
  @override
  Widget build(BuildContext context) {
    final storageService = ref.watch(storagePathServiceProvider);
    final theme = Theme.of(context);

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
            leading: const Icon(Icons.folder_shared_outlined),
            title: Text(t.settings.storage_manager),
            subtitle: Text(t.settings.storage_root_desc),
            children: [
              ListTile(
                title: Text(t.settings.storage_root),
                subtitle: FutureBuilder<Directory>(
                  future: storageService.getRootDirectory(),
                  builder: (context, snapshot) {
                    return Text(
                      snapshot.data?.path ?? '...',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    );
                  },
                ),
                trailing: TextButton(
                  onPressed: () => _changeStorageRoot(storageService),
                  child: Text(t.settings.change_storage_root),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _changeStorageRoot(StoragePathService storageService) async {
    // 移动端权限前置检查
    if (Platform.isAndroid) {
      final permissionSvc = ref.read(permissionServiceProvider.notifier);
      final hasPermission = await permissionSvc.hasStoragePermission();
      if (!hasPermission) {
        final granted = await permissionSvc.requestStoragePermission();
        if (!granted) {
          if (mounted) {
            AppToast.showError(
              context,
              t.common.permission.storage_denied,
            );
          }
          return;
        }
      }
    }

    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    if (selectedDirectory == null || !mounted) return;

    await storageService.updateRootDirectory(selectedDirectory);
    ref.invalidate(vaultServiceProvider);

    setState(() {});

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(t.settings.scanning_new_dir),
          ],
        ),
      ),
    );

    try {
      final syncService = ref.read(shadowIndexSyncServiceProvider.notifier);
      await syncService.fullScanVault();
      await ref.read(vaultIndexProvider.notifier).forceReload();

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      final count = ref.read(vaultIndexProvider).value?.length ?? 0;
      AppToast.showSuccess(
        context,
        t.settings.dir_switched(count: count),
        duration: const Duration(seconds: 4),
      );
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        AppToast.showError(
            context, t.settings.dir_scan_failed(error: e.toString()));
      }
    }
  }
}
