/// WebSearchTool — AI 可调用的网络搜索工具
///
/// 通过 DuckDuckGo/Google/Bing 抓取搜索结果,让 AI 获取实时互联网信息。
/// 支持 Multi-Query：AI 可以同时提交多个查询词，系统并行搜索后去重合并。
///
/// 当启用 RAG 压缩且配置了 embedding 模型时：
/// 搜索 → 抓取全文 → 向量分块 → KNN 检索 → Round Robin → 合并

import 'dart:convert';

import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:baishou/agent/tools/search/html_to_markdown.dart';
import 'package:baishou/agent/tools/search/search_rag_service.dart';
import 'package:baishou/agent/tools/search/web_search_service.dart';
import 'package:baishou/agent/tools/tool_config_param.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class WebSearchTool extends AgentTool {
  static const _fetchTimeout = Duration(seconds: 12);

  @override
  String get id => 'web_search';

  @override
  String get displayName => t.agent.tools.web_search;

  @override
  String get category => 'search';

  @override
  IconData get icon => Icons.travel_explore_rounded;

  @override
  List<ToolConfigParam> get configurableParams => [
        ToolConfigParam(
          key: 'engine',
          label: t.agent.tools.param_search_engine,
          description: t.agent.tools.param_search_engine_desc,
          type: ParamType.select,
          defaultValue: 'tavily',
          options: ['tavily', 'bing', 'google'],
          icon: Icons.search,
        ),
        ToolConfigParam(
          key: 'max_results',
          label: t.agent.tools.param_max_results,
          description: t.agent.tools.param_max_results_desc,
          type: ParamType.integer,
          defaultValue: 5,
          min: 1,
          max: 10,
          icon: Icons.format_list_numbered,
        ),
        ToolConfigParam(
          key: 'rag_enabled',
          label: t.agent.tools.param_rag_enabled,
          description: t.agent.tools.param_rag_enabled_desc,
          type: ParamType.boolean,
          defaultValue: false,
          icon: Icons.auto_awesome,
        ),
        ToolConfigParam(
          key: 'tavily_api_key',
          label: t.agent.tools.param_tavily_api_key,
          description: t.agent.tools.param_tavily_api_key_desc,
          type: ParamType.string,
          defaultValue: '',
          icon: Icons.key,
        ),
      ];

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

    final engineStr = context.userConfig['engine'] as String? ?? 'tavily';
    final maxResults =
        (context.userConfig['max_results'] as num?)?.toInt() ?? 5;
    final ragEnabled = context.userConfig['rag_enabled'] as bool? ?? false;
    final tavilyApiKey = context.userConfig['tavily_api_key'] as String? ?? '';

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
          totalMaxResults: maxResults * 2,
          apiKey: tavilyApiKey,
        );
        debugPrint('WebSearch: primary engine $engineStr returned ${results.length} results');
        if (results.isEmpty) {
          throw Exception('Primary engine returned 0 results (possible anti-bot block)');
        }
      } catch (primaryError) {
        debugPrint('WebSearch: primary engine $engineStr failed: $primaryError');

        final fallbackEngines = [SearchEngine.tavily, SearchEngine.bing, SearchEngine.google]
            .where((e) => e != engine)
            .toList();

        for (final fallback in fallbackEngines) {
          try {
            debugPrint('WebSearch: trying fallback engine ${fallback.name}...');
            results = await WebSearchService.multiSearch(
              queries: queries,
              engine: fallback,
              maxResultsPerQuery: maxResults,
              totalMaxResults: maxResults * 2,
              apiKey: tavilyApiKey,
            );
            actualEngine = fallback.name;
            debugPrint('WebSearch: fallback ${fallback.name} returned ${results.length} results');
            if (results.isNotEmpty) break;
            throw Exception('Fallback engine returned 0 results');
          } catch (fallbackError) {
            debugPrint('WebSearch: fallback ${fallback.name} also failed: $fallbackError');
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
          metadata: {
            'queries': queries,
            'engine': actualEngine,
            'count': 0,
          },
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
      case 'google':
        return SearchEngine.google;
      case 'bing':
        return SearchEngine.bing;
      case 'tavily':
        return SearchEngine.tavily;
      default:
        return SearchEngine.tavily;
    }
  }

  /// RAG 压缩模式
  Future<ToolResult> _executeWithRag({
    required List<String> queries,
    required List<SearchResult> results,
    required ToolContext context,
    required String engineStr,
  }) async {
    debugPrint('WebSearch: RAG mode enabled, fetching full content...');

    // 2a. 并行抓取每个 URL 的全文
    final fetchFutures = results.map((r) => _fetchPageContent(r.url));
    final fetchedContents = await Future.wait(fetchFutures);

    // 组装 RAG 输入
    final ragInputs = <Map<String, String>>[];
    for (int i = 0; i < results.length; i++) {
      final r = results[i];
      final fullContent = fetchedContents[i];
      ragInputs.add({
        'title': r.title,
        'url': r.url,
        // 有全文用全文，否则用摘要
        'content': fullContent.isNotEmpty ? fullContent : r.snippet,
      });
    }

    final fetchedCount = fetchedContents.where((c) => c.isNotEmpty).length;
    debugPrint('WebSearch: fetched $fetchedCount/${results.length} pages');

    // 2b. RAG 压缩（使用第一个查询词作为主要语义锚）
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
        ..writeln(
          'Search queries: ${queries.map((q) => '"$q"').join(', ')}',
        )
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

  /// 抓取单个页面内容并转 Markdown
  Future<String> _fetchPageContent(String url) async {
    try {
      final uri = Uri.parse(url);
      final response = await http
          .get(uri, headers: _browserHeaders)
          .timeout(_fetchTimeout);

      if (response.statusCode != 200) return '';

      final html = utf8.decode(response.bodyBytes, allowMalformed: true);

      // 提取 <article> / <main> / <body>
      String bodyHtml = html;
      final articleMatch = RegExp(
        r'<(article|main)[^>]*>(.*?)</\1>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(html);
      if (articleMatch != null) {
        bodyHtml = articleMatch.group(2) ?? html;
      } else {
        final bodyMatch = RegExp(
          r'<body[^>]*>(.*?)</body>',
          dotAll: true,
          caseSensitive: false,
        ).firstMatch(html);
        if (bodyMatch != null) {
          bodyHtml = bodyMatch.group(1) ?? html;
        }
      }

      final markdown = HtmlToMarkdownConverter.convert(bodyHtml);
      // 限制每个页面内容（避免 embedding 请求过多）
      if (markdown.length > 6000) {
        return markdown.substring(0, 6000);
      }
      return markdown;
    } catch (e) {
      debugPrint('WebSearch: fetch failed for $url: $e');
      return '';
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
      ..writeln(
        'Search queries: ${queries.map((q) => '"$q"').join(', ')}',
      )
      ..writeln(
        'Found ${results.length} results (via $engineName):',
      )
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

  static Map<String, String> get _browserHeaders => {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };
}
