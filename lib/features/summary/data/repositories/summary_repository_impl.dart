import 'package:baishou/core/database/app_database.dart' as db;
import 'package:baishou/core/database/tables/summaries.dart';
import 'package:baishou/features/summary/domain/entities/summary.dart';
import 'package:baishou/features/summary/domain/repositories/summary_repository.dart';
import 'package:baishou/features/storage/domain/services/summary_file_service.dart';
import 'package:baishou/features/summary/domain/services/summary_sync_service.dart';
import 'package:baishou/features/storage/domain/services/file_state_scheduler.dart';
import 'package:drift/drift.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'summary_repository_impl.g.dart';

class SummaryRepositoryImpl implements SummaryRepository {
  final db.AppDatabase _db;
  final SummaryFileService _fileService;
  final Ref _ref;

  SummaryRepositoryImpl(this._db, this._fileService, this._ref) {
    // 延迟初始化同步，避免循环依赖
    Future.microtask(
      () => _ref.read(summarySyncServiceProvider.notifier).fullScanArchives(),
    );
  }

  @override
  Stream<List<Summary>> watchSummaries(
    SummaryType type, {
    DateTime? start,
    DateTime? end,
  }) {
    final query = _db.select(_db.summaries)
      ..where((t) => t.type.equals(type.name));

    if (start != null) {
      // 筛选 startDate >= start
      query.where((t) => t.startDate.isBiggerOrEqualValue(start));
    }
    if (end != null) {
      // 筛选 startDate <= end
      query.where((t) => t.startDate.isSmallerOrEqualValue(end));
    }

    return (query..orderBy([
          (t) => OrderingTerm(expression: t.startDate, mode: OrderingMode.desc),
        ]))
        .watch()
        .map((rows) => rows.map(_mapToEntity).toList());
  }

  @override
  Future<Summary?> getSummaryById(int id) async {
    final query = _db.select(_db.summaries)..where((t) => t.id.equals(id));
    final row = await query.getSingleOrNull();
    return row != null ? _mapToEntity(row) : null;
  }

  @override
  Future<List<Summary>> getSummaries({DateTime? start, DateTime? end}) async {
    final query = _db.select(_db.summaries);
    if (start != null) {
      query.where((t) => t.startDate.isBiggerOrEqualValue(start));
    }
    if (end != null) {
      query.where((t) => t.endDate.isSmallerOrEqualValue(end));
    }
    query.orderBy([
      (t) => OrderingTerm(expression: t.startDate, mode: OrderingMode.desc),
    ]);

    final rows = await query.get();
    return rows.map(_mapToEntity).toList();
  }

  @override
  Future<Summary?> getSummaryByTypeAndDate(
    SummaryType type,
    DateTime start,
    DateTime end,
  ) async {
    final query = _db.select(_db.summaries)
      ..where((t) => t.type.equalsValue(type))
      ..where((t) => t.startDate.equals(start))
      ..where((t) => t.endDate.equals(end));

    final row = await query.getSingleOrNull();
    return row != null ? _mapToEntity(row) : null;
  }

  @override
  Future<int> addSummary({
    required SummaryType type,
    required DateTime startDate,
    required DateTime endDate,
    required String content,
    List<String> sourceIds = const [],
  }) async {
    final now = DateTime.now();
    final summary = Summary(
      id: 0, // 数据库生成
      type: type,
      startDate: startDate,
      endDate: endDate,
      content: content,
      generatedAt: now,
      sourceIds: sourceIds,
    );

    // 1. 写入数据库
    final id = await _db
        .into(_db.summaries)
        .insert(
          db.SummariesCompanion(
            type: Value(type),
            startDate: Value(startDate),
            endDate: Value(endDate),
            content: Value(content),
            sourceIds: Value(sourceIds.join(',')),
            generatedAt: Value(now),
          ),
        );

    // 2. 写入物理文件
    final filePath = await _fileService.getSummaryFilePath(type, startDate);
    _ref.read(fileStateSchedulerProvider.notifier).suppressPath(filePath);
    await _fileService.writeSummary(summary.copyWith(id: id));

    return id;
  }

  @override
  Future<void> batchAddSummaries(List<Summary> summaries) async {
    await _db.batch((batch) {
      for (final summary in summaries) {
        batch.insert(
          _db.summaries,
          db.SummariesCompanion(
            type: Value(summary.type),
            startDate: Value(summary.startDate),
            endDate: Value(summary.endDate),
            content: Value(summary.content),
            sourceIds: Value(summary.sourceIds.join(',')),
            generatedAt: Value(DateTime.now()),
          ),
        );
      }
    });

    // 批量写入物理文件
    for (final s in summaries) {
      final filePath = await _fileService.getSummaryFilePath(
        s.type,
        s.startDate,
      );
      _ref.read(fileStateSchedulerProvider.notifier).suppressPath(filePath);
      await _fileService.writeSummary(s);
    }
  }

  @override
  Future<void> updateSummary(Summary summary) async {
    await (_db.update(
      _db.summaries,
    )..where((t) => t.id.equals(summary.id))).write(
      db.SummariesCompanion(
        content: Value(summary.content),
        // 其他字段通常不会更新
      ),
    );
    // 更新物理文件
    final filePath = await _fileService.getSummaryFilePath(
      summary.type,
      summary.startDate,
    );
    _ref.read(fileStateSchedulerProvider.notifier).suppressPath(filePath);
    await _fileService.writeSummary(summary);
  }

  @override
  Future<void> deleteSummary(int id) async {
    final summary = await getSummaryById(id);
    if (summary != null) {
      await _fileService.deleteSummaryFile(summary.type, summary.startDate);
    }
    await (_db.delete(_db.summaries)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> deleteAllSummaries() async {
    await _fileService.clearAllArchives();
    await _db.delete(_db.summaries).go();
  }

  Summary _mapToEntity(db.Summary row) {
    return Summary(
      id: row.id,
      type: row.type,
      startDate: row.startDate,
      endDate: row.endDate,
      content: row.content,
      generatedAt: row.generatedAt,
      sourceIds:
          row.sourceIds
              ?.split(',')
              .where((s) => s.trim().isNotEmpty)
              .toList() ??
          [],
    );
  }
}

@Riverpod(keepAlive: true)
SummaryRepository summaryRepository(Ref ref) {
  final dbInstance = ref.watch(db.appDatabaseProvider);
  final fileService = ref.watch(summaryFileServiceProvider.notifier);
  return SummaryRepositoryImpl(dbInstance, fileService, ref);
}
