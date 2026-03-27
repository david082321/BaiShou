import 'dart:io';

import 'package:baishou/core/storage/data_archive_manager.dart';
import 'package:baishou/core/services/data_refresh_notifier.dart'
    as baishou_refresh;
import 'package:baishou/core/widgets/app_toast.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// 数据管理设置卡片（导出、导入、快照恢复）
class DataManagementCard extends ConsumerStatefulWidget {
  const DataManagementCard({super.key});

  @override
  ConsumerState<DataManagementCard> createState() => _DataManagementCardState();
}

class _DataManagementCardState extends ConsumerState<DataManagementCard> {
  @override
  Widget build(BuildContext context) {
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
            leading: const Icon(Icons.storage_outlined),
            title: Text(t.settings.data_management),
            subtitle: Text(t.settings.data_management_desc),
            children: [
              ListTile(
                leading: const Icon(Icons.download_outlined),
                title: Text(t.settings.export_data),
                subtitle: Text(t.settings.export_desc),
                trailing: const Icon(Icons.chevron_right),
                onTap: _exportData,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.upload_file_outlined),
                title: Text(t.settings.import_data),
                subtitle: Text(t.settings.import_desc),
                trailing: const Icon(Icons.chevron_right),
                onTap: _importData,
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.history),
                title: Text(t.settings.restore_snapshot),
                subtitle: Text(t.settings.restore_desc),
                trailing: const Icon(Icons.chevron_right),
                onTap: _restoreFromSnapshot,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _exportData() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(t.settings.exporting_data),
          ],
        ),
      ),
    );

    try {
      final exportService = ref.read(dataArchiveManagerProvider.notifier);
      final exportFile = await exportService.exportToUserDevice();

      if (mounted) {
        Navigator.pop(context);
        if (exportFile != null) {
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text(t.settings.export_success),
              content: Text(
                t.settings.export_success_desc(path: exportFile.path),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(t.common.ok),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        AppToast.showError(
          context,
          t.settings.export_failed(error: e.toString()),
        );
      }
    }
  }

  Future<void> _importData() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );

    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.settings.confirm_restore),
        content: Text(t.settings.confirm_restore_desc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.common.restore),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(t.settings.restoring_data),
          ],
        ),
      ),
    );

    try {
      final importResult = await ref
          .read(dataArchiveManagerProvider.notifier)
          .importFromZip(file);

      if (!mounted) return;
      Navigator.pop(context);

      if (importResult.success) {
        if (!mounted) return;
        ref.read(baishou_refresh.dataRefreshProvider.notifier).refresh();
        AppToast.showSuccess(
          context,
          t.settings.restore_success_simple,
        );
      } else {
        AppToast.showError(
          context,
          importResult.error ?? t.settings.restore_failed_generic,
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        AppToast.showError(
          context,
          t.settings.restore_failed(error: e.toString()),
        );
      }
    }
  }

  Future<void> _restoreFromSnapshot() async {
    final appDir = await getApplicationDocumentsDirectory();
    final snapshotDir = Directory('${appDir.path}/snapshots');

    if (!snapshotDir.existsSync()) {
      if (mounted) AppToast.show(context, t.settings.no_snapshots_available);
      return;
    }

    final allFiles =
        snapshotDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.zip'))
            .toList()
          ..sort((a, b) => b.path.compareTo(a.path));

    if (allFiles.length > 10) {
      for (var i = 10; i < allFiles.length; i++) {
        try {
          allFiles[i].deleteSync();
        } catch (_) {}
      }
    }

    final snapshots = allFiles.take(10).toList();

    if (snapshots.isEmpty) {
      if (mounted) AppToast.show(context, t.settings.no_snapshots_available);
      return;
    }

    if (!mounted) return;

    final selected = await showDialog<File>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.settings.select_snapshot_to_restore),
        content: SizedBox(
          width: double.maxFinite,
          height: 300,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: snapshots.length,
            itemBuilder: (context, index) {
              final f = snapshots[index];
              final name = f.path.split(Platform.pathSeparator).last;
              final timeMatch = RegExp(r'(\d{8})_(\d{6})').firstMatch(name);
              String displayTime = name;
              if (timeMatch != null) {
                final d = timeMatch.group(1)!;
                final t = timeMatch.group(2)!;
                displayTime =
                    '${d.substring(0, 4)}-${d.substring(4, 6)}-${d.substring(6, 8)} '
                    '${t.substring(0, 2)}:${t.substring(2, 4)}:${t.substring(4, 6)}';
              }
              final fileSize = f.lengthSync();
              final sizeStr = fileSize > 1024 * 1024
                  ? '${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB'
                  : '${(fileSize / 1024).toStringAsFixed(0)} KB';
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text(displayTime),
                subtitle: Text(sizeStr),
                onTap: () => Navigator.pop(ctx, f),
              );
            },
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

    if (selected == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.settings.confirm_restore),
        content: Text(t.settings.confirm_restore_desc),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(t.common.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t.common.restore),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 16),
            Text(t.settings.restoring_data),
          ],
        ),
      ),
    );

    try {
      final importResult = await ref
          .read(dataArchiveManagerProvider.notifier)
          .importFromZip(selected);

      if (!mounted) return;
      Navigator.pop(context);

      if (importResult.success) {
        if (!mounted) return;
        ref.read(baishou_refresh.dataRefreshProvider.notifier).refresh();
        AppToast.showSuccess(
          context,
          t.settings.restore_success_simple,
          duration: const Duration(seconds: 4),
        );
      } else {
        AppToast.showError(
          context,
          importResult.error ?? t.settings.restore_failed_generic,
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        AppToast.showError(
          context,
          t.settings.restore_failed(error: e.toString()),
        );
      }
    }
  }
}
