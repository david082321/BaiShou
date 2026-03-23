/// Web 搜索服务 — 负责执行 Google/Bing 搜索并解析结果
///
/// SOLID: 单一职责 — 仅处理搜索请求和HTML解析

import 'dart:convert';
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
}

/// 支持的搜索引擎
enum SearchEngine { google, bing }

/// Web 搜索服务
class WebSearchService {
  static const _defaultMaxResults = 5;
  static const _timeout = Duration(seconds: 15);

  /// 执行搜索
  static Future<List<SearchResult>> search({
    required String query,
    SearchEngine engine = SearchEngine.google,
    int maxResults = _defaultMaxResults,
  }) async {
    switch (engine) {
      case SearchEngine.google:
        return _searchGoogle(query, maxResults);
      case SearchEngine.bing:
        return _searchBing(query, maxResults);
    }
  }

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

  /// 解析 Google 搜索结果 HTML
  static List<SearchResult> _parseGoogleResults(String html, int maxResults) {
    final results = <SearchResult>[];

    // Google 结果在 <div class="g"> 或类似结构中
    // 使用正则提取 <a href="..."><h3>title</h3></a> 和摘要
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

  /// 解析 Bing 搜索结果 HTML
  static List<SearchResult> _parseBingResults(String html, int maxResults) {
    final results = <SearchResult>[];

    // Bing 结果在 <li class="b_algo"> 中
    // <h2><a href="url">title</a></h2>
    // <p class="b_lineclamp...">snippet</p>
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

  /// 模拟浏览器请求头
  static const _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };
}
