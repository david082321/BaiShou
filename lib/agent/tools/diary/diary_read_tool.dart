/// DiaryReadTool — 读取指定日期的日记内容
///
/// Agent 通过此工具读取用户的 Markdown 日记文件

import 'dart:io';
import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';

class DiaryReadTool extends AgentTool {
  @override
  String get id => 'diary_read';

  @override
  String get displayName => t.agent.tools.diary_read;

  @override
  String get category => 'diary';

  @override
  IconData get icon => Icons.auto_stories_outlined;

  @override
  bool get canBeDisabled => false;

  @override
  String get description =>
      'Read multiple diary entries for specific dates. Returns the full Markdown content of the diary files. '
      'You can request up to 20 dates at once. Date format: YYYY-MM-DD (e.g. 2026-03-15).';

  @override
  Map<String, dynamic> get parameterSchema => {
        'type': 'object',
        'properties': {
          'dates': {
            'type': 'array',
            'items': {'type': 'string'},
            'description':
                'A list of dates to read diaries for, in YYYY-MM-DD format. Maximum 20 dates.',
          },
        },
        'required': ['dates'],
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    ToolContext context,
  ) async {
    final datesDynamic = arguments['dates'] as List<dynamic>?;
    if (datesDynamic == null || datesDynamic.isEmpty) {
      return ToolResult.error('Missing required parameter: dates');
    }

    final dates = datesDynamic.map((e) => e.toString()).take(20).toList();
    final dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');

    final buffer = StringBuffer();
    int foundCount = 0;
    int missingCount = 0;

    for (final date in dates) {
      if (!dateRegex.hasMatch(date)) {
        buffer.writeln('⚠️ Invalid date format "$date". Expected YYYY-MM-DD.\n');
        missingCount++;
        continue;
      }

      final parts = date.split('-');
      final year = parts[0];
      final month = parts[1];
      final filePath = '${context.vaultPath}/Journals/$year/$month/$date.md';

      final file = File(filePath);
      if (!await file.exists()) {
        buffer.writeln('## [$date]');
        buffer.writeln('*No diary found for this date.*\n');
        missingCount++;
        continue;
      }

      try {
        final content = await file.readAsString();
        buffer.writeln('## [$date]');
        buffer.writeln(content);
        buffer.writeln('\n---\n');
        foundCount++;
      } catch (e) {
        buffer.writeln('## [$date]');
        buffer.writeln('*Failed to read diary: $e*\n');
        missingCount++;
      }
    }

    return ToolResult(
      output: buffer.toString().trimRight(),
      success: true,
      metadata: {
        'requested_count': dates.length,
        'found_count': foundCount,
        'missing_count': missingCount,
      },
    );
  }
}
