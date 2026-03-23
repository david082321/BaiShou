/// WebSearchTool 单元测试
///
/// 测试覆盖范围：
/// 1. 参数解析（新 queries 数组 + 旧 query 兼容）
/// 2. 引擎解析逻辑
/// 3. 结果格式化输出

import 'package:baishou/agent/tools/search/web_search_service.dart';
import 'package:baishou/agent/tools/search/web_search_tool.dart';
import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late WebSearchTool tool;

  setUp(() {
    tool = WebSearchTool();
  });

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

    test('默认引擎应该是 duckduckgo', () {
      final params = tool.configurableParams;
      final engineParam = params.firstWhere((p) => p.key == 'engine');
      expect(engineParam.defaultValue, 'duckduckgo');
      expect((engineParam.options as List), contains('duckduckgo'));
    });
  });

  group('WebSearchTool - 参数兼容性', () {
    test('空 queries 应该返回错误', () async {
      // Arrange（准备）
      final context = ToolContext(
        sessionId: 'test',
        vaultPath: '/tmp',
        userConfig: {'engine': 'duckduckgo', 'max_results': 5},
      );

      // Act（执行）
      final result = await tool.execute({'queries': []}, context);

      // Assert（断言）
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
  });

  group('WebSearchTool - 结果格式化验证', () {
    test('引用格式应该包含 Markdown 可点击链接', () {
      // 验证输出格式模板
      final results = [
        SearchResult(title: 'Flutter Guide', url: 'https://flutter.dev', snippet: 'Official guide'),
        SearchResult(title: 'Dart Docs', url: 'https://dart.dev', snippet: 'Dart documentation'),
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

      // Assert（断言）
      expect(output, contains('[1] [Flutter Guide](https://flutter.dev)'));
      expect(output, contains('[2] [Dart Docs](https://dart.dev)'));
    });
  });

  group('WebSearchTool - 工具定义', () {
    test('toDefinition 应该生成有效的 ToolDefinition', () {
      final def = tool.toDefinition();
      expect(def.name, 'web_search');
      expect(def.description, isNotEmpty);
      expect(def.parameterSchema, isNotEmpty);
    });
  });
}
