/// MemoryDeleteTool — 删除向量记忆
///
/// 通过语义搜索找到匹配的记忆条目，然后删除对应的嵌入数据。

import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/agent/rag/hybrid_search.dart';
import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';

class MemoryDeleteTool extends AgentTool {
  final AgentDatabase _db;

  MemoryDeleteTool(this._db);

  @override
  String get id => 'memory_delete';

  @override
  String get displayName => t.agent.tools.memory_delete;

  @override
  String get category => 'memory';

  @override
  IconData get icon => Icons.delete_sweep_outlined;

  @override
  bool get canBeDisabled => true;

  @override
  String get description =>
      'Delete stored memories by semantic search. '
      'First searches for memories matching the query, then deletes the matching entries. '
      'Use this when the user wants to forget something or remove outdated information. '
      'IMPORTANT: Always confirm with the user before deleting memories.';

  @override
  Map<String, dynamic> get parameterSchema => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'Search query to find memories to delete. '
                'Describe the content of memories you want to remove.',
          },
          'message_id': {
            'type': 'string',
            'description':
                'Optional. Delete a specific memory by its message ID. '
                'If provided, query is ignored.',
          },
        },
        'required': ['query'],
      };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    ToolContext context,
  ) async {
    final query = arguments['query'] as String? ?? '';
    final messageId = arguments['message_id'] as String?;

    try {
      if (messageId != null && messageId.isNotEmpty) {
        // 精确删除：按 message_id
        await _db.deleteEmbeddingsBySource('chat', messageId);
        return ToolResult(
          output: 'Memory chunks for message ID "$messageId" have been deleted.',
          success: true,
          metadata: {'message_id': messageId},
        );
      }

      if (query.isEmpty) {
        return ToolResult.error(
          'Missing required parameter: query or message_id',
        );
      }

      // 语义搜索匹配的记忆
      final embeddingService = context.embeddingService;
      if (embeddingService == null) {
        return ToolResult.error('嵌入服务未配置，无法搜索记忆。');
      }

      final queryEmbedding = await embeddingService.embedQuery(query);
      if (queryEmbedding == null) {
        return ToolResult.error('嵌入模型未配置或查询嵌入失败。');
      }

      // 搜索最相关的记忆
      final vectorRaw = await _db.searchSimilar(
        queryEmbedding: queryEmbedding,
        topK: 5,
      );

      final results = vectorRaw
          .where((r) => (1.0 - (r['distance'] as double)) >= 0.5) // 只删除高相关度的
          .toList();

      if (results.isEmpty) {
        return ToolResult(
          output: 'No memories found matching "$query" with sufficient '
              'similarity (≥0.5). Nothing deleted.',
          success: true,
          metadata: {'deleted_count': 0},
        );
      }

      // 删除找到的记忆
      final deletedPreviews = <String>[];

      for (final result in results) {
        await _db.deleteEmbeddingsBySource(result['source_type'] as String, result['source_id'] as String);
        final chunkText = result['chunk_text'] as String;
        final preview = chunkText.length > 60
            ? '${chunkText.substring(0, 60)}...'
            : chunkText;
        final score = 1.0 - (result['distance'] as double);
        deletedPreviews.add(
          '- [${score.toStringAsFixed(2)}] $preview',
        );
      }

      return ToolResult(
        output: 'Deleted ${results.length} matching memory entries:\n'
            '${deletedPreviews.join('\n')}',
        success: true,
        metadata: {
          'matched_entries': results.length,
        },
      );
    } catch (e) {
      return ToolResult.error('Failed to delete memories: $e');
    }
  }
}
