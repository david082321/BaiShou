/// 日记元数据卡片
///
/// 轻量卡片：接收 DiaryMeta，点击时跳转到编辑器。

import 'package:baishou/features/diary/domain/entities/diary.dart';
import 'package:baishou/features/diary/domain/entities/diary_meta.dart';
import 'package:baishou/features/diary/presentation/widgets/diary_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class DiaryMetaCard extends ConsumerWidget {
  final DiaryMeta meta;
  final VoidCallback? onDelete;

  const DiaryMetaCard({super.key, required this.meta, this.onDelete});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
    );
  }
}
