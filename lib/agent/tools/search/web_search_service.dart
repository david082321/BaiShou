/// Web 搜索服务 — 负责执行搜索并解析结果
///
/// 支持引擎：Tavily、DuckDuckGo
///
/// SOLID: 单一职责 — 仅处理搜索请求和 HTML 解析

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show visibleForTesting;
import 'package:http/http.dart' as http;

/// 单条搜索结果
class SearchResult {
  final String title;
  final String url;
  final String snippet;

  const SearchResult({
    required this.title,
    required this.url,
    required this.snippet,
  });

  @override
  String toString() => '[$title]($url)\n$snippet';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SearchResult && runtimeType == other.runtimeType && url == other.url;

  @override
  int get hashCode => url.hashCode;
}

/// 支持的搜索引擎
enum SearchEngine { tavily, duckduckgo }

/// Web 搜索服务
class WebSearchService {
  static const _defaultMaxResults = 5;
  static const _timeout = Duration(seconds: 15);

  /// 随机 User-Agent 池 — 降低被反爬拦截的概率
  static final _userAgentPool = [
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:133.0) Gecko/20100101 Firefox/133.0',
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 14.7; rv:133.0) Gecko/20100101 Firefox/133.0',
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0',
  ];

  static final _random = Random();

  /// 获取随机浏览器请求头
  static Map<String, String> get _browserHeaders => {
    'User-Agent': _userAgentPool[_random.nextInt(_userAgentPool.length)],
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
    'Accept-Encoding': 'gzip, deflate',
    'DNT': '1',
    'Connection': 'keep-alive',
    'Upgrade-Insecure-Requests': '1',
  };

  /// 执行单引擎搜索
  static Future<List<SearchResult>> search({
    required String query,
    required SearchEngine engine,
    int maxResults = _defaultMaxResults,
    String? apiKey,
  }) async {
    switch (engine) {
      case SearchEngine.duckduckgo:
        return _searchDuckDuckGo(query, maxResults);
      case SearchEngine.tavily:
        return _searchTavily(query, maxResults, apiKey ?? '');
    }
  }

  /// Multi-Query 搜索 — 并行执行多个查询词并去重合并
  ///
  /// AI 可以同时提交多个不同侧重点的关键词，
  /// 系统会并行抓取、去重（按 URL）后返回合并结果，
  /// 极大地丰富了单次搜索的信息广度。
  static Future<List<SearchResult>> multiSearch({
    required List<String> queries,
    required SearchEngine engine,
    int maxResultsPerQuery = 5,
    int totalMaxResults = 10,
    String? apiKey,
  }) async {
    if (queries.isEmpty) return [];

    // 单查询退化为普通搜索
    if (queries.length == 1) {
      return search(
        query: queries.first,
        engine: engine,
        maxResults: totalMaxResults,
        apiKey: apiKey,
      );
    }

    debugPrint('WebSearch: multi-query with ${queries.length} queries via ${engine.name}');

    // 并行执行所有查询
    final futures = queries.map(
      (q) => search(query: q, engine: engine, maxResults: maxResultsPerQuery, apiKey: apiKey),
    );
    final allResults = await Future.wait(futures);

    // 按 URL 去重，保留先出现的（排名更高的优先）
    final seen = <String>{};
    final merged = <SearchResult>[];

    for (final results in allResults) {
      for (final r in results) {
        if (!seen.contains(r.url)) {
          seen.add(r.url);
          merged.add(r);
        }
      }
    }

    debugPrint('WebSearch: multi-query merged ${merged.length} unique results');

    // 截断到总上限
    if (merged.length > totalMaxResults) {
      return merged.sublist(0, totalMaxResults);
    }
    return merged;
  }

  // ── Tavily API 搜索 ───────────────────────────────────────

  /// Tavily 搜索 — 通过 REST API 获取结构化 JSON 结果
  static Future<List<SearchResult>> _searchTavily(
    String query,
    int maxResults,
    String apiKey,
  ) async {
    if (apiKey.isEmpty) {
      throw Exception('Tavily API key is required');
    }

    final uri = Uri.parse('https://api.tavily.com/search');

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode({
        'query': query,
        'max_results': maxResults,
        'search_depth': 'basic',
        'include_answer': false,
      }),
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('Tavily search failed: ${response.statusCode} ${response.body}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    return parseTavilyResults(data, maxResults);
  }

  /// 解析 Tavily API JSON 响应
  @visibleForTesting
  static List<SearchResult> parseTavilyResults(Map<String, dynamic> json, int maxResults) {
    final results = <SearchResult>[];
    final rawResults = json['results'] as List? ?? [];

    for (final item in rawResults) {
      if (results.length >= maxResults) break;

      final map = item as Map<String, dynamic>;
      final title = (map['title'] as String?) ?? '';
      final url = (map['url'] as String?) ?? '';
      final content = (map['content'] as String?) ?? '';

      if (title.isNotEmpty && url.isNotEmpty) {
        results.add(SearchResult(title: title, url: url, snippet: content));
      }
    }

    return results;
  }

  // ── DuckDuckGo 搜索 ────────────────────────────────────────

  /// DuckDuckGo 搜索 — 通过 html.duckduckgo.com 抓取
  static Future<List<SearchResult>> _searchDuckDuckGo(
    String query,
    int maxResults,
  ) async {
    final uri = Uri.https('html.duckduckgo.com', '/html/', {
      'q': query,
    });

    final response = await http.get(uri, headers: _browserHeaders).timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('DuckDuckGo search failed: ${response.statusCode}');
    }

    final html = utf8.decode(response.bodyBytes);
    return parseDuckDuckGoResults(html, maxResults);
  }

  /// 解析 DuckDuckGo 搜索结果 HTML
  @visibleForTesting
  static List<SearchResult> parseDuckDuckGoResults(String html, int maxResults) {
    final results = <SearchResult>[];

    // Split by the start of each result title to isolate blocks and prevent catastrophic backtracking
    final blocks = html.split('class="result__title"');

    for (int i = 1; i < blocks.length; i++) {
      if (results.length >= maxResults) break;
      final block = blocks[i];

      // Find URL and Title anchor tag
      final aTagStart = block.indexOf('<a');
      if (aTagStart == -1) continue;
      final aTagEnd = block.indexOf('</a>', aTagStart);
      if (aTagEnd == -1) continue;

      final aTag = block.substring(aTagStart, aTagEnd + 4);
      final hrefMatch = RegExp(r'href="([^"]+)"').firstMatch(aTag);
      final rawUrl = hrefMatch?.group(1) ?? '';

      final titleMatch = RegExp(r'>(.*?)</a>', dotAll: true).firstMatch(aTag);
      final title = stripHtml(titleMatch?.group(1) ?? '').trim();

      // Find Snippet anchor tag
      final snippetStart = block.indexOf('class="result__snippet"');
      String snippet = '';
      if (snippetStart != -1) {
        final snippetEnd = block.indexOf('</a>', snippetStart);
        if (snippetEnd != -1) {
          final snippetTag = block.substring(snippetStart, snippetEnd + 4);
          final snippetMatch = RegExp(r'>(.*?)</a>', dotAll: true).firstMatch(snippetTag);
          final snippetHtml = snippetMatch?.group(1) ?? '';
          snippet = stripHtml(snippetHtml).replaceAll(RegExp(r'\s+'), ' ').trim();
        }
      }

      // DuckDuckGo redirects urls via uddg parameter (e.g. //duckduckgo.com/l/?uddg=...)
      String actualUrl = rawUrl;
      try {
        final uri = Uri.parse(rawUrl.startsWith('//') ? 'https:' + rawUrl : rawUrl);
        if (uri.queryParameters.containsKey('uddg')) {
          final decodedUddg = Uri.decodeComponent(uri.queryParameters['uddg']!);
          actualUrl = decodedUddg;
        }
      } catch (e) {
        // Fallback to raw url
      }

      if (actualUrl.isEmpty || title.isEmpty || snippet.length <= 10) continue;
      results.add(SearchResult(title: title, url: actualUrl, snippet: snippet));
    }

    return results;
  }

  // ── 工具方法 ────────────────────────────────────────────────

  /// 移除 HTML 标签
  @visibleForTesting
  static String stripHtml(String html) {
    return html
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
  }
}

