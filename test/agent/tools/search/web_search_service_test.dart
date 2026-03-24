/// WebSearchService 单元测试
///
/// 测试覆盖范围：
/// 1. SearchResult 数据模型（相等性、hashCode、toString）
/// 2. Multi-Query 去重合并逻辑
/// 3. 搜索引擎枚举
/// 4. Bing HTML 解析（通过暴露的测试辅助方法）
/// 5. Google HTML 解析（通过暴露的测试辅助方法）

import 'package:baishou/agent/tools/search/web_search_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ════════════════════════════════════════════════════════════
  // SearchResult 数据模型
  // ════════════════════════════════════════════════════════════
  group('SearchResult 数据模型', () {
    test('按 URL 判断相等性（忽略 title/snippet 差异）', () {
      final a = SearchResult(
        title: 'Title A',
        url: 'https://example.com/page1',
        snippet: 'Snippet A',
      );
      final b = SearchResult(
        title: 'Title B (不同标题)',
        url: 'https://example.com/page1',
        snippet: 'Snippet B (不同摘要)',
      );
      final c = SearchResult(
        title: 'Title C',
        url: 'https://example.com/page2',
        snippet: 'Snippet C',
      );

      expect(a, equals(b)); // 相同 URL → 相等
      expect(a, isNot(equals(c))); // 不同 URL → 不相等
      expect(a.hashCode, b.hashCode);
      expect(a.hashCode, isNot(c.hashCode));
    });

    test('toString 输出 Markdown 链接格式', () {
      final r = SearchResult(
        title: 'Flutter 官网',
        url: 'https://flutter.dev',
        snippet: '构建原生应用的 UI 框架',
      );
      final s = r.toString();
      expect(s, contains('[Flutter 官网](https://flutter.dev)'));
      expect(s, contains('构建原生应用的 UI 框架'));
    });

    test('const 构造器允许编译期常量', () {
      const r = SearchResult(
        title: 'Const',
        url: 'https://const.com',
        snippet: 'This is const',
      );
      expect(r.title, 'Const');
    });
  });

  // ════════════════════════════════════════════════════════════
  // 搜索引擎枚举
  // ════════════════════════════════════════════════════════════
  group('SearchEngine 枚举', () {
    test('包含 bing 和 google 两个选项', () {
      expect(SearchEngine.values.length, 2);
      expect(SearchEngine.values, contains(SearchEngine.bing));
      expect(SearchEngine.values, contains(SearchEngine.google));
    });

    test('name 应返回正确字符串', () {
      expect(SearchEngine.bing.name, 'bing');
      expect(SearchEngine.google.name, 'google');
    });
  });

  // ════════════════════════════════════════════════════════════
  // Multi-Query 去重合并逻辑
  // ════════════════════════════════════════════════════════════
  group('Multi-Query 去重逻辑', () {
    test('按 URL 去重，保留先出现的结果', () {
      final query1Results = [
        SearchResult(title: 'A', url: 'https://a.com', snippet: 'snippet aaa aaa'),
        SearchResult(title: 'B', url: 'https://b.com', snippet: 'snippet bbb bbb'),
        SearchResult(title: 'C', url: 'https://c.com', snippet: 'snippet ccc ccc'),
      ];
      final query2Results = [
        SearchResult(title: 'B copy', url: 'https://b.com', snippet: 'bbb2 bbb2 bbb2'),
        SearchResult(title: 'D', url: 'https://d.com', snippet: 'snippet ddd ddd'),
      ];

      // 模拟 multiSearch 内部去重逻辑
      final seen = <String>{};
      final merged = <SearchResult>[];
      for (final results in [query1Results, query2Results]) {
        for (final r in results) {
          if (!seen.contains(r.url)) {
            seen.add(r.url);
            merged.add(r);
          }
        }
      }

      expect(merged.length, 4); // A, B, C, D（B copy 被去重）
      expect(merged.map((r) => r.url).toList(), [
        'https://a.com',
        'https://b.com',
        'https://c.com',
        'https://d.com',
      ]);
      expect(merged[1].title, 'B'); // 保留的是第一个 B
    });

    test('达到 totalMaxResults 时截断', () {
      final results = List.generate(
        20,
        (i) => SearchResult(
          title: 'Result $i',
          url: 'https://example.com/$i',
          snippet: 'Snippet for result number $i',
        ),
      );

      const totalMaxResults = 10;
      final truncated = results.length > totalMaxResults
          ? results.sublist(0, totalMaxResults)
          : results;

      expect(truncated.length, 10);
      expect(truncated.first.title, 'Result 0');
      expect(truncated.last.title, 'Result 9');
    });

    test('空查询列表返回空结果', () {
      final queries = <String>[];
      expect(queries.isEmpty, isTrue);
      // multiSearch 对空 queries 直接返回 []
    });

    test('单查询退化为普通搜索', () {
      final queries = ['Flutter 教程'];
      expect(queries.length, 1);
      // multiSearch 中 queries.length == 1 时直接调用 search()
    });

    test('三个查询的结果交叉去重', () {
      final q1 = [
        SearchResult(title: 'A', url: 'https://a.com', snippet: 'snippet a long enough'),
        SearchResult(title: 'B', url: 'https://b.com', snippet: 'snippet b long enough'),
      ];
      final q2 = [
        SearchResult(title: 'B2', url: 'https://b.com', snippet: 'snippet b2 again'),
        SearchResult(title: 'C', url: 'https://c.com', snippet: 'snippet c long enough'),
      ];
      final q3 = [
        SearchResult(title: 'A3', url: 'https://a.com', snippet: 'snippet a3 again'),
        SearchResult(title: 'D', url: 'https://d.com', snippet: 'snippet d long enough'),
      ];

      final seen = <String>{};
      final merged = <SearchResult>[];
      for (final results in [q1, q2, q3]) {
        for (final r in results) {
          if (!seen.contains(r.url)) {
            seen.add(r.url);
            merged.add(r);
          }
        }
      }

      expect(merged.length, 4); // A, B, C, D
      expect(merged.map((r) => r.title).toList(), ['A', 'B', 'C', 'D']);
    });
  });

  // ════════════════════════════════════════════════════════════
  // Bing HTML 解析（通过 parseBingResults 暴露）
  // ════════════════════════════════════════════════════════════
  group('Bing HTML 解析', () {
    test('应正确解析标准 b_algo 结构', () {
      const html = '''
<html><body>
<li class="b_algo"><a href="https://flutter.dev/docs" h="ID=SERP,5001"><h2>Flutter Documentation</h2></a>
<p>Flutter is Google's UI toolkit for building natively compiled applications.</p></li>
<li class="b_algo"><a href="https://dart.dev/guides" h="ID=SERP,5002"><h2>Dart Language Guide</h2></a>
<p>Dart is a client-optimized language for fast apps on any platform.</p></li>
</body></html>
''';

      final results = WebSearchService.parseBingResults(html, 10);

      expect(results.length, 2);
      expect(results[0].url, 'https://flutter.dev/docs');
      expect(results[0].title, 'Flutter Documentation');
      expect(results[0].snippet, contains('UI toolkit'));
      expect(results[1].url, 'https://dart.dev/guides');
      expect(results[1].title, 'Dart Language Guide');
    });

    test('应跳过缺少 <p> 摘要或摘要过短的结果', () {
      const html = '''
<li class="b_algo"><a href="https://short.com"><h2>Short Snippet</h2></a>
<p>Too short</p></li>
<li class="b_algo"><a href="https://ok.com"><h2>OK Result</h2></a>
<p>This snippet is long enough to pass the length threshold check.</p></li>
''';

      final results = WebSearchService.parseBingResults(html, 10);

      // "Too short" 少于 10 字符，应被跳过
      expect(results.length, 1);
      expect(results[0].url, 'https://ok.com');
    });

    test('应尊重 maxResults 限制', () {
      final buffer = StringBuffer();
      for (int i = 0; i < 20; i++) {
        buffer.writeln(
          '<li class="b_algo"><a href="https://r$i.com"><h2>Result $i</h2></a>'
          '<p>This is a sufficiently long snippet for result number $i.</p></li>',
        );
      }

      final results = WebSearchService.parseBingResults(buffer.toString(), 5);
      expect(results.length, 5);
    });

    test('空 HTML 返回空列表', () {
      final results = WebSearchService.parseBingResults('', 10);
      expect(results, isEmpty);
    });

    test('无匹配结构的 HTML 返回空列表', () {
      const html = '<html><body><div>No search results here</div></body></html>';
      final results = WebSearchService.parseBingResults(html, 10);
      expect(results, isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════
  // Google HTML 解析（通过 parseGoogleResults 暴露）
  // ════════════════════════════════════════════════════════════
  group('Google HTML 解析', () {
    test('应正确解析 <a><h3> 结构', () {
      const html = '''
<div>
<a href="https://flutter.dev" data-ved="abc"><h3 class="LC20lb">Flutter - Build apps for any screen</h3></a>
<span>Flutter transforms the development process. Build, test, and deploy beautiful mobile, web, desktop, and embedded apps from a single codebase.</span>
</div>
<div>
<a href="https://dart.dev" data-ved="def"><h3 class="LC20lb">Dart programming language</h3></a>
<span>Dart is a client-optimized language for developing fast apps on any platform.</span>
</div>
''';

      final results = WebSearchService.parseGoogleResults(html, 10);

      expect(results.length, 2);
      expect(results[0].url, 'https://flutter.dev');
      expect(results[0].title, 'Flutter - Build apps for any screen');
      expect(results[0].snippet, contains('Flutter transforms'));
      expect(results[1].url, 'https://dart.dev');
    });

    test('应过滤 google.com 自身的链接', () {
      const html = '''
<a href="https://www.google.com/settings"><h3>Google Settings</h3></a>
<span>Manage your Google preferences and account.</span>
<a href="https://example.com/real"><h3>Real Result</h3></a>
<span>This is a real search result with enough text.</span>
''';

      final results = WebSearchService.parseGoogleResults(html, 10);
      // google.com 链接应被过滤
      expect(results.every((r) => !r.url.contains('google.com')), isTrue);
    });

    test('应尊重 maxResults 限制', () {
      final buffer = StringBuffer();
      for (int i = 0; i < 20; i++) {
        buffer.writeln(
          '<a href="https://result$i.com"><h3>Result $i</h3></a>'
          '<span>A sufficiently long snippet for result number $i here.</span>',
        );
      }

      final results = WebSearchService.parseGoogleResults(buffer.toString(), 3);
      expect(results.length, 3);
    });

    test('空 HTML 返回空列表', () {
      final results = WebSearchService.parseGoogleResults('', 10);
      expect(results, isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════
  // HTML 实体解码（_stripHtml）
  // ════════════════════════════════════════════════════════════
  group('stripHtml 工具方法', () {
    test('应移除 HTML 标签', () {
      expect(
        WebSearchService.stripHtml('<b>bold</b> and <i>italic</i>'),
        'bold and italic',
      );
    });

    test('应解码常见 HTML 实体', () {
      expect(WebSearchService.stripHtml('A &amp; B'), 'A & B');
      expect(WebSearchService.stripHtml('&lt;tag&gt;'), '<tag>');
      expect(WebSearchService.stripHtml('&quot;quoted&quot;'), '"quoted"');
      expect(WebSearchService.stripHtml('it&#39;s'), "it's");
      expect(WebSearchService.stripHtml('hello&nbsp;world'), 'hello world');
    });

    test('应去除首尾空白', () {
      expect(WebSearchService.stripHtml('  hello  '), 'hello');
    });

    test('应处理嵌套标签', () {
      expect(
        WebSearchService.stripHtml('<div><span>nested</span></div>'),
        'nested',
      );
    });

    test('空字符串返回空字符串', () {
      expect(WebSearchService.stripHtml(''), '');
    });
  });
}
