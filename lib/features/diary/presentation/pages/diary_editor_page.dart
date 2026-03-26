import 'package:baishou/core/theme/app_theme.dart';
import 'package:baishou/core/widgets/app_toast.dart';
import 'package:baishou/features/diary/data/repositories/diary_repository_impl.dart';
import 'package:baishou/features/diary/presentation/widgets/markdown_toolbar.dart';
import 'package:baishou/features/diary/presentation/widgets/tag_input_widget.dart';
import 'package:baishou/core/database/tables/summaries.dart';
import 'package:baishou/features/diary/presentation/pages/widgets/diary_editor_app_bar_title.dart';
import 'package:baishou/features/diary/presentation/pages/widgets/diary_editor_content_area.dart';
import 'package:baishou/features/diary/presentation/pages/widgets/diary_exit_dialog.dart';
import 'package:baishou/features/summary/data/repositories/summary_repository_impl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:baishou/features/diary/domain/entities/diary.dart';
import 'package:baishou/features/diary/data/vault_index_notifier.dart';
import 'dart:convert';
import 'package:collection/collection.dart';
import 'package:baishou/agent/rag/embedding_service.dart';
import 'package:baishou/core/services/api_config_service.dart';

/// 日记/总结编辑器页面
/// 支持日记记录（标题、内容、标签）以及对 AI 生成总结的查看与编辑。
class DiaryEditorPage extends ConsumerStatefulWidget {
  final int? diaryId; // 如果是非空，则进入日记编辑模式
  final int? summaryId; // 如果是非空，则进入总结编辑模式，与 diaryId 互斥
  final DateTime? initialDate; // 新建日记时的默认日期
  final bool appendOnLoad; // 如果为 true，加载已有日记后自动在末尾追加 ##### HH:mm 时间戳

  DiaryEditorPage({
    super.key,
    this.diaryId,
    this.summaryId,
    this.initialDate,
    this.appendOnLoad = false,
  }) : assert(diaryId == null || summaryId == null, t.diary.error_dual_edit);

  @override
  ConsumerState<DiaryEditorPage> createState() => _DiaryEditorPageState();
}

class _DiaryEditorPageState extends ConsumerState<DiaryEditorPage> {
  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late TextEditingController _contentController;

  // 标签管理
  final List<String> _tags = [];
  late TextEditingController _tagInputController;
  final FocusNode _tagFocusNode = FocusNode();

  bool _isDirty = false; // 标记内容是否有未保存的更改
  bool _isSaving = false; // 是否正在保存
  bool _isLoading = false; // 标记数据加载状态
  bool _isTransitioning = true; // 标记是否处于路由转场期间（防止 Markdown 阻塞动画）
  bool _isPreview = false; // 标记是否处于 Markdown 预览模式

  // 编辑模式：false=日记，true=总结
  bool get _isSummaryMode => widget.summaryId != null;

  // 内部追踪的实际日记 ID（处理“追加写入”机制）
  int? _currentDiaryId;

  // 总结特定状态
  SummaryType? _summaryType;
  DateTime? _summaryStartDate;
  DateTime? _summaryEndDate;

  @override
  void initState() {
    super.initState();
    final now = widget.initialDate ?? DateTime.now();
    _selectedDate = now;
    _selectedTime = TimeOfDay.fromDateTime(now);
    _contentController = TextEditingController();
    _tagInputController = TextEditingController();

    _contentController.addListener(_markDirty);

    // 设置 200ms 的严格保护期，在此期间不渲染 Markdown（避免转场掉帧）
    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) {
        setState(() => _isTransitioning = false);
      }
    });

    if (widget.diaryId != null) {
      _isLoading = true; // 先设为加载中，防止日期闪烁
      // 延迟到第一帧绘制完成后再加载，避免阻塞路由转场动画（掉帧）
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadDiary(widget.diaryId!);
      });
    } else if (widget.summaryId != null) {
      _isLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadSummary(widget.summaryId!);
      });
    } else {
      // 新增模式：直接创建干净的空白日记（不合并今日旧内容）
      _initNewDiary();
    }
  }

  /// 初始化"新增日记"流程：仅插入当前时间戳，不合并今日旧内容
  Future<void> _initNewDiary() async {
    final timeMark = '##### ${DateFormat('HH:mm').format(DateTime.now())}\n\n';
    _contentController.text = timeMark;
    _contentController.selection = TextSelection.collapsed(
      offset: timeMark.length,
    );
  }

  /// 标记内容已修改
  void _markDirty() {
    if (!_isDirty && !_isLoading) setState(() => _isDirty = true);
  }

  /// 加载日记（日记编辑模式）
  Future<void> _loadDiary(int id) async {
    setState(() => _isLoading = true);
    try {
      final diary = await ref.read(diaryRepositoryProvider).getDiaryById(id);
      if (diary != null && mounted) {
        setState(() {
          _selectedDate = diary.date;
          _selectedTime = TimeOfDay.fromDateTime(diary.date);
        });
        _populateControllers(diary.content, diary.tags);

        // 追加模式：在已有内容末尾插入新的时间戳，方便用户继续记录
        if (widget.appendOnLoad) {
          final timeMark =
              '\n\n##### ${DateFormat('HH:mm').format(DateTime.now())}\n\n';
          final newText = _contentController.text.trimRight() + timeMark;
          _contentController.value = TextEditingValue(
            text: newText,
            selection: TextSelection.collapsed(offset: newText.length),
          );
        }
      }
    } catch (e) {
      debugPrint('Err load diary: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 加载总结数据（总结模式）
  Future<void> _loadSummary(int id) async {
    setState(() => _isLoading = true);
    try {
      final summary = await ref
          .read(summaryRepositoryProvider)
          .getSummaryById(id);
      if (summary != null && mounted) {
        setState(() {
          _selectedDate = summary.startDate;
          _selectedTime = TimeOfDay.fromDateTime(summary.startDate);
          _summaryType = summary.type;
          _summaryStartDate = summary.startDate;
          _summaryEndDate = summary.endDate;
        });
        // 总结没有标题和标签，直接填充内容
        _contentController.text = summary.content;
        _tags.clear();

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _isDirty = false);
        });
      }
    } catch (e) {
      debugPrint('Err load summary: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 填充控制器内容
  /// 将 fullContent 拆分为标题和正文，并加载标签。
  void _populateControllers(String fullContent, List<String> tags) {
    _contentController.text = fullContent;
    _tags.clear();
    _tags.addAll(tags.where((t) => t.trim().isNotEmpty));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _isDirty = false);
    });
  }

  @override
  void dispose() {
    _contentController.dispose();
    _tagInputController.dispose();
    _tagFocusNode.dispose();
    super.dispose();
  }

  // ─── 标签管理 ─────────────────────────────────

  /// 添加标签
  void _addTag(String text) {
    final tag = text.trim();
    if (tag.isNotEmpty && !_tags.contains(tag)) {
      setState(() {
        _tags.add(tag);
        _isDirty = true;
      });
    }
    _tagInputController.clear();
  }

  /// 移除标签
  void _removeTag(String tag) {
    setState(() {
      _tags.remove(tag);
      _isDirty = true;
    });
  }

  // ─── 工具栏操作 ────────────────────────────────

  /// 在光标处插入 Markdown 文本
  void _insertText(String prefix, [String suffix = '']) {
    final text = _contentController.text;
    final selection = _contentController.selection;

    if (selection.start == -1 || selection.end == -1) {
      final newText = '$text\n$prefix$suffix';
      _contentController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: newText.length - suffix.length,
        ),
      );
      return;
    }

    final selectedText = text.substring(selection.start, selection.end);
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      '$prefix$selectedText$suffix',
    );

    _contentController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: selection.start + prefix.length + selectedText.length,
      ),
    );
  }

  // ─── 保存 ───────────────────────────────────────────

  /// 执行保存操作
  Future<void> _save() async {
    final content = _contentController.text.trim();

    if (content.isEmpty) {
      AppToast.showSuccess(context, t.diary.editor_hint);
      return;
    }

    Diary? savedDiary; // 保存成功后要带回列表页的实体

    setState(() => _isSaving = true);

    try {
      if (_isSummaryMode) {
        final summary = await ref
            .read(summaryRepositoryProvider)
            .getSummaryById(widget.summaryId!);
        if (summary != null) {
          await ref
              .read(summaryRepositoryProvider)
              .updateSummary(
                summary.copyWith(
                  content: content,
                  startDate: _summaryStartDate,
                  endDate: _summaryEndDate,
                ),
              );
        }
      } else {
        final repo = ref.read(diaryRepositoryProvider);

        // 优先使用内存索引 (VaultIndex) 查找当天的日记，这比通过 Repository 查询 SQLite 更快且更可靠
        final metas = ref.read(vaultIndexProvider).value ?? [];
        final existingMeta = metas.firstWhereOrNull(
          (m) => DateUtils.isSameDay(m.date, _selectedDate),
        );

        if (widget.diaryId != null ||
            _currentDiaryId != null ||
            existingMeta != null) {
          // ── 编辑/追加模式 ──
          final targetId =
              widget.diaryId ?? _currentDiaryId ?? existingMeta!.id;
          final diary = await repo.getDiaryById(targetId);

          if (diary != null) {
            String finalContent = content;
            List<String> finalTags = _tags;

            // 如果是通过 existingMeta 发现的（但当前页面还没绑定过这个 ID），则执行追加合并
            if (widget.diaryId == null && _currentDiaryId == null) {
              final oldContent = diary.content.trimRight();
              finalContent = oldContent.isEmpty
                  ? content
                  : '$oldContent\n\n$content';
              finalTags = {...diary.tags, ..._tags}.toList();
            }

            savedDiary = await repo.saveDiary(
              id: diary.id,
              content: finalContent,
              date: _selectedDate,
              tags: finalTags,
            );
          }
        } else {
          // ── 纯新增模式 ──
          savedDiary = await repo.saveDiary(
            content: content,
            date: _selectedDate,
            tags: _tags,
          );
        }

        // 保存成功后，更新当前页面的追踪 ID，防止短时间内再次点击产生 ID 冲突
        _currentDiaryId = savedDiary?.id;

        // 自动将新日记内容加入 RAG 记忆中（无需等待）
        if (savedDiary != null) {
          final embeddingService = ref.read(embeddingServiceProvider);
          final apiConfig = ref.read(apiConfigServiceProvider);
          if (apiConfig.ragEnabled && embeddingService.isConfigured) {
            final dateLabel = DateFormat('yyyy-MM-dd').format(savedDiary.date);
            embeddingService.reEmbedText(
              text: '$dateLabel: ${savedDiary.content}',
              sourceType: 'diary',
              sourceId: savedDiary.id.toString(),
              groupId: 'diary_auto',
              metadataJson: jsonEncode({'updated_at': savedDiary.updatedAt.millisecondsSinceEpoch}),
            ).catchError((e) {
              debugPrint('Diary auto-embedding failed: $e');
            });
          }
        }
      }

      if (mounted) {
        setState(() => _isDirty = false);
        AppToast.showSuccess(context, t.diary.saved_toast);
        context.pop(savedDiary);
      }
    } catch (e) {
      debugPrint('Error saving: $e');
      if (mounted) {
        AppToast.showError(
          context,
          t.diary.save_failed(e: e.toString()),
          backgroundColor: Colors.red[900],
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty && !_isSaving,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;

        if (_isSaving) {
          AppToast.show(context, t.common.saving);
          return;
        }

        final shouldPop = await showDiaryExitConfirmationDialog(context);
        if (shouldPop && context.mounted) {
          // 关键修复：确认退出时，必须先清除拦截条件 (_isDirty = false)，避免重复拦截或卡死
          setState(() {
            _isDirty = false;
          });
          
          // 使用原生的 Navigator.pop 代替 GoRouter 的 pop，因为 GoRouter 
          // 在被 PopScope 拦截过的异步上下文中可能有栈状态不同步导致 Nothing to pop 的问题。
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            context.go('/diary');
          }
        }
      },
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: AppBar(
              centerTitle: true,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new),
                onPressed: () async {
                  // 手动触发 pop，利用底层的 PopScope 机制来判断是否需要弹窗
                  final nav = Navigator.of(context);
                  bool canPop = nav.canPop();
                  debugPrint('AppBar back pressed, canPop: $canPop');
                  await nav.maybePop();
                },
              ),
              title: DiaryEditorAppBarTitle(
                isSummaryMode: _isSummaryMode,
                summaryType: _summaryType,
                selectedDate: _selectedDate,
                summaryStartDate: _summaryStartDate,
                summaryEndDate: _summaryEndDate,
                onDateChanged: (date) {
                  setState(() {
                    _selectedDate = date;
                    _isDirty = true;
                  });
                },
                onSummaryDateChanged: (start, end) {
                  setState(() {
                    _summaryStartDate = start;
                    _summaryEndDate = end;
                    _isDirty = true;
                  });
                },
              ),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, right: 16),
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primary,
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                    ),
                    child: Text(t.common.save),
                  ),
                ),
              ],
            ),
            body: (_isLoading || _isTransitioning)
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 16,
                          ),
                          children: [
                            // 标签（仅日记模式）
                            if (!_isSummaryMode) ...[
                              const SizedBox(height: 8),
                              TagInputWidget(
                                tags: _tags,
                                controller: _tagInputController,
                                focusNode: _tagFocusNode,
                                onAddTag: _addTag,
                                onRemoveTag: _removeTag,
                              ),
                            ],

                            const SizedBox(height: 16),

                            DiaryEditorContentArea(
                              isPreview: _isPreview,
                              contentController: _contentController,
                            ),
                          ],
                        ),
                      ),
                      // Markdown 格式化工具栏
                      MarkdownToolbar(
                        isPreview: _isPreview,
                        onTogglePreview: () {
                          setState(() => _isPreview = !_isPreview);
                          if (_isPreview) FocusScope.of(context).unfocus();
                        },
                        onHideKeyboard: () => FocusScope.of(context).unfocus(),
                        onInsertText: _insertText,
                      ),
                    ],
                  ),
          ),
          if (_isSaving)
            Container(
              color: Colors.black26,
              child: Center(
                child: Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CircularProgressIndicator(),
                        const SizedBox(height: 16),
                        Text(
                          t.common.saving,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
