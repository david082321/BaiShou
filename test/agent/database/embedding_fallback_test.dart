import 'dart:math';
import 'package:baishou/agent/database/agent_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AgentDatabase db;

  setUp(() {
    // 使用纯内存的 NativeDatabase 创建测试环境
    // 注意：这里刻意没有加载 sqlite3.loadSqliteVectorExtension()
    // 来模拟在华为等设备上加载失败的情况
    db = AgentDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('测试纯 Dart 层面的 Float32List 的插入和 cosine_distance 计算', () async {
    // 构造一些测试的向量
    // [1.0, 0.0]
    final vec1 = [1.0, 0.0];
    // [0.0, 1.0] 互相垂直，cosine 距离理论上为 1.0
    final vec2 = [0.0, 1.0];
    // [0.707, 0.707] 45度角
    final vec3 = [0.707, 0.707];
    // [1.0, 0.0] 完全相同，cosine 距离应该为 0.0
    final vec4 = [1.0, 0.0];

    // 1. 测试写入 (不会报 vector_as_f32() 找不到的错误，直接写 Blob 成功)
    await db.insertEmbedding(
      id: 'mock_1',
      sourceType: 'chat',
      sourceId: 'msg_1',
      groupId: 'sess_1',
      chunkIndex: 0,
      chunkText: 'test 1',
      embedding: vec1,
      modelId: 'mock_model',
    );
    
    await db.insertEmbedding(
      id: 'mock_2',
      sourceType: 'chat',
      sourceId: 'msg_2',
      groupId: 'sess_1',
      chunkIndex: 0,
      chunkText: 'test 2',
      embedding: vec2,
      modelId: 'mock_model',
    );

    await db.insertEmbedding(
      id: 'mock_3',
      sourceType: 'chat',
      sourceId: 'msg_3',
      groupId: 'sess_1',
      chunkIndex: 0,
      chunkText: 'test 3',
      embedding: vec3,
      modelId: 'mock_model',
    );

    await db.insertEmbedding(
      id: 'mock_4',
      sourceType: 'chat',
      sourceId: 'msg_4',
      groupId: 'sess_1',
      chunkIndex: 0,
      chunkText: 'test 4',
      embedding: vec4,
      modelId: 'mock_model',
    );

    final count = await db.getEmbeddingCount();
    expect(count, 4, reason: '四个纯 Dart 字节的向量插入应当成功');

    // 2. 测试查询 (没有触发 sqlite-vec 扩展，降级到 pure Dart 查询)
    // 以 [1.0, 0.0] 为基准查询
    final queryEmbedding = [1.0, 0.0];
    final results = await db.searchSimilar(
      queryEmbedding: queryEmbedding,
      topK: 4,
      dimension: 2,
    );

    expect(results.length, 4, reason: '必须返回全部结果完成退避搜索');

    // 检查排序顺序是否按 distance 升序
    // 第一个是它自己或者完全一致的 mock_4，距离 0
    final top1 = results[0];
    expect(top1['embedding_id'] == 'mock_1' || top1['embedding_id'] == 'mock_4', isTrue);
    expect((top1['distance'] as double).abs() < 0.001, isTrue);

    final top2 = results[1];
    expect(top2['embedding_id'] == 'mock_1' || top2['embedding_id'] == 'mock_4', isTrue);
    expect((top2['distance'] as double).abs() < 0.001, isTrue);

    // 第三个应该是 vec3 [0.707, 0.707] 角度45度, cos = 0.707 * 1.0, distance = 1 - 0.707 = 0.293
    final top3 = results[2];
    expect(top3['embedding_id'], 'mock_3');
    expect((top3['distance'] as double) > 0.2 && (top3['distance'] as double) < 0.3, isTrue);

    // 第四个应该是 vec2 [0.0, 1.0] 完全垂直, cos 0, distance 1.0
    final top4 = results[3];
    expect(top4['embedding_id'], 'mock_2');
    expect(((top4['distance'] as double) - 1.0).abs() < 0.001, isTrue);
  });
}
