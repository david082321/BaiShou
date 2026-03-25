import 'package:baishou/agent/database/agent_database.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:sqlite_vector/sqlite_vector.dart';

bool _extensionLoaded = false;

/// 创建用于测试的纯内存 AgentDatabase，并加载 sqlite-vec 扩展
AgentDatabase createInMemoryAgentDatabase() {
  if (!_extensionLoaded) {
    sql.sqlite3.loadSqliteVectorExtension();
    _extensionLoaded = true;
  }
  return AgentDatabase(NativeDatabase.memory());
}

/// 向数据库插入模拟的 embedding 数据
Future<void> seedEmbeddingData(
  AgentDatabase db, {
  required int count,
  required String modelId,
  required int dimension,
}) async {
  // 需要先初始化对应维度的索引
  await db.initVectorIndex(dimension);

  for (int i = 0; i < count; i++) {
    final embedding = List.filled(dimension, 0.5); // dummy vector
    await db.insertEmbedding(
      id: 'mock_emb_$i',
      sourceType: 'chat',
      sourceId: 'mock_msg_$i',
      groupId: 'mock_session',
      chunkIndex: 0,
      chunkText: 'This is mock chunk $i',
      embedding: embedding,
      modelId: modelId,
    );
  }
}
