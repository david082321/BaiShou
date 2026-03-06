import 'dart:io';

import 'package:baishou/core/storage/storage_path_provider.dart';
import 'package:baishou/core/storage/vault_service.dart';
import 'package:baishou/core/database/tables/summaries.dart';
import 'package:baishou/features/summary/domain/entities/summary.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/foundation.dart' hide Summary;
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:yaml/yaml.dart';
import 'package:yaml_writer/yaml_writer.dart';

part 'summary_file_service.g.dart';

/// 物理文件层总结（归档）读写服务
@Riverpod(keepAlive: true)
class SummaryFileService extends _$SummaryFileService {
  StoragePathService get _pathProvider => ref.read(storagePathServiceProvider);

  @override
  FutureOr<void> build() async {
    ref.watch(vaultServiceProvider);
  }

  Future<Directory> _getSecureArchivesBaseDir() async {
    final activeVault = await ref.read(vaultServiceProvider.future);
    if (activeVault == null) {
      throw Exception(t.common.errors.no_active_vault);
    }
    return await _pathProvider.getArchivesBaseDirectory(activeVault.name);
  }

  /// 获取总结文件的物理文件路径
  Future<String> getSummaryFilePath(
    SummaryType type,
    DateTime startDate,
  ) async {
    final file = await _resolveSummaryFile(type, startDate);
    return file.path;
  }

  /// 获取总结文件的物理文件对象
  /// 路径格式：Archives/{Type}/{yyyy-MM-dd}.md
  Future<File> _resolveSummaryFile(SummaryType type, DateTime startDate) async {
    final baseDir = await _getSecureArchivesBaseDir();
    final typeFolder = type.name[0].toUpperCase() + type.name.substring(1);
    final fileName = '${DateFormat('yyyy-MM-dd').format(startDate)}.md';

    final dir = Directory(p.join(baseDir.path, typeFolder));
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }

    return File(p.join(dir.path, fileName));
  }

  /// 写入总结到物理文件
  Future<String> writeSummary(Summary summary) async {
    final file = await _resolveSummaryFile(summary.type, summary.startDate);

    final yamlWriter = YamlWriter();
    final metaData = {
      'id': summary.id,
      'type': summary.type.name,
      'startDate': summary.startDate.toIso8601String(),
      'endDate': summary.endDate.toIso8601String(),
      'generatedAt': summary.generatedAt.toIso8601String(),
      'sourceIds': summary.sourceIds,
    };

    final yamlString = yamlWriter.write(metaData);

    final buffer = StringBuffer();
    buffer.writeln('---');
    buffer.write(yamlString);
    if (!yamlString.endsWith('\n')) {
      buffer.writeln();
    }
    buffer.writeln('---');
    buffer.write(summary.content.trim());

    await file.writeAsString(buffer.toString(), flush: true);
    return file.path;
  }

  /// 从物理文件读取总结
  Future<Summary?> readSummary(SummaryType type, DateTime startDate) async {
    final file = await _resolveSummaryFile(type, startDate);
    if (!file.existsSync()) return null;

    final content = await file.readAsString();
    final regex = RegExp(r'^---\r?\n(.*?)\r?\n---\r?\n(.*)$', dotAll: true);
    final match = regex.firstMatch(content);

    if (match == null) return null;

    final yamlStr = match.group(1) ?? '';
    final bodyStr = match.group(2) ?? '';

    try {
      final doc = loadYaml(yamlStr);
      final meta = Map<String, dynamic>.from(doc as Map);

      return Summary(
        id: meta['id'] as int? ?? 0,
        type: type,
        startDate: DateTime.parse(meta['startDate'] as String),
        endDate: DateTime.parse(meta['endDate'] as String),
        content: bodyStr.trim(),
        generatedAt: DateTime.parse(meta['generatedAt'] as String),
        sourceIds: meta['sourceIds'] != null
            ? List<String>.from(meta['sourceIds'] as Iterable)
            : const [],
      );
    } catch (e) {
      debugPrint(
        'SummaryFileService: Failed to parse YAML for ${file.path}: $e',
      );
      return null;
    }
  }

  /// 删除总结文件
  Future<void> deleteSummaryFile(SummaryType type, DateTime startDate) async {
    final file = await _resolveSummaryFile(type, startDate);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  /// 清空所有归档文件
  Future<void> clearAllArchives() async {
    final baseDir = await _getSecureArchivesBaseDir();
    if (baseDir.existsSync()) {
      await baseDir.delete(recursive: true);
      await baseDir.create(recursive: true);
    }
  }
}
