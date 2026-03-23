/// Agent 数据导出/导入功能 — 单元测试
///
/// 验证 AgentDatabase 层面对于数据全量清空、全量获取、RAG 向量序列化还原、
/// 以及 FTS 索引自动重建的正确性。
///
/// 注意: 这些测试运行在纯内存 SQLite 实例中，无需任何真实文件系统交互。

import 'dart:convert';
import 'dart:typed_data';

import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/agent/database/agent_tables.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/database_helpers.dart';

void main() {
  group('AgentDatabase — 数据导出/导入 底层接口测试', () {
    late AgentDatabase db;

    setUp(() {
      db = createInMemoryAgentDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    // ── 辅助函数 ──────────────────────────────────────────

    /// 向数据库填充一组完整的 Agent 测试数据（伙伴、会话、消息、Part）
    Future<void> seedAgentData() async {
      // 1. 插入 Assistant
      await db.into(db.agentAssistants).insert(
            AgentAssistantsCompanion.insert(
              id: 'ast_1',
              name: '测试伙伴',
            ),
          );

      // 2. 插入 Session
      await db.into(db.agentSessions).insert(
            AgentSessionsCompanion.insert(
              id: 'ses_1',
              vaultName: 'Personal',
              providerId: 'openai',
              modelId: 'gpt-4',
              title: Value('测试对话'),
              assistantId: Value('ast_1'),
            ),
          );

      // 3. 插入 Messages
      await db.into(db.agentMessages).insert(
            AgentMessagesCompanion.insert(
              id: 'msg_user_1',
              sessionId: 'ses_1',
              role: 'user',
              orderIndex: 1,
            ),
          );
      await db.into(db.agentMessages).insert(
            AgentMessagesCompanion.insert(
              id: 'msg_ast_1',
              sessionId: 'ses_1',
              role: 'assistant',
              orderIndex: 2,
            ),
          );

      // 4. 插入 Parts (text 类型)
      await db.into(db.agentParts).insert(
            AgentPartsCompanion.insert(
              id: 'msg_user_1_p0',
              messageId: 'msg_user_1',
              sessionId: 'ses_1',
              type: 'text',
              data: '{"text":"Hello this is a test message for export"}',
            ),
          );
      await db.into(db.agentParts).insert(
            AgentPartsCompanion.insert(
              id: 'msg_ast_1_p0',
              messageId: 'msg_ast_1',
              sessionId: 'ses_1',
              type: 'text',
              data: '{"text":"Hello I am your AI assistant ready to help"}',
            ),
          );
    }

    // ── clearAllAgentData 测试 ────────────────────────────

    test('clearAllAgentData — 应清空所有 Agent 表和 FTS', () async {
      await seedAgentData();
      await seedEmbeddingData(db, count: 3, modelId: 'test', dimension: 2);

      // 确保数据存在
      final sessionsBefore =
          await db.select(db.agentSessions).get();
      expect(sessionsBefore.length, 1);
      final embCountBefore = await db.getEmbeddingCount();
      expect(embCountBefore, 3);

      // 执行清空
      await db.clearAllAgentData();

      // 验证各表全部为空
      expect((await db.select(db.agentAssistants).get()).length, 0);
      expect((await db.select(db.agentSessions).get()).length, 0);
      expect((await db.select(db.agentMessages).get()).length, 0);
      expect((await db.select(db.agentParts).get()).length, 0);
      expect(await db.getEmbeddingCount(), 0);
    });

    // ── getAllEmbeddingsForExport / importEmbeddingsRaw 测试 ──

    test('getAllEmbeddingsForExport — 应返回包含 Uint8List BLOB 的记录', () async {
      await seedEmbeddingData(db, count: 2, modelId: 'test_m', dimension: 3);

      final exported = await db.getAllEmbeddingsForExport();

      expect(exported.length, 2);
      for (final row in exported) {
        expect(row['embedding_id'], isNotNull);
        expect(row['embedding'], isA<Uint8List>());
        expect(row['dimension'], 3);
        expect(row['model_id'], 'test_m');
      }
    });

    test('importEmbeddingsRaw — 应正确地把 Uint8List 导回数据库', () async {
      // 准备导出数据
      await seedEmbeddingData(db, count: 3, modelId: 'exp_model', dimension: 2);
      final exported = await db.getAllEmbeddingsForExport();
      expect(exported.length, 3);

      // 清空后确认为零
      await db.clearAllAgentData();
      expect(await db.getEmbeddingCount(), 0);

      // 导入
      await db.importEmbeddingsRaw(exported);

      // 验证
      expect(await db.getEmbeddingCount(), 3);
      final reimported = await db.getAllEmbeddingsForExport();
      for (int i = 0; i < 3; i++) {
        expect(reimported[i]['embedding_id'], exported[i]['embedding_id']);
        expect(reimported[i]['model_id'], 'exp_model');
      }
    });

    // ── Base64 编码/解码 往返测试（模拟 Export → Import 的 JSON 环节） ──

    test('Base64 往返 — 导出 BLOB → Base64 → 解码 → 导入应无损', () async {
      await seedEmbeddingData(db, count: 2, modelId: 'b64_test', dimension: 4);
      final exported = await db.getAllEmbeddingsForExport();

      // 模拟导出：将 Uint8List 转为 Base64 字符串
      final jsonLike = exported.map((e) {
        final copy = Map<String, dynamic>.from(e);
        copy['embedding'] = base64Encode(copy['embedding'] as Uint8List);
        return copy;
      }).toList();

      // 模拟导入：将 Base64 解码回 Uint8List
      final decoded = jsonLike.map((e) {
        final copy = Map<String, dynamic>.from(e);
        copy['embedding'] = base64Decode(copy['embedding'] as String);
        return copy;
      }).toList();

      // 清空再导入
      await db.clearAllAgentData();
      await db.importEmbeddingsRaw(decoded);

      // 验证数据完整
      expect(await db.getEmbeddingCount(), 2);
      final final_ = await db.getAllEmbeddingsForExport();
      for (int i = 0; i < 2; i++) {
        final origBytes = exported[i]['embedding'] as Uint8List;
        final newBytes = final_[i]['embedding'] as Uint8List;
        expect(newBytes.length, origBytes.length,
            reason: 'BLOB 长度应相同');
        expect(newBytes, orderedEquals(origBytes),
            reason: 'BLOB 内容应完全一致');
      }
    });

    // ── rebuildFtsIndex 测试 ──────────────────────────────

    test('rebuildFtsIndex — 应从 Parts 重建 FTS 索引', () async {
      await seedAgentData();

      // 先确认 FTS 索引为空（seedAgentData 直接插库，跳过了 SessionManager 的 FTS 同步）
      final ftsBefore = await db.searchFts('test');
      expect(ftsBefore.length, 0);

      // 重建索引
      await db.rebuildFtsIndex();

      // 验证索引已建立
      final ftsAfter = await db.searchFts('test');
      expect(ftsAfter.length, greaterThanOrEqualTo(1));

      // 更精确的逐条验证
      final ftsAll = await db.searchFts('assistant');
      expect(ftsAll.length, 1);
      expect(ftsAll.first['message_id'], 'msg_ast_1');
    });

    test('rebuildFtsIndex — 空数据库不应报错', () async {
      // 空数据库直接调用不应抛异常
      await expectLater(db.rebuildFtsIndex(), completes);
    });

    // ── 完整的 导出 → 清空 → 导入 → FTS重建 端到端测试 ──────

    test('端到端 — 完整的 导出 → 清空 → 导入 → FTS 重建', () async {
      // 1. 灌入完整数据
      await seedAgentData();
      await seedEmbeddingData(db, count: 5, modelId: 'e2e_model', dimension: 2);

      // 2. 导出所有表
      final expAssistants =
          await db.select(db.agentAssistants).get();
      final expSessions =
          await db.select(db.agentSessions).get();
      final expMessages =
          await db.select(db.agentMessages).get();
      final expParts =
          await db.select(db.agentParts).get();
      final expEmbeddings = await db.getAllEmbeddingsForExport();

      // 3. 清空
      await db.clearAllAgentData();
      expect((await db.select(db.agentAssistants).get()).length, 0);
      expect(await db.getEmbeddingCount(), 0);

      // 4. 导入 (使用 batch API 逐条写入)
      await db.batch((batch) {
        for (final a in expAssistants) {
          batch.insert(db.agentAssistants, a, mode: InsertMode.insertOrReplace);
        }
        for (final s in expSessions) {
          batch.insert(db.agentSessions, s, mode: InsertMode.insertOrReplace);
        }
        for (final m in expMessages) {
          batch.insert(db.agentMessages, m, mode: InsertMode.insertOrReplace);
        }
        for (final p in expParts) {
          batch.insert(db.agentParts, p, mode: InsertMode.insertOrReplace);
        }
      });

      // Base64 往返
      final embJson = expEmbeddings.map((e) {
        final c = Map<String, dynamic>.from(e);
        c['embedding'] = base64Encode(c['embedding'] as Uint8List);
        return c;
      }).toList();
      final embDecoded = embJson.map((e) {
        final c = Map<String, dynamic>.from(e);
        c['embedding'] = base64Decode(c['embedding'] as String);
        return c;
      }).toList();
      await db.importEmbeddingsRaw(embDecoded);

      // 5. 重建 FTS
      await db.rebuildFtsIndex();

      // 6. 验证
      expect((await db.select(db.agentAssistants).get()).length, 1);
      expect((await db.select(db.agentSessions).get()).length, 1);
      expect((await db.select(db.agentMessages).get()).length, 2);
      expect((await db.select(db.agentParts).get()).length, 2);
      expect(await db.getEmbeddingCount(), 5);

      // FTS 验证
      final fts = await db.searchFts('assistant');
      expect(fts.length, 1);
    });
  });
}
