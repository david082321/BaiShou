/// Web 搜索服务 — 负责执行搜索并解析结果
///
/// 支持引擎：DuckDuckGo Lite（默认推荐）、Google、Bing
/// 支持 Multi-Query：并行多个查询词后去重合并
///
/// SOLID: 单一职责 — 仅处理搜索请求和 HTML 解析

import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
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
enum SearchEngine { duckduckgo, google, bing }

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
  }) async {
    switch (engine) {
      case SearchEngine.duckduckgo:
        return _searchDuckDuckGo(query, maxResults);
      case SearchEngine.google:
        return _searchGoogle(query, maxResults);
      case SearchEngine.bing:
        return _searchBing(query, maxResults);
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
  }) async {
    if (queries.isEmpty) return [];

    // 单查询退化为普通搜索
    if (queries.length == 1) {
      return search(
        query: queries.first,
        engine: engine,
        maxResults: totalMaxResults,
      );
    }

    debugPrint('WebSearch: multi-query with ${queries.length} queries via ${engine.name}');

    // 并行执行所有查询
    final futures = queries.map(
      (q) => search(query: q, engine: engine, maxResults: maxResultsPerQuery),
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

  // ── DuckDuckGo Lite 搜索 ────────────────────────────────────

  /// DuckDuckGo Lite — 纯 HTML 轻量版，无 JS、无验证码
  ///
  /// 这是最稳定的免代理搜索源：
  /// - 不需要 API Key
  /// - 不需要执行 JavaScript
  /// - 极少被反爬拦截
  static Future<List<SearchResult>> _searchDuckDuckGo(
    String query,
    int maxResults,
  ) async {
    final uri = Uri.https('lite.duckduckgo.com', '/lite/', {
      'q': query,
    });

    // DuckDuckGo Lite 使用 POST 请求
    final response = await http.post(
      uri,
      headers: _browserHeaders,
      body: {'q': query},
    ).timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('DuckDuckGo search failed: ${response.statusCode}');
    }

    final html = utf8.decode(response.bodyBytes, allowMalformed: true);
    return _parseDuckDuckGoResults(html, maxResults);
  }

  /// 解析 DuckDuckGo Lite 搜索结果 HTML
  ///
  /// DuckDuckGo Lite 的 HTML 结构非常简洁：
  /// - 结果标题在 <a class="result-link" href="..."> 中
  /// - 摘要在紧随的 <td class="result-snippet"> 中
  static List<SearchResult> _parseDuckDuckGoResults(String html, int maxResults) {
    final results = <SearchResult>[];

    // DuckDuckGo Lite 的结构：
    // <a rel="nofollow" href="URL" class="result-link">Title</a>
    // 紧随其后的 <td class="result-snippet">Snippet</td>
    final linkPattern = RegExp(
      r'<a[^>]+class="result-link"[^>]+href="([^"]+)"[^>]*>(.*?)</a>',
      dotAll: true,
      caseSensitive: false,
    );

    final snippetPattern = RegExp(
      r'<td\s+class="result-snippet"[^>]*>(.*?)</td>',
      dotAll: true,
      caseSensitive: false,
    );

    final linkMatches = linkPattern.allMatches(html).toList();
    final snippetMatches = snippetPattern.allMatches(html).toList();

    for (int i = 0; i < linkMatches.length && results.length < maxResults; i++) {
      final url = _decodeEntities(linkMatches[i].group(1) ?? '');
      final title = _stripHtml(linkMatches[i].group(2) ?? '');

      // 跳过非 HTTP 链接
      if (!url.startsWith('http')) continue;
      if (title.isEmpty) continue;

      // 尝试匹配相应的摘要
      String snippet = '';
      if (i < snippetMatches.length) {
        snippet = _stripHtml(snippetMatches[i].group(1) ?? '');
      }

      results.add(SearchResult(title: title, url: url, snippet: snippet));
    }

    return results;
  }

  // ── Google 搜索 ─────────────────────────────────────────────

  /// Google 搜索 — 通过 google.com/search 抓取
  static Future<List<SearchResult>> _searchGoogle(
    String query,
    int maxResults,
  ) async {
    final uri = Uri.https('www.google.com', '/search', {
      'q': query,
      'num': maxResults.toString(),
      'hl': 'zh-CN',
    });

    final response = await http.get(uri, headers: _browserHeaders).timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('Google search failed: ${response.statusCode}');
    }

    final html = utf8.decode(response.bodyBytes);
    return _parseGoogleResults(html, maxResults);
  }

  /// 解析 Google 搜索结果 HTML
  static List<SearchResult> _parseGoogleResults(String html, int maxResults) {
    final results = <SearchResult>[];

    final linkPattern = RegExp(
      r'<a[^>]+href="(https?://[^"]+)"[^>]*><h3[^>]*>(.*?)</h3>',
      dotAll: true,
    );

    final matches = linkPattern.allMatches(html);
    for (final match in matches) {
      if (results.length >= maxResults) break;

      final url = match.group(1) ?? '';
      final rawTitle = match.group(2) ?? '';
      final title = _stripHtml(rawTitle);

      // 跳过 Google 自身的链接
      if (url.contains('google.com') || title.isEmpty) continue;

      // 尝试找相邻的摘要文本
      final snippetStart = match.end;
      final snippetEnd = (snippetStart + 500).clamp(0, html.length);
      final snippetRegion = html.substring(snippetStart, snippetEnd);
      final snippetMatch = RegExp(r'<span[^>]*>(.*?)</span>', dotAll: true)
          .firstMatch(snippetRegion);
      final snippet = snippetMatch != null
          ? _stripHtml(snippetMatch.group(1) ?? '')
          : '';

      if (snippet.length > 10) {
        results.add(SearchResult(title: title, url: url, snippet: snippet));
      }
    }

    return results;
  }

  // ── Bing 搜索 ──────────────────────────────────────────────

  /// Bing 搜索 — 通过 bing.com/search 抓取
  static Future<List<SearchResult>> _searchBing(
    String query,
    int maxResults,
  ) async {
    final uri = Uri.https('www.bing.com', '/search', {
      'q': query,
      'count': maxResults.toString(),
      'ensearch': '1',
    });

    final response = await http.get(uri, headers: _browserHeaders).timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception('Bing search failed: ${response.statusCode}');
    }

    final html = utf8.decode(response.bodyBytes);
    return _parseBingResults(html, maxResults);
  }

  /// 解析 Bing 搜索结果 HTML
  static List<SearchResult> _parseBingResults(String html, int maxResults) {
    final results = <SearchResult>[];

    final blockPattern = RegExp(
      r'<li class="b_algo">(.*?)</li>',
      dotAll: true,
    );

    for (final blockMatch in blockPattern.allMatches(html)) {
      if (results.length >= maxResults) break;

      final block = blockMatch.group(1) ?? '';

      final linkMatch = RegExp(
        r'<a[^>]+href="(https?://[^"]+)"[^>]*>(.*?)</a>',
        dotAll: true,
      ).firstMatch(block);

      if (linkMatch == null) continue;

      final url = linkMatch.group(1) ?? '';
      final title = _stripHtml(linkMatch.group(2) ?? '');

      // 提取摘要
      final snippetMatch = RegExp(
        r'<p[^>]*>(.*?)</p>',
        dotAll: true,
      ).firstMatch(block);
      final snippet = snippetMatch != null
          ? _stripHtml(snippetMatch.group(1) ?? '')
          : '';

      if (title.isNotEmpty && snippet.length > 10) {
        results.add(SearchResult(title: title, url: url, snippet: snippet));
      }
    }

    return results;
  }

  // ── 工具方法 ────────────────────────────────────────────────

  /// 移除 HTML 标签
  static String _stripHtml(String html) {
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

  /// 解码 HTML 实体
  static String _decodeEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
  }
}
