/// DiaryDeleteTool — 删除指定日期的日记
///
/// Agent 通过此工具删除指定日期的日记文件。
/// 会同时删除物理文件和对应的 RAG 向量。

import 'dart:io';
import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';

class DiaryDeleteTool extends AgentTool {
  final AgentDatabase _db;

  DiaryDeleteTool(this._db);

  @override
  String get id => 'diary_delete';

  @override
  String get displayName => t.agent.tools.diary_delete;

  @override
  String get category => 'diary';

  @override
  IconData get icon => Icons.delete_outline_rounded;

  @override
  bool get canBeDisabled => false;

  @override
  String get description =>
      'Delete a diary entry for a specific date. '
      'This permanently removes the Markdown file at Journals/YYYY/MM/YYYY-MM-DD.md. '
      'IMPORTANT: Always confirm with the user before deleting. '
      'Use diary_read first to verify the content that will be deleted.';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'date': {
        'type': 'string',
        'description': 'The date of the diary to delete, in YYYY-MM-DD format.',
      },
    },
    'required': ['date'],
  };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    ToolContext context,
  ) async {
    final date = arguments['date'] as String?;

    if (date == null || date.isEmpty) {
      return ToolResult.error('Missing required parameter: date');
    }

    // 验证日期格式
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!dateRegex.hasMatch(date)) {
      return ToolResult.error(
        'Invalid date format "$date". Expected YYYY-MM-DD.',
      );
    }

    final parts = date.split('-');
    final year = parts[0];
    final month = parts[1];
    final filePath = '${context.vaultPath}/Journals/$year/$month/$date.md';

    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return ToolResult(
          output: 'No diary found for date $date. Nothing to delete.',
          success: true,
          metadata: {'date': date, 'deleted': false},
        );
      }

      // 读取内容用于确认信息
      final content = await file.readAsString();
      final preview = content.length > 80
          ? '${content.substring(0, 80)}...'
          : content;

      // 删除文件
      await file.delete();

      // 清理该日记对应的 RAG 向量
      // 日记的 source_id 是其数字 ID（yyyyMMdd 格式），从日期推算
      try {
        final logicalDate = DateTime.parse(date);
        final diaryId = logicalDate.year * 10000 +
            logicalDate.month * 100 +
            logicalDate.day;
        await _db.deleteEmbeddingsBySource('diary', diaryId.toString());
        debugPrint('DiaryDeleteTool: Cleaned RAG vectors for diary $diaryId');
      } catch (e) {
        debugPrint('DiaryDeleteTool: Failed to clean RAG vectors: $e');
      }

      return ToolResult(
        output:
            'Diary for $date has been deleted successfully.\n'
            'Deleted content preview: $preview',
        success: true,
        metadata: {
          'date': date,
          'deleted': true,
          'deleted_length': content.length,
        },
      );
    } catch (e) {
      return ToolResult.error('Failed to delete diary: $e');
    }
  }
}
