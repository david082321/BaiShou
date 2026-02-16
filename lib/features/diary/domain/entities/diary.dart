import 'package:freezed_annotation/freezed_annotation.dart';

part 'diary.freezed.dart';
part 'diary.g.dart';

@freezed
sealed class Diary with _$Diary {
  const factory Diary({
    required int id,
    required DateTime date,
    required String content,
    @Default([]) List<String> tags,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _Diary;

  factory Diary.fromJson(Map<String, dynamic> json) => _$DiaryFromJson(json);
}
