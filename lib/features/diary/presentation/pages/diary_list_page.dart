import 'package:baishou/core/theme/app_theme.dart';
import 'package:baishou/features/diary/data/repositories/diary_repository_impl.dart';
import 'package:baishou/features/diary/presentation/widgets/diary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class DiaryListPage extends ConsumerWidget {
  const DiaryListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 监听日记流
    final diaryStream = ref.watch(diaryRepositoryProvider).watchAllDiaries();

    return Scaffold(
      appBar: AppBar(
        title: const Text('白守'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_month),
            onPressed: () {
              // TODO: 跳转日历视图
            },
          ),
        ],
      ),
      body: StreamBuilder(
        stream: diaryStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('出错了: ${snapshot.error}'));
          }

          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final diaries = snapshot.data!;

          if (diaries.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.edit_note,
                    size: 80,
                    color: AppTheme.sakuraPink.withOpacity(0.5),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '还没有日记哦',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  const Text('点击右下角，记录今天的故事吧'),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: diaries.length,
            itemBuilder: (context, index) {
              final diary = diaries[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DiaryCard(diary: diary),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          context.push('/diary/edit');
        },
        label: const Text('写日记'),
        icon: const Icon(Icons.add),
        backgroundColor: AppTheme.sakuraDeep,
        foregroundColor: Colors.white,
      ),
    );
  }
}
