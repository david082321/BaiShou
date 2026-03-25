/// WebSearchTool — AI 可调用的网络搜索工具
///
/// 通过 Tavily/DuckDuckGo 获取搜索结果，让 AI 获取实时互联网信息。
/// 支持 Multi-Query：AI 可以同时提交多个查询词，系统并行搜索后去重合并。
///
/// 当启用 RAG 压缩且配置了 embedding 模型时：
/// 搜索 → snippet 分块 → KNN 检索 → Round Robin → 合并

import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:baishou/agent/tools/search/search_rag_service.dart';
import 'package:baishou/agent/tools/search/web_search_service.dart';
import 'package:baishou/agent/tools/tool_config_param.dart';
import 'package:baishou/core/services/api_config_service.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class WebSearchTool extends AgentTool {
  final ApiConfigService apiConfig;

  WebSearchTool(this.apiConfig);

  @override
  String get id => 'web_search';

  @override
  String get displayName => t.agent.tools.web_search;

  @override
  String get category => 'search';

  @override
  IconData get icon => Icons.travel_explore_rounded;

  @override
  List<ToolConfigParam> get configurableParams => [];

  @override
  String get description =>
      'Search the internet for current information, news, and real-time data. '
      'Use this when the user asks about recent events, current facts, or anything '
      'that requires up-to-date information beyond your training data.\n\n'
      'IMPORTANT: You should provide 2-3 search queries with different angles/keywords '
      'to get comprehensive results. For example, if the user asks about "iPhone 16 vs Samsung S25", '
      'you could search ["iPhone 16 specs review", "Samsung S25 specs review", "iPhone 16 vs Samsung S25 comparison"].\n\n'
      'Results include clickable [title](url) citations — use the url_read tool to read specific pages in detail.';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'queries': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'A list of 1-3 search queries with different angles/keywords. '
            'Using multiple queries greatly improves result diversity and comprehensiveness. '
            'Example: ["latest Flutter 4.0 features", "Flutter 4.0 migration guide"]',
        'minItems': 1,
        'maxItems': 3,
      },
    },
    'required': ['queries'],
  };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    ToolContext context,
  ) async {
    // 兼容旧的 query（string）和新的 queries（array）
    final List<String> queries;
    if (arguments.containsKey('queries') && arguments['queries'] is List) {
      queries = (arguments['queries'] as List)
          .map((e) => e.toString().trim())
          .where((q) => q.isNotEmpty)
          .toList();
    } else if (arguments.containsKey('query') && arguments['query'] is String) {
      // 向后兼容：部分 LLM 可能仍然传 query
      final q = (arguments['query'] as String).trim();
      queries = q.isNotEmpty ? [q] : [];
    } else {
      return ToolResult.error('Missing required parameter: queries');
    }

    if (queries.isEmpty) {
      return ToolResult.error('At least one search query is required.');
    }

    final engineStr = apiConfig.webSearchEngine;
    final maxResults = apiConfig.webSearchMaxResults;
    final ragEnabled = apiConfig.webSearchRagEnabled;
    final tavilyApiKey = apiConfig.tavilyApiKey;

    final engine = _parseEngine(engineStr);

    try {
      // ── 步骤 1: Multi-Query 搜索（含自动引擎 fallback） ──
      List<SearchResult> results = [];
      String actualEngine = engineStr;

      // 首选引擎搜索
      try {
        results = await WebSearchService.multiSearch(
          queries: queries,
          engine: engine,
          maxResultsPerQuery: maxResults,
          totalMaxResults: maxResults,
          apiKey: tavilyApiKey,
        );
        debugPrint(
          'WebSearch: primary engine $engineStr returned ${results.length} results',
        );
        if (results.isEmpty) {
          throw Exception(
            'Primary engine returned 0 results (possible anti-bot block)',
          );
        }
      } catch (primaryError) {
        debugPrint(
          'WebSearch: primary engine $engineStr failed: $primaryError',
        );

        final fallbackEngines = [
          SearchEngine.tavily,
          SearchEngine.duckduckgo,
        ].where((e) => e != engine).toList();

        for (final fallback in fallbackEngines) {
          try {
            debugPrint('WebSearch: trying fallback engine ${fallback.name}...');
            results = await WebSearchService.multiSearch(
              queries: queries,
              engine: fallback,
              maxResultsPerQuery: maxResults,
              totalMaxResults: maxResults,
              apiKey: tavilyApiKey,
            );
            actualEngine = fallback.name;
            debugPrint(
              'WebSearch: fallback ${fallback.name} returned ${results.length} results',
            );
            if (results.isNotEmpty) break;
            throw Exception('Fallback engine returned 0 results');
          } catch (fallbackError) {
            debugPrint(
              'WebSearch: fallback ${fallback.name} also failed: $fallbackError',
            );
          }
        }

        // 所有引擎都失败
        if (results.isEmpty) {
          return ToolResult.error(
            'Web search failed with all engines. '
            'Primary ($engineStr): $primaryError. '
            'Please check network connectivity.',
          );
        }
      }

      if (results.isEmpty) {
        return ToolResult(
          output: 'No search results found for: ${queries.join(", ")}',
          success: true,
          metadata: {'queries': queries, 'engine': actualEngine, 'count': 0},
        );
      }

      // ── 步骤 2: RAG 压缩（可选） ──
      if (ragEnabled &&
          context.embeddingService != null &&
          context.embeddingService!.isConfigured) {
        return _executeWithRag(
          queries: queries,
          results: results,
          context: context,
          engineStr: actualEngine,
        );
      }

      // ── 普通模式：直接返回格式化摘要 ──
      return _formatPlainResults(queries, results, actualEngine);
    } catch (e) {
      return ToolResult.error('Web search failed: $e');
    }
  }

  /// 解析搜索引擎枚举
  SearchEngine _parseEngine(String str) {
    switch (str) {
      case 'duckduckgo':
        return SearchEngine.duckduckgo;
      case 'tavily':
      default:
        return SearchEngine.tavily;
    }
  }

  /// RAG 压缩模式
  /// 直接使用搜索 API 返回的 snippet 进行 RAG，
  /// 不下载完整网页（避免并行大量 HTTP 请求导致 OOM）。
  /// 用户若需要某个页面的完整内容，可通过 url_read 工具单独读取。
  Future<ToolResult> _executeWithRag({
    required List<String> queries,
    required List<SearchResult> results,
    required ToolContext context,
    required String engineStr,
  }) async {
    debugPrint('WebSearch: RAG mode enabled, using snippets');

    // 直接使用搜索结果的 content/snippet，不抓全文
    final ragInputs = results
        .map((r) => {'title': r.title, 'url': r.url, 'content': r.snippet})
        .toList();

    // RAG 压缩（使用第一个查询词作为主要语义锚）
    try {
      final compressed = await SearchRagService.compress(
        query: queries.first,
        results: ragInputs,
        embeddingService: context.embeddingService!,
        totalMaxChunks: 12,
        maxChunksPerSource: 4,
      );

      if (compressed.isEmpty) {
        debugPrint('WebSearch: RAG returned empty, falling back to plain');
        return _formatPlainResults(queries, results, engineStr);
      }

      // 格式化 RAG 压缩结果
      final buffer = StringBuffer()
        ..writeln('Search queries: ${queries.map((q) => '"$q"').join(', ')}')
        ..writeln(
          'Found ${results.length} results, '
          'RAG-compressed to ${compressed.length} relevant sources:',
        )
        ..writeln();

      for (var i = 0; i < compressed.length; i++) {
        final r = compressed[i];
        buffer.writeln('[${i + 1}] [${r.title}](${r.url})');
        buffer.writeln('Relevance: ${(r.avgScore * 100).toStringAsFixed(1)}%');
        buffer.writeln(r.content);
        buffer.writeln();
      }

      buffer.writeln(
        'These results have been semantically filtered for relevance. '
        'Use [number](url) to cite sources in your answer. '
        'Use url_read for more details on specific pages.',
      );

      return ToolResult(
        output: buffer.toString(),
        success: true,
        metadata: {
          'queries': queries,
          'engine': engineStr,
          'count': results.length,
          'rag_compressed': true,
          'compressed_count': compressed.length,
          'urls': compressed.map((r) => r.url).toList(),
        },
      );
    } catch (e) {
      debugPrint('WebSearch: RAG compression failed: $e, falling back');
      return _formatPlainResults(queries, results, engineStr);
    }
  }


  /// 普通模式格式化 — 带可点击引用链接
  ToolResult _formatPlainResults(
    List<String> queries,
    List<SearchResult> results,
    String engineStr,
  ) {
    final engineName = switch (engineStr) {
      'bing' => 'Bing',
      'google' => 'Google',
      _ => 'DuckDuckGo',
    };

    final buffer = StringBuffer()
      ..writeln('Search queries: ${queries.map((q) => '"$q"').join(', ')}')
      ..writeln('Found ${results.length} results (via $engineName):')
      ..writeln();

    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('[${i + 1}] [${r.title}](${r.url})');
      buffer.writeln(r.snippet);
      buffer.writeln();
    }

    buffer.writeln(
      'Use [number](url) format to cite specific sources in your response. '
      'Use url_read for more details on specific pages.',
    );

    return ToolResult(
      output: buffer.toString(),
      success: true,
      metadata: {
        'queries': queries,
        'engine': engineStr,
        'count': results.length,
        'urls': results.map((r) => r.url).toList(),
      },
    );
  }
}
