import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:baishou/core/providers/shared_preferences_provider.dart';
import 'package:baishou/core/storage/data_archive_manager.dart';
import 'package:baishou/core/storage/storage_path_provider.dart';
import 'package:baishou/core/storage/vault_service.dart';
import 'package:baishou/core/database/app_database.dart';
import 'package:baishou/agent/database/agent_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tempDir;
  late ProviderContainer container;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('baishou_archive_test_');
    SharedPreferences.setMockInitialValues({
      'custom_storage_root': tempDir.path,
    });
    final prefs = await SharedPreferences.getInstance();

    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
  });

  tearDown(() async {
    container.dispose();
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (e) {
        debugPrint('Ignored file lock during teardown: $e');
      }
    }
  });

  test('DataArchiveManager correctly exports physical directories into ZIP', () async {
    final vaultService = container.read(vaultServiceProvider.notifier);
    final archiveManager = container.read(dataArchiveManagerProvider.notifier);
    
    // 初始化确保生成 Personal 工作区及其真实 SQLite 文件
    final personalAppDb = container.read(appDatabaseProvider);
    await personalAppDb.customSelect('SELECT 1').get();
    final personalAgentDb = container.read(agentDatabaseProvider);
    await personalAgentDb.customSelect('SELECT 1').get();

    // 在 Personal 目录模拟注入附件
    final pathService = container.read(storagePathServiceProvider);
    final personalAttachmentsDir = Directory(p.join((await pathService.getVaultDirectory('Personal')).path, 'attachments'));
    personalAttachmentsDir.createSync(recursive: true);
    final dummyImage = File(p.join(personalAttachmentsDir.path, 'photo.jpg'));
    dummyImage.writeAsStringSync('image_data');

    // 切换产生第二个工作区
    await vaultService.switchVault('Work');
    final workAppDb = container.read(appDatabaseProvider);
    await workAppDb.customSelect('SELECT 1').get();
    final workAgentDb = container.read(agentDatabaseProvider);
    await workAgentDb.customSelect('SELECT 1').get();

    // 实行物理级全局导出
    final zipFile = await archiveManager.exportToTempFile();
    expect(zipFile, isNotNull);
    expect(zipFile!.existsSync(), isTrue);

    // 校验 ZIP 内部结构
    final bytes = zipFile.readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    // ZIP 内理应包含：
    // Personal/.baishou/baishou.sqlite
    // Personal/attachments/photo.jpg
    // Work/.baishou/agent.sqlite
    // .baishou/vault_registry.json
    final fileNames = archive.map((f) => f.name.replaceAll('\\', '/')).toList();
    debugPrint('ZIP Contents: $fileNames');
    expect(fileNames.any((name) => name.contains('Personal/.baishou/baishou.sqlite')), isTrue);
    expect(fileNames.any((name) => name.contains('Personal/attachments/photo.jpg')), isTrue);
    expect(fileNames.any((name) => name.contains('Work/.baishou/agent.sqlite')), isTrue);
    expect(fileNames.any((name) => name.contains('.baishou/vault_registry.json')), isTrue);

    // 清理生成的临时 ZIP
    zipFile.deleteSync();
  });

  test('DataArchiveManager safely wipes and restores physical root from ZIP', () async {
    final archiveManager = container.read(dataArchiveManagerProvider.notifier);
    await container.read(vaultServiceProvider.future);

    // 先虚构一个备用的“正确” ZIP 文件结构
    final encoder = ZipFileEncoder();
    final fakeZipFile = File(p.join(tempDir.path, 'fake_backup.zip'));
    encoder.create(fakeZipFile.path);

    // Create a dummy structure to zip
    final fakeSourceDir = await Directory.systemTemp.createTemp('baishou_fake_src_');
    final fakeGlobalSys = Directory(p.join(fakeSourceDir.path, '.baishou'));
    fakeGlobalSys.createSync(recursive: true);
    
    try {
      // 写入必需的识别文件
      final fakeRegistry = File(p.join(fakeGlobalSys.path, 'vault_registry.json'));
      fakeRegistry.writeAsStringSync(jsonEncode([{'name': 'RestoredVault', 'path': '/restored'}]));
      
      // 写入特殊的模拟数据证明导入覆盖成功
      // 这里必须是一个合法的 SQLite 文件，我们可以拷一块小数据或用实际 Drift 初始化并关闭。
      // 但为了独立性，干脆复制一个新建立的空 sqlite 文件。
      final fakeRestoredVaultSys = Directory(p.join(fakeSourceDir.path, 'RestoredVault', '.baishou'));
      fakeRestoredVaultSys.createSync(recursive: true);
      // 暂时拷贝原系统内的空 agent.sqlite 作为蓝本
      final pathService = container.read(storagePathServiceProvider);
      final realWorkAgentDb = File(p.join((await pathService.getVaultSystemDirectory('Work')).path, 'agent.sqlite'));
      final fakeNewDb = File(p.join(fakeRestoredVaultSys.path, 'agent.sqlite'));
      realWorkAgentDb.copySync(fakeNewDb.path);

      // 打包这个外来的假 ZIP
      for (final entity in fakeSourceDir.listSync()) {
        if (entity is Directory) {
          encoder.addDirectory(entity);
        } else if (entity is File) {
          encoder.addFile(entity);
        }
      }
      encoder.close();

      // 在导入前，往当前的物理根目录塞入会产生锁的“当前库”
      final personalSysDir = await pathService.getVaultSystemDirectory('Personal');
      File(p.join(personalSysDir.path, 'baishou.sqlite')).writeAsStringSync('old_data');

      // 执行跨设备物理导入
      final result = await archiveManager.importFromZip(fakeZipFile, createSnapshotBefore: false);

      expect(result.profileRestored, isTrue);

      // 验证新目录结构起效
      final newPathService = container.read(storagePathServiceProvider);
      final rootDir = await newPathService.getRootDirectory();
      final allEntities = rootDir.listSync(recursive: true).map((e) => p.relative(e.path, from: rootDir.path).replaceAll('\\', '/')).toList();

      expect(allEntities.contains('RestoredVault/.baishou/agent.sqlite'), isTrue);
      // 原来的 Personal 应该被洗掉了
      expect(allEntities.contains('Personal/.baishou/baishou.sqlite'), isFalse);
    } catch (e, st) {
      debugPrint('TEST FAILED WITH: $e');
      debugPrint('STACKTRACE: $st');
      rethrow;
    } finally {
      try {
        fakeSourceDir.deleteSync(recursive: true);
        fakeZipFile.deleteSync();
      } catch (e) {
        debugPrint('Ignored cleanup error: $e');
      }
    }
  });

  test('DataArchiveManager detects legacy manifest.json and delegates to legacy import', () async {
    final archiveManager = container.read(dataArchiveManagerProvider.notifier);
    
    // 初始化并等待 Vault 挂载，防止底层调用时拿到未初始化或者已经关闭的 DB 连接。
    container.read(appDatabaseProvider);
    await container.read(vaultServiceProvider.future);
    await Future.delayed(const Duration(milliseconds: 100));

    // 内存里手动捏造一个极为干净包含 manifest.json 的旧包
    final archive = Archive();
    archive.addFile(ArchiveFile('manifest.json', 23, utf8.encode('{"schema_version": 1}')));
    archive.addFile(ArchiveFile('data/diaries.json', 2, utf8.encode('[]')));
    archive.addFile(ArchiveFile('data/summaries.json', 2, utf8.encode('[]')));
    
    final encoded = ZipEncoder().encode(archive);
    final fakeLegacyZip = File(p.join(tempDir.path, 'legacy_backup.zip'));
    fakeLegacyZip.writeAsBytesSync(encoded);

    try {
      // 执行旧版导入路由（预期会成功但影响 0 条文档）
      final result = await archiveManager.importFromZip(fakeLegacyZip, createSnapshotBefore: false);
      expect(result.fileCount, 0);
      expect(result.profileRestored, isFalse);
    } catch (e, st) {
      debugPrint('TEST FAILED WITH: $e');
      debugPrint('STACKTRACE: $st');
      rethrow;
    } finally {
      try {
        fakeLegacyZip.deleteSync();
      } catch (e) {
        debugPrint('Ignored cleanup error: $e');
      }
    }
  });
}
