/// HTML → Markdown 转换服务
///
/// SOLID: 单一职责 — 仅处理 HTML 到纯文本/Markdown 的转换
/// 轻量级实现，无需重型依赖

class HtmlToMarkdownConverter {
  /// 将 HTML 转换为 Markdown 格式
  static String convert(String html) {
    var result = html;

    // 1. 移除 script/style/nav/footer 等非内容块
    result = result.replaceAll(
      RegExp(r'<(script|style|nav|footer|header|noscript|iframe|svg)[^>]*>.*?</\1>',
          dotAll: true, caseSensitive: false),
      '',
    );

    // 2. 处理 <head> 区块（完全移除）
    result = result.replaceAll(
      RegExp(r'<head[^>]*>.*?</head>', dotAll: true, caseSensitive: false),
      '',
    );

    // 3. 标题标签 → Markdown 标题
    for (int i = 6; i >= 1; i--) {
      result = result.replaceAllMapped(
        RegExp('<h$i[^>]*>(.*?)</h$i>', dotAll: true, caseSensitive: false),
        (m) => '\n${'#' * i} ${_stripTags(m.group(1) ?? '')}\n',
      );
    }

    // 4. 段落和换行
    result = result.replaceAllMapped(
      RegExp(r'<p[^>]*>(.*?)</p>', dotAll: true, caseSensitive: false),
      (m) => '\n${_stripTags(m.group(1) ?? '')}\n',
    );
    result = result.replaceAll(
      RegExp(r'<br\s*/?>',  caseSensitive: false),
      '\n',
    );
    result = result.replaceAll(
      RegExp(r'<div[^>]*>', caseSensitive: false),
      '\n',
    );

    // 5. 粗体和斜体
    result = result.replaceAllMapped(
      RegExp(r'<(strong|b)[^>]*>(.*?)</\1>', dotAll: true, caseSensitive: false),
      (m) => '**${m.group(2) ?? ''}**',
    );
    result = result.replaceAllMapped(
      RegExp(r'<(em|i)[^>]*>(.*?)</\1>', dotAll: true, caseSensitive: false),
      (m) => '*${m.group(2) ?? ''}*',
    );

    // 6. 链接 → [text](url)
    result = result.replaceAllMapped(
      RegExp(r'<a[^>]+href="([^"]*)"[^>]*>(.*?)</a>',
          dotAll: true, caseSensitive: false),
      (m) {
        final url = m.group(1) ?? '';
        final text = _stripTags(m.group(2) ?? '');
        if (url.isEmpty || text.isEmpty) return text;
        return '[$text]($url)';
      },
    );

    // 7. 图片 → ![alt](src)
    result = result.replaceAllMapped(
      RegExp(r'<img[^>]+src="([^"]*)"[^>]*(?:alt="([^"]*)")?[^>]*/?>',
          caseSensitive: false),
      (m) {
        final src = m.group(1) ?? '';
        final alt = m.group(2) ?? '';
        return '![$alt]($src)';
      },
    );

    // 8. 无序列表
    result = result.replaceAllMapped(
      RegExp(r'<li[^>]*>(.*?)</li>', dotAll: true, caseSensitive: false),
      (m) => '- ${_stripTags(m.group(1) ?? '')}\n',
    );

    // 9. 代码块
    result = result.replaceAllMapped(
      RegExp(r'<pre[^>]*><code[^>]*>(.*?)</code></pre>',
          dotAll: true, caseSensitive: false),
      (m) => '\n```\n${_decodeEntities(m.group(1) ?? '')}\n```\n',
    );
    result = result.replaceAllMapped(
      RegExp(r'<code[^>]*>(.*?)</code>', dotAll: true, caseSensitive: false),
      (m) => '`${m.group(1) ?? ''}`',
    );

    // 10. 表格简化处理
    result = result.replaceAllMapped(
      RegExp(r'<t[dh][^>]*>(.*?)</t[dh]>', dotAll: true, caseSensitive: false),
      (m) => ' | ${_stripTags(m.group(1) ?? '')}',
    );
    result = result.replaceAll(
      RegExp(r'</tr>', caseSensitive: false),
      ' |\n',
    );

    // 11. 引用块
    result = result.replaceAllMapped(
      RegExp(r'<blockquote[^>]*>(.*?)</blockquote>',
          dotAll: true, caseSensitive: false),
      (m) {
        final content = _stripTags(m.group(1) ?? '');
        return content
            .split('\n')
            .map((line) => '> ${line.trim()}')
            .join('\n');
      },
    );

    // 12. 水平线
    result = result.replaceAll(
      RegExp(r'<hr\s*/?>',  caseSensitive: false),
      '\n---\n',
    );

    // 13. 清除所有剩余 HTML 标签
    result = _stripTags(result);

    // 14. 解码 HTML 实体
    result = _decodeEntities(result);

    // 15. 清理多余空行
    result = result.replaceAll(RegExp(r'\n{3,}'), '\n\n');

    // 16. 清理每行首尾空白
    result = result
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n')
        .trim();

    return result;
  }

  /// 移除 HTML 标签
  static String _stripTags(String html) {
    return html.replaceAll(RegExp(r'<[^>]+>'), '');
  }

  /// 解码 HTML 实体
  static String _decodeEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&#x27;', "'")
        .replaceAll('&#x2F;', '/')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–')
        .replaceAll('&hellip;', '…')
        .replaceAll('&laquo;', '«')
        .replaceAll('&raquo;', '»')
        .replaceAll('&bull;', '•')
        .replaceAll('&copy;', '©')
        .replaceAll('&reg;', '®')
        .replaceAll('&trade;', '™')
        .replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
          final code = int.tryParse(m.group(1) ?? '');
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        })
        .replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
          final code = int.tryParse(m.group(1) ?? '', radix: 16);
          return code != null ? String.fromCharCode(code) : m.group(0)!;
        });
  }
}
