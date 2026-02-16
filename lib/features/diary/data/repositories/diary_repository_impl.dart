import 'package:baishou/core/database/app_database.dart' as db;
import 'package:baishou/features/diary/domain/entities/diary.dart';
import 'package:baishou/features/diary/domain/repositories/diary_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'diary_repository_impl.g.dart';

class DiaryRepositoryImpl implements DiaryRepository {
  final db.AppDatabase _db;

  DiaryRepositoryImpl(this._db);

  @override
  Stream<List<Diary>> watchAllDiaries() {
    return (_db.select(_db.diaries)..orderBy([
          (t) => OrderingTerm(expression: t.date, mode: OrderingMode.desc),
        ]))
        .watch()
        .map((rows) => rows.map(_mapToEntity).toList());
  }

  @override
  Future<Diary?> getDiaryByDate(DateTime date) async {
    // 忽略时间部分，只比较日期
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final query = _db.select(_db.diaries)
      ..where((t) => t.date.isBetweenValues(startOfDay, endOfDay));

    final row = await query.getSingleOrNull();
    return row != null ? _mapToEntity(row) : null;
  }

  @override
  Future<void> saveDiary({
    required DateTime date,
    required String content,
    List<String> tags = const [],
  }) async {
    // 尝试查找当天日记
    final existing = await getDiaryByDate(date);

    final companion = db.DiariesCompanion(
      date: Value(date),
      content: Value(content),
      tags: Value(tags.join(',')),
      updatedAt: Value(DateTime.now()),
    );

    try {
      if (existing != null) {
        // 更新
        await (_db.update(
          _db.diaries,
        )..where((t) => t.id.equals(existing.id))).write(companion);
      } else {
        // 新增
        await _db.into(_db.diaries).insert(companion);
      }
    } catch (e) {
      debugPrint('DiaryRepository: Failed to save diary. Error: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteDiary(int id) {
    return (_db.delete(_db.diaries)..where((t) => t.id.equals(id))).go();
  }

  // 将数据库行转换为领域实体
  Diary _mapToEntity(db.Diary row) {
    return Diary(
      id: row.id,
      date: row.date,
      content: row.content,
      tags: row.tags?.split(',') ?? [], // 简单处理
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
    );
  }
}

@Riverpod(keepAlive: true)
DiaryRepository diaryRepository(Ref ref) {
  final dbInstance = ref.watch(db.appDatabaseProvider);
  return DiaryRepositoryImpl(dbInstance);
}
