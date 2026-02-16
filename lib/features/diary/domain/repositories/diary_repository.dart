import 'package:baishou/features/diary/domain/entities/diary.dart';

abstract class DiaryRepository {
  // 获取所有日记 (按日期倒序)
  Stream<List<Diary>> watchAllDiaries();

  // 获取某一天的日记
  Future<Diary?> getDiaryByDate(DateTime date);

  // 保存日记 (新增或更新)
  Future<void> saveDiary({
    required DateTime date,
    required String content,
    List<String> tags = const [],
  });

  // 删除日记
  Future<void> deleteDiary(int id);
}
