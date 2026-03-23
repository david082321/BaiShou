/// WebSearchTool — AI 可调用的网络搜索工具
///
/// 通过 Google/Bing 抓取搜索结果,让 AI 获取实时互联网信息。
/// 搜索引擎可通过工具配置参数切换。
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
          defaultValue: 'bing',
          options: ['google', 'bing'],
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
      ];

  @override
  String get description =>
      'Search the internet for current information, news, and real-time data. '
      'Use this when the user asks about recent events, current facts, or anything '
      'that requires up-to-date information beyond your training data. '
      'Results include URLs — use the url_read tool to read specific pages in detail.';

  @override
  Map<String, dynamic> get parameterSchema => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'The search query. Use clear, specific keywords for best results.',
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
    if (query == null || query.trim().isEmpty) {
      return ToolResult.error('Missing required parameter: query');
    }

    final engineStr = context.userConfig['engine'] as String? ?? 'google';
    final maxResults =
        (context.userConfig['max_results'] as num?)?.toInt() ?? 5;
    final ragEnabled = context.userConfig['rag_enabled'] as bool? ?? false;

    final engine =
        engineStr == 'bing' ? SearchEngine.bing : SearchEngine.google;

    try {
      // ── 步骤 1: 搜索 ──
      final results = await WebSearchService.search(
        query: query.trim(),
        engine: engine,
        maxResults: maxResults,
      );

      if (results.isEmpty) {
        return ToolResult(
          output: 'No search results found for "$query".',
          success: true,
          metadata: {'query': query, 'engine': engineStr, 'count': 0},
        );
      }

      // ── 步骤 2: RAG 压缩（可选） ──
      if (ragEnabled &&
          context.embeddingService != null &&
          context.embeddingService!.isConfigured) {
        return _executeWithRag(
          query: query,
          results: results,
          context: context,
          engineStr: engineStr,
        );
      }

      // ── 普通模式：直接返回摘要 ──
      return _formatPlainResults(query, results, engineStr);
    } catch (e) {
      return ToolResult.error('Web search failed: $e');
    }
  }

  /// RAG 压缩模式
  Future<ToolResult> _executeWithRag({
    required String query,
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

    // 2b. RAG 压缩
    try {
      final compressed = await SearchRagService.compress(
        query: query,
        results: ragInputs,
        embeddingService: context.embeddingService!,
        totalMaxChunks: 12,
        maxChunksPerSource: 4,
      );

      if (compressed.isEmpty) {
        debugPrint('WebSearch: RAG returned empty, falling back to plain');
        return _formatPlainResults(query, results, engineStr);
      }

      // 格式化 RAG 压缩结果
      final buffer = StringBuffer()
        ..writeln(
          'Found ${results.length} results for "$query", '
          'RAG-compressed to ${compressed.length} relevant sources:',
        )
        ..writeln();

      for (var i = 0; i < compressed.length; i++) {
        final r = compressed[i];
        buffer.writeln('[${i + 1}] ${r.title}');
        buffer.writeln('URL: ${r.url}');
        buffer.writeln('Relevance: ${(r.avgScore * 100).toStringAsFixed(1)}%');
        buffer.writeln(r.content);
        buffer.writeln();
      }

      buffer.writeln(
        'These results have been semantically filtered for relevance. '
        'Use [number] to cite sources. '
        'Use url_read for more details on specific pages.',
      );

      return ToolResult(
        output: buffer.toString(),
        success: true,
        metadata: {
          'query': query,
          'engine': engineStr,
          'count': results.length,
          'rag_compressed': true,
          'compressed_count': compressed.length,
          'urls': compressed.map((r) => r.url).toList(),
        },
      );
    } catch (e) {
      debugPrint('WebSearch: RAG compression failed: $e, falling back');
      return _formatPlainResults(query, results, engineStr);
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

  /// 普通模式格式化
  ToolResult _formatPlainResults(
    String query,
    List<SearchResult> results,
    String engineStr,
  ) {
    final buffer = StringBuffer()
      ..writeln(
        'Found ${results.length} results for "$query" '
        '(via ${engineStr == "bing" ? "Bing" : "Google"}):',
      )
      ..writeln();

    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      buffer.writeln('[${i + 1}] ${r.title}');
      buffer.writeln('URL: ${r.url}');
      buffer.writeln(r.snippet);
      buffer.writeln();
    }

    buffer.writeln(
      'Use [number] format to cite specific sources in your response.',
    );

    return ToolResult(
      output: buffer.toString(),
      success: true,
      metadata: {
        'query': query,
        'engine': engineStr,
        'count': results.length,
        'urls': results.map((r) => r.url).toList(),
      },
    );
  }

  static const _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };
}
