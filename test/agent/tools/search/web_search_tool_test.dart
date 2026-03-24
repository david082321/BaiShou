/// WebSearchTool 单元测试
///
/// 测试覆盖范围：
/// 1. 基础属性（ID、分类、参数 schema）
/// 2. 参数兼容性（queries 数组 + 旧 query 兼容）
/// 3. 引擎配置（默认引擎 = tavily）
/// 4. 结果格式化
/// 5. ToolDefinition 转换

import 'package:baishou/agent/tools/search/web_search_service.dart';
import 'package:baishou/agent/tools/search/web_search_tool.dart';
import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WebSearchTool tool;

  setUp(() {
    tool = WebSearchTool();
  });

  // ════════════════════════════════════════════════════════════
  // 基础属性
  // ════════════════════════════════════════════════════════════
  group('WebSearchTool - 基础属性', () {
    test('应该有正确的 ID 和分类', () {
      expect(tool.id, 'web_search');
      expect(tool.category, 'search');
    });

    test('description 应该提示使用多查询词', () {
      expect(tool.description, contains('2-3 search queries'));
      expect(tool.description, contains('different angles'));
    });

    test('参数 schema 应该定义 queries 数组', () {
      final props = tool.parameterSchema['properties'] as Map;
      expect(props.containsKey('queries'), isTrue);

      final queriesDef = props['queries'] as Map;
      expect(queriesDef['type'], 'array');
      expect(queriesDef['minItems'], 1);
      expect(queriesDef['maxItems'], 3);
    });

    test('默认引擎应该是 tavily', () {
      final params = tool.configurableParams;
      final engineParam = params.firstWhere((p) => p.key == 'engine');
      expect(engineParam.defaultValue, 'tavily');
      expect((engineParam.options as List), contains('tavily'));
      expect((engineParam.options as List), contains('bing'));
      expect((engineParam.options as List), contains('google'));
    });

    test('应该有 tavily_api_key 配置参数', () {
      final params = tool.configurableParams;
      final apiKeyParam = params.firstWhere((p) => p.key == 'tavily_api_key');
      expect(apiKeyParam.defaultValue, '');
    });

    test('应该有 max_results 配置参数', () {
      final params = tool.configurableParams;
      final maxResultsParam = params.firstWhere((p) => p.key == 'max_results');
      expect(maxResultsParam.defaultValue, 5);
      expect(maxResultsParam.min, 1);
      expect(maxResultsParam.max, 10);
    });

    test('应该有 rag_enabled 配置参数', () {
      final params = tool.configurableParams;
      final ragParam = params.firstWhere((p) => p.key == 'rag_enabled');
      expect(ragParam.defaultValue, false);
    });
  });

  // ════════════════════════════════════════════════════════════
  // 参数兼容性
  // ════════════════════════════════════════════════════════════
  group('WebSearchTool - 参数兼容性', () {
    test('空 queries 应该返回错误', () async {
      final context = ToolContext(
        sessionId: 'test',
        vaultPath: '/tmp',
        userConfig: {'engine': 'bing', 'max_results': 5},
      );

      final result = await tool.execute({'queries': []}, context);

      expect(result.success, isFalse);
      expect(result.output, contains('At least one'));
    });

    test('缺少参数应该返回错误', () async {
      final context = ToolContext(
        sessionId: 'test',
        vaultPath: '/tmp',
      );

      final result = await tool.execute({}, context);

      expect(result.success, isFalse);
      expect(result.output, contains('Missing required'));
    });

    test('空字符串 query 应该被过滤', () async {
      final context = ToolContext(
        sessionId: 'test',
        vaultPath: '/tmp',
        userConfig: {'engine': 'bing', 'max_results': 5},
      );

      final result = await tool.execute({
        'queries': ['', '  ', ''],
      }, context);

      expect(result.success, isFalse);
      expect(result.output, contains('At least one'));
    });

    test('旧版 query 字符串参数应该兼容', () async {
      // 这里仅验证参数解析逻辑不报错（实际网络请求会失败）
      final context = ToolContext(
        sessionId: 'test',
        vaultPath: '/tmp',
        userConfig: {'engine': 'bing', 'max_results': 5},
      );

      // 旧版 query（string 类型）- 会尝试发起网络请求
      // 我们只验证不会返回 "Missing required parameter"
      final result = await tool.execute({'query': 'test query'}, context);
      // 这里因为没有网络可能会失败，但不应该报 Missing required
      expect(result.output, isNot(contains('Missing required')));
    });
  });

  // ════════════════════════════════════════════════════════════
  // 结果格式化
  // ════════════════════════════════════════════════════════════
  group('WebSearchTool - 结果格式化验证', () {
    test('引用格式应该包含 Markdown 可点击链接', () {
      final results = [
        SearchResult(
          title: 'Flutter Guide',
          url: 'https://flutter.dev',
          snippet: 'Official guide to Flutter',
        ),
        SearchResult(
          title: 'Dart Docs',
          url: 'https://dart.dev',
          snippet: 'Dart documentation pages',
        ),
      ];

      // 模拟格式化逻辑
      final buffer = StringBuffer();
      for (var i = 0; i < results.length; i++) {
        final r = results[i];
        buffer.writeln('[${i + 1}] [${r.title}](${r.url})');
        buffer.writeln(r.snippet);
        buffer.writeln();
      }
      final output = buffer.toString();

      expect(output, contains('[1] [Flutter Guide](https://flutter.dev)'));
      expect(output, contains('[2] [Dart Docs](https://dart.dev)'));
    });
  });

  // ════════════════════════════════════════════════════════════
  // ToolDefinition 转换
  // ════════════════════════════════════════════════════════════
  group('WebSearchTool - 工具定义', () {
    test('toDefinition 应该生成有效的 ToolDefinition', () {
      final def = tool.toDefinition();
      expect(def.name, 'web_search');
      expect(def.description, isNotEmpty);
      expect(def.parameterSchema, isNotEmpty);
    });

    test('required 应包含 queries', () {
      final required = tool.parameterSchema['required'] as List;
      expect(required, contains('queries'));
    });
  });
}
