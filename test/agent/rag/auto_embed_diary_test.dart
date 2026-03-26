import 'package:baishou/agent/clients/ai_client.dart';
import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/agent/models/ai_provider_model.dart';
import 'package:baishou/agent/rag/embedding_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../mocks/mock_ai_client.dart';
import '../../mocks/mock_api_config_service.dart';
import '../../test_helpers/database_helpers.dart';

void main() {
  group('Auto-Embed and Supplement Logic Tests', () {
    late AgentDatabase db;
    late MockApiConfigService mockApiConfig;
    late MockAiClient mockAiClient;
    late EmbeddingService embeddingService;

    final dummyProvider = AiProviderModel(
      id: 'mock_provider',
      name: 'Mock',
      type: ProviderType.openai,
      apiKey: 'test_key',
      baseUrl: '',
      isSystem: false,
    );

    setUp(() {
      db = createInMemoryAgentDatabase();
      mockApiConfig = MockApiConfigService();
      mockAiClient = MockAiClient();

      AiClientFactory.setTestClient(mockAiClient);

      // Default mock configuration
      when(
        () => mockApiConfig.globalEmbeddingProviderId,
      ).thenReturn('mock_provider');
      when(() => mockApiConfig.globalEmbeddingModelId).thenReturn('mock_model');
      when(
        () => mockApiConfig.getProvider('mock_provider'),
      ).thenReturn(dummyProvider);
      when(() => mockApiConfig.globalEmbeddingDimension).thenReturn(3);
      when(
        () => mockApiConfig.setGlobalEmbeddingDimension(any()),
      ).thenAnswer((_) async {});

      embeddingService = EmbeddingService(mockApiConfig, db);
    });

    tearDown(() async {
      await db.close();
      AiClientFactory.setTestClient(null);
    });

    test('1. 如果没有配置嵌入模型，reEmbedText 应该直接安全退出', () async {
      // 未配置模型的情况（ProviderId 或 ModelId 为空）
      when(() => mockApiConfig.globalEmbeddingProviderId).thenReturn('');
      when(() => mockApiConfig.globalEmbeddingModelId).thenReturn('');

      await embeddingService.reEmbedText(
        text: '这是一篇新日记',
        sourceType: 'diary',
        sourceId: '123',
        groupId: 'diary_auto',
      );

      final count = await db.getEmbeddingCount();
      expect(count, 0, reason: '未配置时不应产生任何嵌入数据');
    });

    test('2. getEmbeddedSourceMetadataByType 能够正确识别已嵌入的日记（补充嵌入逻辑测试）', () async {
      when(
        () => mockAiClient.generateEmbedding(
          input: any(named: 'input'),
          modelId: any(named: 'modelId'),
        ),
      ).thenAnswer((_) async => [0.1, 0.2, 0.3]);

      // 模拟先嵌入两篇日记
      await embeddingService.embedText(
        text: '日记1内容',
        sourceType: 'diary',
        sourceId: '1',
        groupId: 'diary_batch',
      );
      await embeddingService.embedText(
        text: '日记2内容',
        sourceType: 'diary',
        sourceId: '2',
        groupId: 'diary_batch',
      );
      // 模拟一个非日记的嵌入
      await embeddingService.embedText(
        text: '普通记忆',
        sourceType: 'chat',
        sourceId: 'mem_1',
        groupId: 'mem',
      );

      // 获取所有的 diary 已嵌入元信息
      final existingIds = await db.getEmbeddedSourceMetadataByType('diary');

      expect(existingIds.length, 2);
      expect(existingIds.containsKey('1'), isTrue);
      expect(existingIds.containsKey('2'), isTrue);
      expect(existingIds.containsKey('mem_1'), isFalse);
    });

    test('3. reEmbedText 会删除原有数据并重新生成（长文分块测试）', () async {
      when(
        () => mockAiClient.generateEmbedding(
          input: any(named: 'input'),
          modelId: any(named: 'modelId'),
        ),
      ).thenAnswer((_) async => [0.1, 0.2, 0.3]);

      // 初始：写入一个短日记
      await embeddingService.embedText(
        text: '旧的短日记',
        sourceType: 'diary',
        sourceId: '999',
        groupId: 'diary_auto',
      );
      var chunks = await db.getAllEmbeddingChunks();
      expect(chunks.length, 1, reason: '短日记只有 1 个 chunk');

      // 生成一篇超过 2000 字的长文日记（512/块，重叠 64）
      final longText = List.generate(2000, (i) => '字').join('');

      // 执行 reEmbedText 重新保存（模拟用户更新了长文）
      await embeddingService.reEmbedText(
        text: longText,
        sourceType: 'diary',
        sourceId: '999',
        groupId: 'diary_auto',
      );

      // (2000 - 512) / (512 - 64) = 1488 / 448 ≈ 3.32 -> 需要额外的块，所以总共约 4 到 5 个分块。
      chunks = await db.getAllEmbeddingChunks();

      // 确保旧的数据被全删了，现在只有新生成的 chunk
      final allDiary999Chunks = chunks
          .where((c) => c['source_id'] == '999')
          .toList();
      expect(allDiary999Chunks.isNotEmpty, isTrue);
      expect(
        allDiary999Chunks.length,
        greaterThan(3),
        reason: '2000字被按 512 大小分出了多个 chunk',
      );

      // 验证分块逻辑的正确性，第一个 chunk 应该具有 chunk_index 0
      final firstChunk = allDiary999Chunks.firstWhere(
        (c) => c['chunk_index'] == 0,
      );
      expect(
        firstChunk['chunk_text'].length,
        512,
        reason: '由于中文字符不限制，chunk 长度应该是 512',
      );
    });
  });
}
