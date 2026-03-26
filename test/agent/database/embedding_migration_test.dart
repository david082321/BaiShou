import 'dart:io';

import 'package:baishou/agent/database/agent_database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_helpers/database_helpers.dart';

void main() {
  group('AgentDatabase — Cross-Dimensional Embedding Migration', () {
    late AgentDatabase db;

    setUp(() {
      db = createInMemoryAgentDatabase();
    });

    tearDown(() async {
      await db.close();
    });

    test('Full lifecycle of cross-dimensional embedding migration', () async {
      void logStep(String msg) => File(
        'debug_log.txt',
      ).writeAsStringSync('$msg\n', mode: FileMode.append);
      logStep('--- TEST START ---');
      // 1. Initial State: Old model with dimension 3
      await seedEmbeddingData(db, count: 5, modelId: 'old_model', dimension: 3);
      logStep('--- SEED DONE ---');

      var stats = await db.getEmbeddingStats();
      expect(stats['total_count'], 5);
      expect(stats['dimension_count'], 1);
      final oldModelStats = (stats['models'] as List).first;
      expect(oldModelStats['model_id'], 'old_model');
      expect(oldModelStats['dimension'], 3);

      expect(await db.hasPendingMigration(), isFalse);

      // 2. Start Migration Backup
      final backupCount = await db.createMigrationBackup();
      expect(
        backupCount,
        5,
        reason: 'Migration backup should capture all 5 existing chunks',
      );
      expect(await db.hasPendingMigration(), isTrue);

      // 3. Clear existing vectors and re-initialize vector index with new dimension 5
      logStep('--- CLEAR AND REINIT ---');
      await db.clearAndReinitEmbeddings(5);
      logStep('--- CLEAR AND REINIT DONE ---');

      stats = await db.getEmbeddingStats();
      expect(
        stats['total_count'],
        0,
        reason:
            'Actual embeddings table should be empty after clearAndReinitEmbeddings',
      );
      expect(await db.getUnmigratedCount(), 5);

      // 4. Retrieve unmigrated chunks and process them (simulate LLM RAG re-embedding)
      logStep('--- GET UNMIGRATED ---');
      final unmigratedChunks = await db.getUnmigratedBackupChunks();
      logStep('--- GET UNMIGRATED DONE: ${unmigratedChunks.length} ---');
      expect(unmigratedChunks.length, 5);

      for (var i = 0; i < unmigratedChunks.length; i++) {
        final chunk = unmigratedChunks[i];

        // Simulate external new model embedding (dimension=5 instead of 3)
        final newEmbedding = List.filled(5, 0.8 + i * 0.01);

        logStep('--- INSERTING CHUNK $i ---');
        // Insert new vector
        await db.insertEmbedding(
          id: chunk['embedding_id'] as String,
          messageId: chunk['message_id'] as String,
          sessionId: chunk['session_id'] as String,
          chunkIndex: chunk['chunk_index'] as int,
          chunkText: chunk['chunk_text'] as String,
          embedding: newEmbedding,
          modelId: 'new_model',
        );

        logStep('--- MARKING CHUNK $i ---');
        // Mark as migrated
        await db.markBackupChunkMigrated(chunk['embedding_id'] as String);
      }

      // 5. Verify Migration Status
      expect(await db.getUnmigratedCount(), 0);

      final verification = await db.verifyMigrationComplete('new_model');
      expect(
        verification.$1,
        isTrue,
        reason: 'allMigrated flag should be true',
      );
      expect(
        verification.$2,
        isTrue,
        reason: 'noStaleData flag should be true',
      );

      // 6. Complete and Cleanup
      await db.dropMigrationBackup();
      expect(await db.hasPendingMigration(), isFalse);

      // 7. Verify the new data is fully searchable with the new dimension
      stats = await db.getEmbeddingStats();
      expect(stats['total_count'], 5);
      expect((stats['models'] as List).first['model_id'], 'new_model');
      expect((stats['models'] as List).first['dimension'], 5);

      logStep('--- SEARCHING ---');
      final searchResults = await db.searchSimilar(
        queryEmbedding: List.filled(
          5,
          0.8,
        ), // Exact match simulation for chunk 0
        topK: 1,
        dimension: 5,
      );
      logStep('--- SEARCH DONE ---');

      expect(searchResults.length, 1);
      expect(searchResults.first['model_id'], 'new_model');
      expect(searchResults.first['dimension'], 5);
    });

    test(
      'Migration verification mechanism catches partial or stale state',
      () async {
        // Setup old data
        await seedEmbeddingData(
          db,
          count: 2,
          modelId: 'old_model',
          dimension: 3,
        );
        await db.createMigrationBackup();

        // Before clearing, both conditions are unmet
        final initialVerif = await db.verifyMigrationComplete('new_model');
        expect(initialVerif.$1, isFalse, reason: 'Not all migrated');
        expect(
          initialVerif.$2,
          isFalse,
          reason: 'Stale data still exists (old_model)',
        );

        await db.clearAndReinitEmbeddings(5);

        final unmigrated = await db.getUnmigratedBackupChunks();

        // Migrate ONLY the FIRST chunk
        await db.insertEmbedding(
          id: unmigrated[0]['embedding_id'] as String,
          messageId: unmigrated[0]['message_id'] as String,
          sessionId: unmigrated[0]['session_id'] as String,
          chunkIndex: unmigrated[0]['chunk_index'] as int,
          chunkText: unmigrated[0]['chunk_text'] as String,
          embedding: List.filled(5, 0.1),
          modelId: 'new_model',
        );
        await db.markBackupChunkMigrated(
          unmigrated[0]['embedding_id'] as String,
        );

        // Verification should catch that 1 chunk is still unmigrated
        final partialVerif = await db.verifyMigrationComplete('new_model');
        expect(partialVerif.$1, isFalse, reason: 'Only 1 of 2 migrated');
        expect(
          partialVerif.$2,
          isTrue,
          reason: 'No stale data (old embeddings were cleared)',
        );

        // Migrate the SECOND chunk but with WRONG model name
        await db.insertEmbedding(
          id: unmigrated[1]['embedding_id'] as String,
          messageId: unmigrated[1]['message_id'] as String,
          sessionId: unmigrated[1]['session_id'] as String,
          chunkIndex: unmigrated[1]['chunk_index'] as int,
          chunkText: unmigrated[1]['chunk_text'] as String,
          embedding: List.filled(5, 0.2),
          modelId: 'wrong_model_xyz',
        );
        await db.markBackupChunkMigrated(
          unmigrated[1]['embedding_id'] as String,
        );

        // All are migrated BUT there is stale data
        final staleVerif = await db.verifyMigrationComplete('new_model');
        expect(staleVerif.$1, isTrue, reason: 'All chunks marked as migrated');
        expect(
          staleVerif.$2,
          isFalse,
          reason: 'One chunk has wrong_model_xyz instead of new_model',
        );
      },
    );
  });
}
