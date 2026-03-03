import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:baishou/core/theme/app_theme.dart';
import 'package:baishou/core/widgets/year_month_picker_sheet.dart';
import 'package:baishou/features/diary/data/repositories/diary_repository_impl.dart';
import 'package:baishou/features/diary/data/vault_index_notifier.dart';
import 'package:baishou/features/diary/domain/entities/diary.dart';
import 'package:baishou/features/diary/domain/entities/diary_meta.dart';
import 'package:baishou/features/diary/presentation/widgets/diary_card.dart';
import 'package:collection/collection.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:baishou/core/localization/locale_service.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

/// 日记列表页面
/// 架构：UI 直接绑定内存 VaultIndex（Obsidian 模式），无游标分页，无 StreamSubscription。
/// VaultIndex 全量持有元数据，CRUD 直接更新内存，watcher 只处理外部变化。
class DiaryListPage extends ConsumerStatefulWidget {
  const DiaryListPage({super.key});

  @override
  ConsumerState<DiaryListPage> createState() => _DiaryListPageState();
}

class _DiaryListPageState extends ConsumerState<DiaryListPage> {
  DateTime? _selectedMonth;
  String _searchQuery = '';
  bool _isSearching = false;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(localeProvider);

    // 直接绑定内存 VaultIndex：增删改不重置列表，不闪烁，不丢失滚动位置
    final allMeta = ref.watch(vaultIndexProvider);

    bool isMobile = false;
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        isMobile = true;
      }
    } catch (e) {}
    final bool isDesktop = !isMobile;

    return SafeArea(
      top: isMobile,
      bottom: false,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          centerTitle: false,
          backgroundColor: Theme.of(
            context,
          ).colorScheme.surface.withOpacity(0.8),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          title: _isSearching && !isDesktop
              ? TextField(
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: t.common.search_hint,
                    border: InputBorder.none,
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                )
              : _buildHeader(context, isDesktop),
          actions: isDesktop
              ? null
              : [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _isSearching = !_isSearching;
                        if (!_isSearching) _searchQuery = '';
                      });
                    },
                    icon: Icon(_isSearching ? Icons.close : Icons.search),
                  ),
                ],
        ),
        body: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  child: Builder(
                    builder: (context) {
                      // VaultIndex 初始为空列表（await loading），直接显示 loading
                      if (allMeta.isEmpty &&
                          ref.read(vaultIndexProvider).isEmpty) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final filteredMeta = _getFilteredMeta(allMeta);

                      if (filteredMeta.isEmpty) {
                        return _buildEmptyState(context);
                      }

                      return GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onDoubleTap: () {
                          if (_scrollController.hasClients) {
                            _scrollController.animateTo(
                              0,
                              duration: const Duration(milliseconds: 400),
                              curve: Curves.easeOut,
                            );
                          }
                        },
                        child: AlignedGridView.count(
                          controller: _scrollController,
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.symmetric(
                            horizontal: isDesktop ? 32 : 16,
                            vertical: 24,
                          ),
                          crossAxisCount: _getCrossAxisCount(context),
                          mainAxisSpacing: 24,
                          crossAxisSpacing: 24,
                          itemCount: filteredMeta.length,
                          itemBuilder: (context, index) {
                            final meta = filteredMeta[index];
                            return _DiaryMetaCard(
                              meta: meta,
                              onDelete: () =>
                                  _confirmDelete(context, ref, meta),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),

            // Floating Action Buttons (Desktop)
            if (isDesktop)
              Positioned(
                bottom: 32,
                right: 32,
                child: _buildDesktopFABs(context, allMeta),
              ),
          ],
        ),
        floatingActionButton: isDesktop
            ? null
            : FloatingActionButton(
                onPressed: () => context.push(
                  '/diary/edit?date=${DateTime.now().toIso8601String()}',
                ),
                backgroundColor: AppTheme.primary,
                shape: const CircleBorder(),
                child: const Icon(Icons.add, color: Colors.white, size: 32),
              ),
      ),
    );
  }

  int _getCrossAxisCount(BuildContext context) {
    double width = MediaQuery.of(context).size.width;
    if (width > 1200) return 3;
    if (width > 700) return 2;
    return 1;
  }

  Widget _buildDesktopFABs(BuildContext context, List<DiaryMeta> allMeta) {
    final todayMeta = allMeta.firstWhereOrNull(
      (m) => DateUtils.isSameDay(m.date, DateTime.now()),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Edit Today button
        Material(
          color: Theme.of(context).colorScheme.surface,
          shape: const CircleBorder(),
          elevation: 4,
          shadowColor: Colors.black.withOpacity(0.15),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              if (todayMeta != null) {
                context.push('/diary/edit?id=${todayMeta.id}');
              } else {
                context.push(
                  '/diary/edit?date=${DateTime.now().toIso8601String()}',
                );
              }
            },
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              child: Icon(
                Icons.edit_note,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 24,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Add Entry button
        Material(
          color: AppTheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 8,
          shadowColor: AppTheme.primary.withOpacity(0.4),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              context.push(
                '/diary/edit?date=${DateTime.now().toIso8601String()}',
              );
            },
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              child: const Icon(Icons.add, color: Colors.white, size: 32),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, bool isDesktop) {
    final theme = Theme.of(context);
    final isEn = LocaleSettings.instance.currentLocale == AppLocale.en;
    final now = DateTime.now();
    final dateToDisplay = _selectedMonth ?? now;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 16 : 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () => _showMonthPicker(context),
            child: Row(
              children: [
                Text(
                  _selectedMonth == null
                      ? t.diary.all_diaries
                      : '${dateToDisplay.year}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_selectedMonth != null) ...[
                  const SizedBox(width: 4),
                  Text(
                    isEn
                        ? DateFormat('MMM').format(dateToDisplay)
                        : '${dateToDisplay.month}月',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
                Icon(Icons.arrow_drop_down, color: theme.colorScheme.onSurface),
              ],
            ),
          ),
          if (isDesktop)
            Row(
              children: [
                Container(
                  width: 200,
                  height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withOpacity(0.5),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.search,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          onChanged: (val) =>
                              setState(() => _searchQuery = val),
                          decoration: InputDecoration(
                            hintText: t.common.search_hint,
                            hintStyle: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, DiaryMeta meta) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.diary.delete_confirm_title),
        content: Text(t.diary.delete_confirm_content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t.common.cancel),
          ),
          TextButton(
            onPressed: () {
              ref.read(diaryRepositoryProvider).deleteDiary(meta.id);
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(t.common.delete),
          ),
        ],
      ),
    );
  }

  void _showMonthPicker(BuildContext context) async {
    final result = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => YearMonthPickerSheet(initialDate: _selectedMonth),
    );

    if (result != null) {
      setState(() {
        if (result.year == 0) {
          _selectedMonth = null;
        } else {
          _selectedMonth = result;
        }
      });
    }
  }

  List<DiaryMeta> _getFilteredMeta(List<DiaryMeta> allMeta) {
    var metas = allMeta;
    if (_selectedMonth != null) {
      metas = metas.where((m) {
        return m.date.year == _selectedMonth!.year &&
            m.date.month == _selectedMonth!.month;
      }).toList();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      metas = metas.where((m) => m.preview.toLowerCase().contains(q)).toList();
    }
    return metas;
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.edit_note,
            size: 80,
            color: AppTheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 16),
          Text(
            _selectedMonth != null
                ? t.diary.no_diaries_month
                : t.diary.no_diaries,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.grey),
          ),
          if (_selectedMonth != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => setState(() => _selectedMonth = null),
              child: Text(t.common.view_all),
            ),
          ],
        ],
      ),
    );
  }
}

/// 轻量卡片：直接接收 DiaryMeta，点击时去编辑（只加载内容）
class _DiaryMetaCard extends ConsumerWidget {
  final DiaryMeta meta;
  final VoidCallback? onDelete;

  const _DiaryMetaCard({required this.meta, this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 构造一个只有元数据（内容用 preview 代替）的 Diary 传给 DiaryCard
    // 点击时会打开编辑器，编辑器会从 getDiaryById 读取完整内容
    final diaryStub = Diary(
      id: meta.id,
      date: meta.date,
      content: meta.preview,
      tags: meta.tags,
      createdAt: meta.updatedAt,
      updatedAt: meta.updatedAt,
    );

    return DiaryCard(
      diary: diaryStub,
      onDelete: onDelete,
      // 编辑后的原地更新：VaultIndex 由 repository 在 saveDiary 中调用 upsert 完成
      // 这里不需要 onUpdated 回调（VaultIndex 直接触发整个列表重绘）
    );
  }
}
