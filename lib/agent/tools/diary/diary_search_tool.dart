/// DiarySearchTool — 关键词搜索日记内容
///
/// 基于 ShadowIndexDatabase 的 FTS5 全文索引进行搜索
/// Agent 通过此工具按关键词查找日记，无需知道具体日期

import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:baishou/agent/tools/tool_config_param.dart';
import 'package:baishou/features/index/data/shadow_index_database.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';

class DiarySearchTool extends AgentTool {
  final ShadowIndexDatabase _indexDb;

  DiarySearchTool(this._indexDb);

  @override
  String get id => 'diary_search';

  @override
  String get displayName => t.agent.tools.diary_search;

  @override
  String get category => 'diary';

  @override
  IconData get icon => Icons.search_rounded;

  @override
  List<ToolConfigParam> get configurableParams => [
    ToolConfigParam(
      key: 'max_results',
      label: t.agent.tools.param_max_results,
      description: t.agent.tools.param_max_results_desc,
      type: ParamType.integer,
      defaultValue: 10,
      min: 1,
      max: 50,
      icon: Icons.format_list_numbered,
    ),
  ];

  @override
  String get description =>
      'Search the user\'s PERSONAL DIARY/JOURNAL entries by keyword. '
      'Returns matching diary dates and content snippets. '
      'Use this when the user asks about their own past experiences, memories, or personal records.\n\n'
      'IMPORTANT: This tool ONLY searches the user\'s personal diary entries stored locally, '
      'NOT the internet. To search the internet for public information, use the web_search tool instead.';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'query': {
        'type': 'string',
        'description': 'The search keyword or phrase to find in diary entries.',
      },
      'start_date': {
        'type': 'string',
        'description':
            'Optional. Only search diary entries on or after this date (YYYY-MM-DD). '
            'Use this to narrow results to a specific time period.',
      },
      'end_date': {
        'type': 'string',
        'description':
            'Optional. Only search diary entries on or before this date (YYYY-MM-DD).',
      },
      'limit': {
        'type': 'integer',
        'description': 'Maximum number of results to return. Defaults to 10.',
      },
    },
    'required': ['query'],
  };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    ToolContext context,
  ) async {
    final query = arguments['query'] as String?;
    final startDate = arguments['start_date'] as String?;
    final endDate = arguments['end_date'] as String?;
    final limit = (arguments['limit'] as num?)?.toInt() ?? 10;

    if (query == null || query.trim().isEmpty) {
      return ToolResult.error('Missing required parameter: query');
    }

    try {
      final db = _indexDb.database;

      String dateFilter = '';
      final params = <Object>['%$query%'];

      if (startDate != null) {
        dateFilter += ' AND ji.date >= ?';
        params.add(startDate);
      }
      if (endDate != null) {
        dateFilter += ' AND ji.date <= ?';
        params.add(endDate);
      }
      params.add(limit);

      // 使用 LIKE 语法替代 MATCH 解决 FTS5 不支持 CJK 分词的问题
      final results = db.select('''
        SELECT 
          ji.date,
          ji.mood,
          ji.weather,
          ji.location,
          jf.content
        FROM journals_fts jf
        JOIN journals_index ji ON jf.rowid = ji.id
        WHERE jf.content LIKE ?$dateFilter
        ORDER BY ji.date DESC
        LIMIT ?
        ''', params);

      if (results.isEmpty) {
        return ToolResult(
          output: 'No diary entries found matching "$query".',
          success: true,
          metadata: {'query': query, 'count': 0},
        );
      }

      final buffer = StringBuffer()
        ..writeln('Found ${results.length} diary entries matching "$query":')
        ..writeln();

      for (final row in results) {
        final date = row['date'] as String;
        final content = row['content'] as String? ?? '';
        final mood = row['mood'] as String?;
        final weather = row['weather'] as String?;
        final location = row['location'] as String?;

        // 手动生成 snippet
        String snippet = '';
        final lowerContent = content.toLowerCase();
        final lowerQuery = query.toLowerCase();
        final matchIndex = lowerContent.indexOf(lowerQuery);

        if (matchIndex != -1) {
          final start = (matchIndex - 30).clamp(0, content.length);
          final end = (matchIndex + query.length + 30).clamp(0, content.length);
          
          snippet = (start > 0 ? '...' : '') + 
                    content.substring(start, matchIndex) + 
                    '**' + content.substring(matchIndex, matchIndex + query.length) + '**' + 
                    content.substring(matchIndex + query.length, end) + 
                    (end < content.length ? '...' : '');
        } else {
          snippet = content.length > 100 ? '\${content.substring(0, 100)}...' : content;
        }

        buffer.writeln('## $date');
        if (mood != null || weather != null || location != null) {
          final meta = [
            if (mood != null) 'Mood: $mood',
            if (weather != null) 'Weather: $weather',
            if (location != null) 'Location: $location',
          ].join(' | ');
          buffer.writeln(meta);
        }
        buffer.writeln(snippet);
        buffer.writeln();
      }

      return ToolResult(
        output: buffer.toString(),
        success: true,
        metadata: {
          'query': query,
          'count': results.length,
          'dates': results.map((r) => r['date']).toList(),
        },
      );
    } catch (e) {
      return ToolResult.error('Search failed: $e');
    }
  }
}
