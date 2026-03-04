import 'dart:async';
import 'package:baishou/features/diary/domain/entities/diary_meta.dart';
import 'package:baishou/features/index/data/shadow_index_database.dart';
import 'package:baishou/features/index/data/shadow_index_sync_service.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'vault_index_notifier.g.dart';

/// VaultIndex —— 全量日记元数据的内存单一数据源（仿 Obsidian Vault）
///
/// 核心原则：
/// 1. 所有 DiaryMeta 常驻内存（不分页），UI 直接绑定这个列表。
/// 2. App 内 CRUD 操作直接调用 add/update/remove，零延迟刷新 UI。
/// 3. 文件 Watcher 的外部事件（真正的外部删除/修改）才触发重新从 SQLite 加载。
/// 4. 内部写入触发的 Watcher 事件通过"suppress"时间窗口忽略，不重置 UI。
@Riverpod(keepAlive: true)
class VaultIndex extends _$VaultIndex {
  // suppress 路径 → 过期时间：在此时间前忽略同路径的 watcher 事件
  final Map<String, DateTime> _suppressedPaths = {};
  StreamSubscription<String>? _syncSubscription;

  @override
  List<DiaryMeta> build() {
    // 异步初始化：从 SQLite 加载所有元数据
    _init();
    return []; // 初始空列表，_init 完成后通过 state = ... 更新
  }

  Future<void> _init() async {
    await _loadFromDb();
    // 订阅文件 Watcher 事件：只处理外部变化
    final syncService = ref.read(shadowIndexSyncServiceProvider.notifier);
    _syncSubscription = syncService.syncEvents.listen((path) {
      _onExternalChange(path);
    });
    ref.onDispose(() {
      _syncSubscription?.cancel();
    });
  }

  /// 从 SQLite 加载所有元数据（仅启动 + 外部文件变化时调用）
  Future<void> _loadFromDb() async {
    try {
      final dbService = ref.read(shadowIndexDatabaseProvider.notifier);
      final db = await dbService.database;
      final rows = await db.rawQuery('''
        SELECT i.id, i.date, i.updated_at, f.content, f.tags
        FROM journals_index i
        LEFT JOIN journals_fts f ON i.id = f.rowid
        ORDER BY i.date DESC, i.id DESC
      ''');

      final metas = rows.map((row) {
        final content = row['content'] as String? ?? '';
        final tagStr = row['tags'] as String?;
        return DiaryMeta(
          id: row['id'] as int,
          date: DateTime.parse(row['date'] as String),
          preview: content.length > 120 ? content.substring(0, 120) : content,
          tags: tagStr != null && tagStr.isNotEmpty
              ? tagStr.split(',').map((t) => t.trim()).toList()
              : [],
          updatedAt: DateTime.parse(row['updated_at'] as String),
        );
      }).toList();

      state = metas;
      debugPrint('VaultIndex: Loaded ${metas.length} entries from DB');
    } catch (e) {
      debugPrint('VaultIndex: Failed to load from DB: $e');
    }
  }

  /// 外部文件系统变化时重新从 DB 加载
  /// 通过 suppress 机制忽略 App 自身写入触发的 watcher 事件
  void _onExternalChange(String changedPath) {
    // 检查此特定路径是否正在被 suppress
    final now = DateTime.now();
    final expiry = _suppressedPaths[changedPath];

    if (expiry != null && expiry.isAfter(now)) {
      debugPrint(
        'VaultIndex: Ignoring watcher event for $changedPath (internal write suppressed)',
      );
      return;
    }
    debugPrint(
      'VaultIndex: External change detected on $changedPath, reloading from DB',
    );
    _loadFromDb();
  }

  /// 注册一个"suppress"时间窗口：在此时间内忽略该路径的 watcher 事件
  /// 在 App 写文件前调用，防止自身写入被当成外部变化处理
  void suppressPath(
    String path, {
    Duration duration = const Duration(seconds: 3),
  }) {
    _suppressedPaths[path] = DateTime.now().add(duration);
    // 清理过期条目
    _suppressedPaths.removeWhere(
      (_, expiry) => expiry.isBefore(DateTime.now()),
    );
  }

  // ──────────────────────────────────────────────
  // CRUD 操作（App 内调用，直接更新内存，不触发重载）
  // ──────────────────────────────────────────────

  /// 添加或更新一条日记元数据
  void upsert(DiaryMeta meta) {
    final list = List<DiaryMeta>.from(state);
    final idx = list.indexWhere((m) => m.id == meta.id);
    if (idx != -1) {
      list[idx] = meta;
    } else {
      // 找到正确插入位置（date DESC, id DESC）
      final insertAt = list.indexWhere(
        (m) =>
            m.date.isBefore(meta.date) ||
            (m.date.isAtSameMomentAs(meta.date) && m.id < meta.id),
      );
      if (insertAt == -1) {
        list.add(meta);
      } else {
        list.insert(insertAt, meta);
      }
    }
    state = list;
    debugPrint('VaultIndex: upsert id=${meta.id} date=${meta.date}');
  }

  /// 删除一条日记元数据
  void remove(int id) {
    state = state.where((m) => m.id != id).toList();
    debugPrint('VaultIndex: removed id=$id');
  }

  /// 强制从 DB 重新加载（用于开发者选项或调试）
  Future<void> forceReload() => _loadFromDb();
}
