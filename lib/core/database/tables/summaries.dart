import 'package:drift/drift.dart';

/// 总结类型枚举
enum SummaryType { weekly, monthly, quarterly, yearly }

/// 总结表
/// 存储AI生成的周记、月报、年鉴
class Summaries extends Table {
  /// 主键 ID (自增)
  IntColumn get id => integer().autoIncrement()();

  /// 总结类型 (WEEKLY, MONTHLY, etc.)
  TextColumn get type => textEnum<SummaryType>()();

  /// 覆盖的起始日期
  DateTimeColumn get startDate => dateTime()();

  /// 覆盖的结束日期
  DateTimeColumn get endDate => dateTime()();

  /// 总结内容 (Markdown格式)
  TextColumn get content => text()();

  /// 生成时间
  DateTimeColumn get generatedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// 关联的原始数据ID列表 (JSON存储或逗号分隔，用于溯源)
  /// 在MVP阶段，我们暂时只存储 coverage range，不强制关联每一条ID
  TextColumn get sourceIds => text().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {type, startDate, endDate}, // 确保同一时间段的同一类型总结唯一
  ];
}
