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
  group('EmbeddingService - 向量迁移策略测试', () {
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

      // 默认基础配置
      when(
        () => mockApiConfig.globalEmbeddingProviderId,
      ).thenReturn('mock_provider');
      when(
        () => mockApiConfig.globalEmbeddingModelId,
      ).thenReturn('mock_model_v2');
      when(
        () => mockApiConfig.getProvider('mock_provider'),
      ).thenReturn(dummyProvider);

      embeddingService = EmbeddingService(mockApiConfig, db);
    });

    tearDown(() async {
      await db.close();
      AiClientFactory.setTestClient(null);
    });

    test('应该成功完成完整迁移', () async {
      // Arrange（准备）
      // 1. 初始化旧数据 (old_model, dim=2)
      await seedEmbeddingData(db, count: 5, modelId: 'old_model', dimension: 2);

      // 2. 切换到新模型并配置 Mock 维度
      when(
        () => mockApiConfig.globalEmbeddingModelId,
      ).thenReturn('new_model_dim3');
      // Mock 返回新维度的假向量
      when(
        () => mockAiClient.generateEmbedding(
          input: any(named: 'input'),
          modelId: any(named: 'modelId'),
        ),
      ).thenAnswer((_) async => [0.1, 0.2, 0.3]); // 返回 3 维假数据
      when(
        () => mockApiConfig.setGlobalEmbeddingDimension(3),
      ).thenAnswer((_) async {});

      // Act（执行）
      final events = await embeddingService.migrateEmbeddings().toList();

      // Assert（断言）
      expect(events.last.status, contains('迁移完成 ✅'));

      // 验证数据量未丢失
      final count = await db.getEmbeddingCount();
      expect(count, 5);

      // 验证所有数据均已更新为新模型
      final chunks = await db.getAllEmbeddingChunks();
      for (var chunk in chunks) {
        expect(chunk['model_id'], 'new_model_dim3');
        expect(chunk['dimension'], 3);
      }

      // 验证备份表已被安全清理
      final hasPending = await db.hasPendingMigration();
      expect(hasPending, isFalse);
    });

    test('应该从中断处恢复迁移', () async {
      // Arrange（准备）
      // 1. 模拟崩溃：手动创建备份表，并清除旧数据，模拟重嵌了 2 条数据却中途退出的场景
      await seedEmbeddingData(db, count: 5, modelId: 'old_model', dimension: 2);
      await db.createMigrationBackup();
      await db.clearAndReinitEmbeddings(3);

      // 设定模型和 Mock 响应
      when(
        () => mockApiConfig.globalEmbeddingModelId,
      ).thenReturn('new_model_dim3');
      when(
        () => mockAiClient.generateEmbedding(
          input: any(named: 'input'),
          modelId: any(named: 'modelId'),
        ),
      ).thenAnswer((_) async => [0.1, 0.2, 0.3]);

      // 模拟只重嵌了前面 2 条 chunk
      final backupChunks = await db.getUnmigratedBackupChunks();
      for (int i = 0; i < 2; i++) {
        final chunk = backupChunks[i];
        await db.insertEmbedding(
          id: chunk['embedding_id'] as String,
          sourceType: 'chat',
          sourceId: 'mock_msg_$i',
          groupId: 'mock_session',
          chunkIndex: 0,
          chunkText: chunk['chunk_text'] as String,
          embedding: [0.1, 0.2, 0.3],
          modelId: 'new_model_dim3',
        );
        await db.markBackupChunkMigrated(chunk['embedding_id'] as String);
      }

      // Act（执行）
      // 启动 continueMigration
      final events = await embeddingService.continueMigration().toList();

      // Assert（断言）
      expect(events.last.status, contains('迁移完成 ✅'));
      expect(events.last.total, 3); // 剩余 3 条

      // 验证数据完整性
      final count = await db.getEmbeddingCount();
      expect(count, 5); // 之前的 2 条 + 刚跑的 3 条

      final hasPending = await db.hasPendingMigration();
      expect(hasPending, isFalse);
    });

    test('未配置嵌入模型时应该提前退出', () async {
      // Arrange（准备）
      when(() => mockApiConfig.globalEmbeddingModelId).thenReturn('');
      when(() => mockApiConfig.globalEmbeddingProviderId).thenReturn('');

      // Act（执行）
      final events = await embeddingService.migrateEmbeddings().toList();

      // Assert（断言）
      expect(events.length, 1);
      expect(events.first.status, '嵌入模型未配置');
    });

    test('空数据库迁移应该安全退出', () async {
      // Arrange（准备）
      // 空数据库
      when(() => mockApiConfig.globalEmbeddingModelId).thenReturn('new_model');
      when(
        () => mockApiConfig.getProvider('mock_provider'),
      ).thenReturn(dummyProvider);
      when(
        () => mockAiClient.generateEmbedding(
          input: any(named: 'input'),
          modelId: any(named: 'modelId'),
        ),
      ).thenAnswer((_) async => [0.1]);

      // Act（执行）
      final events = await embeddingService.migrateEmbeddings().toList();

      // Assert（断言）
      expect(events.last.status, '没有需要迁移的数据');
      expect(await db.hasPendingMigration(), isFalse);
    });
  });
}
