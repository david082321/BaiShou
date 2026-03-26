/// UrlReadTool — AI 可调用的网页读取工具
///
/// 获取指定 URL 的网页内容，将 HTML 转换为 Markdown 后
/// 返回给 AI。通常与 WebSearchTool 配合使用：
/// 1. AI 先搜索获取 URL 列表
/// 2. AI 选择感兴趣的 URL 调用此工具深入阅读

import 'dart:convert';
import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:baishou/agent/tools/search/html_to_markdown.dart';
import 'package:baishou/agent/tools/tool_config_param.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class UrlReadTool extends AgentTool {
  static const _timeout = Duration(seconds: 20);
  static const _defaultMaxLength = 8000; // 字符上限，避免 context 爆炸

  @override
  String get id => 'url_read';

  @override
  String get displayName => t.agent.tools.url_read;

  @override
  String get category => 'search';

  @override
  IconData get icon => Icons.article_outlined;

  @override
  List<ToolConfigParam> get configurableParams => [
    ToolConfigParam(
      key: 'max_length',
      label: t.agent.tools.param_max_length,
      description: t.agent.tools.param_max_length_desc,
      type: ParamType.integer,
      defaultValue: _defaultMaxLength,
      min: 2000,
      max: 20000,
      icon: Icons.short_text,
    ),
  ];

  @override
  String get description =>
      'Read and extract content from a web page URL. Converts HTML to clean '
      'Markdown format. Use after web_search to read specific pages in detail. '
      'Returns the main text content of the page.';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {
      'url': {
        'type': 'string',
        'description':
            'The full URL to read (must start with http:// or https://).',
      },
    },
    'required': ['url'],
  };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    ToolContext context,
  ) async {
    final url = arguments['url'] as String?;
    if (url == null || url.trim().isEmpty) {
      return ToolResult.error('Missing required parameter: url');
    }

    // 校验 URL 格式
    final trimmedUrl = url.trim();
    if (!trimmedUrl.startsWith('http://') &&
        !trimmedUrl.startsWith('https://')) {
      return ToolResult.error(
        'Invalid URL format. Must start with http:// or https://',
      );
    }

    final maxLength =
        (context.userConfig['max_length'] as num?)?.toInt() ??
        _defaultMaxLength;

    try {
      final uri = Uri.parse(trimmedUrl);
      final response = await http
          .get(uri, headers: _browserHeaders)
          .timeout(_timeout);

      if (response.statusCode != 200) {
        return ToolResult.error(
          'Failed to fetch URL: HTTP ${response.statusCode}',
        );
      }

      final contentType = response.headers['content-type'] ?? '';
      final html = utf8.decode(response.bodyBytes, allowMalformed: true);

      // 如果不是 HTML，直接返回原始文本（截断）
      if (!contentType.contains('html') && !contentType.contains('text')) {
        return ToolResult(
          output:
              'Non-HTML content (${contentType.split(';').first}). '
              'Cannot extract readable content from this URL.',
          success: true,
          metadata: {'url': trimmedUrl, 'content_type': contentType},
        );
      }

      // 提取页面标题
      final titleMatch = RegExp(
        r'<title[^>]*>(.*?)</title>',
        dotAll: true,
        caseSensitive: false,
      ).firstMatch(html);
      final pageTitle = titleMatch != null
          ? HtmlToMarkdownConverter.convert(titleMatch.group(1) ?? '')
          : uri.host;

      // 尝试提取 <article> 或 <main> 主体内容，否则用 <body>
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

      // HTML → Markdown
      var markdown = HtmlToMarkdownConverter.convert(bodyHtml);

      // 截断过长内容
      final truncated = markdown.length > maxLength;
      if (truncated) {
        markdown = markdown.substring(0, maxLength);
        // 在最后一个完整段落处截断
        final lastParagraph = markdown.lastIndexOf('\n\n');
        if (lastParagraph > maxLength * 0.7) {
          markdown = markdown.substring(0, lastParagraph);
        }
        markdown += '\n\n[... Content truncated at $maxLength characters]';
      }

      final buffer = StringBuffer()
        ..writeln('# $pageTitle')
        ..writeln('**Source:** $trimmedUrl')
        ..writeln()
        ..write(markdown);

      return ToolResult(
        output: buffer.toString(),
        success: true,
        metadata: {
          'url': trimmedUrl,
          'title': pageTitle,
          'content_length': markdown.length,
          'truncated': truncated,
        },
      );
    } catch (e) {
      return ToolResult.error('Failed to read URL: $e');
    }
  }

  /// 模拟浏览器请求头
  static const _browserHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
  };
}
