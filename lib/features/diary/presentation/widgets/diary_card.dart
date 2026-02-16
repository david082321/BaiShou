import 'package:baishou/core/theme/app_theme.dart';
import 'package:baishou/features/diary/domain/entities/diary.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class DiaryCard extends StatelessWidget {
  final Diary diary;

  const DiaryCard({super.key, required this.diary});

  @override
  Widget build(BuildContext context) {
    // 格式化日期
    final dateStr = DateFormat('MM月dd日').format(diary.date);
    final weekDay = DateFormat(
      'EEEE',
      'zh_CN',
    ).format(diary.date); // 需要配置 locale，暂时用英文或数字

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.sakuraPink.withOpacity(0.3), width: 1),
      ),
      child: InkWell(
        onTap: () {
          // 跳转到编辑页，带上日记日期
          context.push('/diary/edit?date=${diary.date.toIso8601String()}');
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.sakuraPink.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      dateStr,
                      style: const TextStyle(
                        color: AppTheme.sakuraDeep,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    weekDay, // 暂时显示英文，后续添加 intl 初始化
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                diary.content,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.5,
                  color: Colors.black87,
                ),
              ),
              if (diary.tags.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: diary.tags.map((tag) {
                    return Text(
                      '#$tag',
                      style: TextStyle(fontSize: 12, color: Colors.indigo[300]),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
