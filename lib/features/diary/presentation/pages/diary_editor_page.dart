import 'package:baishou/core/theme/app_theme.dart';
import 'package:baishou/features/diary/data/repositories/diary_repository_impl.dart';
import 'package:baishou/features/diary/domain/entities/diary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class DiaryEditorPage extends ConsumerStatefulWidget {
  final DateTime date;
  final Diary? initialDiary;

  const DiaryEditorPage({super.key, required this.date, this.initialDiary});

  @override
  ConsumerState<DiaryEditorPage> createState() => _DiaryEditorPageState();
}

class _DiaryEditorPageState extends ConsumerState<DiaryEditorPage> {
  late TextEditingController _contentController;
  late TextEditingController _tagsController;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    _contentController = TextEditingController(
      text: widget.initialDiary?.content ?? '',
    );
    _tagsController = TextEditingController(
      text: widget.initialDiary?.tags.join(', ') ?? '',
    );

    _contentController.addListener(_onTextChanged);
    _tagsController.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    if (!_isDirty) {
      setState(() {
        _isDirty = true;
      });
    }
  }

  @override
  void dispose() {
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('日记内容不能为空哦')));
      return;
    }

    final tags = _tagsController.text
        .split(RegExp(r'[,，]')) // 支持中英文逗号
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    try {
      await ref
          .read(diaryRepositoryProvider)
          .saveDiary(date: widget.date, content: content, tags: tags);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('日记保存成功！✨')));
        context.pop();
      }
    } catch (e, stackTrace) {
      debugPrint('Error saving diary: $e');
      debugPrint(stackTrace.toString());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('yyyy年MM月dd日').format(widget.date);

    return Scaffold(
      appBar: AppBar(
        title: Text(dateStr),
        actions: [
          IconButton(
            onPressed: _save,
            icon: const Icon(Icons.check),
            tooltip: '保存',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // 标签输入
            TextField(
              controller: _tagsController,
              decoration: InputDecoration(
                hintText: '添加标签（用逗号分隔，如：开心, 骑车）',
                prefixIcon: const Icon(Icons.tag, color: AppTheme.sakuraPink),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: AppTheme.sakuraPink.withOpacity(0.1),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
              ),
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            // 内容输入 (Markdown 风格)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _contentController,
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  decoration: const InputDecoration(
                    hintText: '今天发生了什么？写下来吧...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(16),
                  ),
                  style: const TextStyle(fontSize: 16, height: 1.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
