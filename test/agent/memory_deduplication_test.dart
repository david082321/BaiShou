import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/agent/rag/embedding_service.dart';
import 'package:baishou/agent/rag/memory_deduplication_service.dart';
import 'package:baishou/core/services/api_config_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ── Mocks ──

class MockEmbeddingService extends Mock implements EmbeddingService {}

class MockAgentDatabase extends Mock implements AgentDatabase {}

class MockApiConfigService extends Mock implements ApiConfigService {}

void main() {
  late MockEmbeddingService mockEmbedding;
  late MockAgentDatabase mockDb;
  late MockApiConfigService mockApiConfig;
  late MemoryDeduplicationService service;

  const testSessionId = 'test-session-001';
  const testMemory = '用户喜欢吃汉堡包';
  final testVector = List<double>.filled(128, 0.1);

  setUp(() {
    mockEmbedding = MockEmbeddingService();
    mockDb = MockAgentDatabase();
    mockApiConfig = MockApiConfigService();
    service = MemoryDeduplicationService(mockEmbedding, mockDb, mockApiConfig);
  });

  // ── Helper ──

  /// 构造一条向量检索结果 row
  Map<String, dynamic> _makeCandidate({
    required String embeddingId,
    required String messageId,
    required String chunkText,
    required double distance, // cosine distance; similarity = 1 - distance
    int createdAt = 1700000000000,
  }) => {
    'embedding_id': embeddingId,
    'message_id': messageId,
    'session_id': testSessionId,
    'chunk_index': 0,
    'chunk_text': chunkText,
    'dimension': 128,
    'model_id': 'text-embedding-model',
    'distance': distance,
    'created_at': createdAt,
    'session_title': 'Test Session',
  };

  // ═══════════════════════════════════════════════════════════

  group('DeduplicationResult', () {
    test('toString 包含核心字段', () {
      const r = DeduplicationResult(
        action: DeduplicationAction.merged,
        mergedContent: '合并后的内容',
        removedIds: ['id1'],
        highestSimilarity: 0.85,
      );
      expect(r.toString(), contains('merged'));
      expect(r.toString(), contains('0.85'));
      expect(r.toString(), contains('removed=1'));
    });
  });

  // ═══════════════════════════════════════════════════════════

  group('checkAndMerge - 直接存储', () {
    test('embedding 生成失败 → stored', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenAnswer((_) async => null);

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      expect(result.action, DeduplicationAction.stored);
      verifyNever(
        () => mockDb.searchSimilar(
          queryEmbedding: any(named: 'queryEmbedding'),
          topK: any(named: 'topK'),
        ),
      );
    });

    test('embedding 返回空向量 → stored', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenAnswer((_) async => []);

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      expect(result.action, DeduplicationAction.stored);
    });

    test('无候选记忆 → stored', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenAnswer((_) async => testVector);
      when(
        () => mockDb.searchSimilar(
          queryEmbedding: any(named: 'queryEmbedding'),
          topK: any(named: 'topK'),
        ),
      ).thenAnswer((_) async => []);

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      expect(result.action, DeduplicationAction.stored);
    });

    test('相似度低于 mergeThreshold → stored', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenAnswer((_) async => testVector);
      when(
        () => mockDb.searchSimilar(
          queryEmbedding: any(named: 'queryEmbedding'),
          topK: any(named: 'topK'),
        ),
      ).thenAnswer(
        (_) async => [
          _makeCandidate(
            embeddingId: 'emb-1',
            messageId: 'msg-1',
            chunkText: '用户讨厌吃辣',
            distance: 0.50, // similarity = 0.50 < 0.70
          ),
        ],
      );

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      expect(result.action, DeduplicationAction.stored);
      expect(result.highestSimilarity, closeTo(0.50, 0.01));
    });
  });

  // ═══════════════════════════════════════════════════════════

  group('checkAndMerge - 跳过（完全重复）', () {
    test('相似度 > 0.92 → skipped + 时间戳更新', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenAnswer((_) async => testVector);
      when(
        () => mockDb.searchSimilar(
          queryEmbedding: any(named: 'queryEmbedding'),
          topK: any(named: 'topK'),
        ),
      ).thenAnswer(
        (_) async => [
          _makeCandidate(
            embeddingId: 'emb-1',
            messageId: 'msg-1',
            chunkText: '用户喜欢吃汉堡包',
            distance: 0.05, // similarity = 0.95 > 0.92
          ),
        ],
      );
      when(
        () => mockDb.customStatement(any(), any()),
      ).thenAnswer((_) async => 0);

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      expect(result.action, DeduplicationAction.skipped);
      expect(result.highestSimilarity, closeTo(0.95, 0.01));
      // 验证时间戳被更新
      verify(
        () => mockDb.customStatement(
          any(that: contains('UPDATE message_embeddings')),
          any(),
        ),
      ).called(1);
    });

    test('相似度刚好等于 0.92 不会跳过（需要 > 0.92）', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenAnswer((_) async => testVector);
      // 需要 API config 来调用 LLM（当 0.70 < sim <= 0.92）
      when(() => mockApiConfig.globalDialogueProviderId).thenReturn('');
      when(
        () => mockDb.searchSimilar(
          queryEmbedding: any(named: 'queryEmbedding'),
          topK: any(named: 'topK'),
        ),
      ).thenAnswer(
        (_) async => [
          _makeCandidate(
            embeddingId: 'emb-1',
            messageId: 'msg-1',
            chunkText: '用户喜欢吃汉堡',
            distance: 0.08, // similarity = 0.92 — 不 > 0.92
          ),
        ],
      );

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      // 进入 LLM 判断流程，但 provider 为空 → fallback stored
      expect(result.action, DeduplicationAction.stored);
    });
  });

  // ═══════════════════════════════════════════════════════════

  group('checkAndMerge - LLM 合并区间 (0.70 ~ 0.92)', () {
    test('LLM provider 未配置 → fallback stored', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenAnswer((_) async => testVector);
      when(
        () => mockDb.searchSimilar(
          queryEmbedding: any(named: 'queryEmbedding'),
          topK: any(named: 'topK'),
        ),
      ).thenAnswer(
        (_) async => [
          _makeCandidate(
            embeddingId: 'emb-1',
            messageId: 'msg-1',
            chunkText: '用户喜欢吃披萨',
            distance: 0.20, // similarity = 0.80
          ),
        ],
      );
      when(() => mockApiConfig.globalDialogueProviderId).thenReturn('');

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      expect(result.action, DeduplicationAction.stored);
      expect(result.highestSimilarity, closeTo(0.80, 0.01));
    });

    test('LLM provider ID 非空但 modelId 为空 → fallback stored', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenAnswer((_) async => testVector);
      when(
        () => mockDb.searchSimilar(
          queryEmbedding: any(named: 'queryEmbedding'),
          topK: any(named: 'topK'),
        ),
      ).thenAnswer(
        (_) async => [
          _makeCandidate(
            embeddingId: 'emb-1',
            messageId: 'msg-1',
            chunkText: '用户喜欢吃披萨',
            distance: 0.15, // similarity = 0.85
          ),
        ],
      );
      when(
        () => mockApiConfig.globalDialogueProviderId,
      ).thenReturn('provider-1');
      when(() => mockApiConfig.globalDialogueModelId).thenReturn('');

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      expect(result.action, DeduplicationAction.stored);
    });
  });

  // ═══════════════════════════════════════════════════════════

  group('checkAndMerge - 容错', () {
    test('embedQuery 抛出异常 → fallback stored', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenThrow(Exception('网络超时'));

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      expect(result.action, DeduplicationAction.stored);
    });

    test('searchSimilar 抛出异常 → fallback stored', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenAnswer((_) async => testVector);
      when(
        () => mockDb.searchSimilar(
          queryEmbedding: any(named: 'queryEmbedding'),
          topK: any(named: 'topK'),
        ),
      ).thenThrow(Exception('数据库锁定'));

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      expect(result.action, DeduplicationAction.stored);
    });

    test('更新时间戳失败不影响 skipped 结果', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenAnswer((_) async => testVector);
      when(
        () => mockDb.searchSimilar(
          queryEmbedding: any(named: 'queryEmbedding'),
          topK: any(named: 'topK'),
        ),
      ).thenAnswer(
        (_) async => [
          _makeCandidate(
            embeddingId: 'emb-1',
            messageId: 'msg-1',
            chunkText: '用户喜欢吃汉堡包',
            distance: 0.03, // similarity = 0.97
          ),
        ],
      );
      when(
        () => mockDb.customStatement(any(), any()),
      ).thenThrow(Exception('写入失败'));

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      // 时间戳更新失败不影响整体 skipped 结果
      expect(result.action, DeduplicationAction.skipped);
    });
  });

  // ═══════════════════════════════════════════════════════════

  group('checkAndMerge - 多候选处理', () {
    test('多条候选：只有最高分超过阈值时才触发去重', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenAnswer((_) async => testVector);
      when(
        () => mockDb.searchSimilar(
          queryEmbedding: any(named: 'queryEmbedding'),
          topK: any(named: 'topK'),
        ),
      ).thenAnswer(
        (_) async => [
          // 按 distance 升序（similarity 降序）
          _makeCandidate(
            embeddingId: 'emb-1',
            messageId: 'msg-1',
            chunkText: '用户的早餐习惯',
            distance: 0.60, // similarity = 0.40 — 最高
          ),
          _makeCandidate(
            embeddingId: 'emb-2',
            messageId: 'msg-2',
            chunkText: '用户的作息时间',
            distance: 0.80, // similarity = 0.20
          ),
        ],
      );

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      expect(result.action, DeduplicationAction.stored);
      expect(result.highestSimilarity, closeTo(0.40, 0.01));
    });

    test('多条候选：首条超过 duplicate 阈值 → 跳过', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenAnswer((_) async => testVector);
      when(
        () => mockDb.searchSimilar(
          queryEmbedding: any(named: 'queryEmbedding'),
          topK: any(named: 'topK'),
        ),
      ).thenAnswer(
        (_) async => [
          _makeCandidate(
            embeddingId: 'emb-1',
            messageId: 'msg-1',
            chunkText: '用户喜欢吃汉堡包',
            distance: 0.04, // similarity = 0.96 > 0.92
          ),
          _makeCandidate(
            embeddingId: 'emb-2',
            messageId: 'msg-2',
            chunkText: '用户也喜欢吃薯条',
            distance: 0.25, // similarity = 0.75
          ),
        ],
      );
      when(
        () => mockDb.customStatement(any(), any()),
      ).thenAnswer((_) async => 0);

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      expect(result.action, DeduplicationAction.skipped);
      expect(result.highestSimilarity, closeTo(0.96, 0.01));
    });
  });

  // ═══════════════════════════════════════════════════════════

  group('阈值边界值测试', () {
    test('相似度 0.70 刚好 → 不触发 LLM（需要 > 0.70）', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenAnswer((_) async => testVector);
      when(
        () => mockDb.searchSimilar(
          queryEmbedding: any(named: 'queryEmbedding'),
          topK: any(named: 'topK'),
        ),
      ).thenAnswer(
        (_) async => [
          _makeCandidate(
            embeddingId: 'emb-1',
            messageId: 'msg-1',
            chunkText: '用户的饮食偏好',
            distance: 0.30, // similarity = 0.70 — 不 > 0.70
          ),
        ],
      );

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      expect(result.action, DeduplicationAction.stored);
      // 不应该尝试访问 LLM 配置
      verifyNever(() => mockApiConfig.globalDialogueProviderId);
    });

    test('相似度 0.701 → 进入 LLM 判断', () async {
      when(
        () => mockEmbedding.embedQuery(testMemory),
      ).thenAnswer((_) async => testVector);
      when(
        () => mockDb.searchSimilar(
          queryEmbedding: any(named: 'queryEmbedding'),
          topK: any(named: 'topK'),
        ),
      ).thenAnswer(
        (_) async => [
          _makeCandidate(
            embeddingId: 'emb-1',
            messageId: 'msg-1',
            chunkText: '用户的饮食偏好',
            distance: 0.299, // similarity ≈ 0.701 > 0.70
          ),
        ],
      );
      when(() => mockApiConfig.globalDialogueProviderId).thenReturn('');

      final result = await service.checkAndMerge(
        newMemoryContent: testMemory,
        sessionId: testSessionId,
      );

      // 尝试了 LLM 但 provider 为空 → fallback stored
      verify(() => mockApiConfig.globalDialogueProviderId).called(1);
      expect(result.action, DeduplicationAction.stored);
    });
  });
}
