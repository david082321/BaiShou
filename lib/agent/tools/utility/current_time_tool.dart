/// CurrentTimeTool — 获取用户当前的精确时间
///
/// Agent 通过此工具获知用户所在时区的当前日期和时间。
/// 这是一个无参数的轻量级工具，Agent 在需要时间信息时应主动调用。

import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';

class CurrentTimeTool extends AgentTool {
  @override
  String get id => 'current_time';

  @override
  String get displayName => t.agent.tools.current_time;

  @override
  String get category => 'utility';

  @override
  IconData get icon => Icons.access_time_rounded;

  @override
  bool get canBeDisabled => false;

  @override
  bool get showInSettings => false;

  @override
  String get description =>
      'Get the current date and time in the user\'s local timezone. '
      'Call this tool when you need to know the exact current time, '
      'such as before writing diary entries, scheduling events, '
      'or when the user asks "what time is it".';

  @override
  Map<String, dynamic> get parameterSchema => {
    'type': 'object',
    'properties': {},
  };

  @override
  Future<ToolResult> execute(
    Map<String, dynamic> arguments,
    ToolContext context,
  ) async {
    final now = DateTime.now();

    final year = now.year;
    final month = now.month.toString().padLeft(2, '0');
    final day = now.day.toString().padLeft(2, '0');
    final hour = now.hour.toString().padLeft(2, '0');
    final minute = now.minute.toString().padLeft(2, '0');
    final second = now.second.toString().padLeft(2, '0');

    final weekdays = [
      'Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday',
    ];
    final weekday = weekdays[now.weekday - 1];

    final tzOffset = now.timeZoneOffset;
    final tzSign = tzOffset.isNegative ? '-' : '+';
    final tzHours = tzOffset.inHours.abs().toString().padLeft(2, '0');
    final tzMinutes = (tzOffset.inMinutes.abs() % 60).toString().padLeft(2, '0');

    return ToolResult(
      output:
          'Current time: $year-$month-$day $hour:$minute:$second ($weekday)\n'
          'Timezone: UTC$tzSign$tzHours:$tzMinutes (${now.timeZoneName})',
      success: true,
      metadata: {
        'date': '$year-$month-$day',
        'time': '$hour:$minute:$second',
        'weekday': weekday,
        'timezone': 'UTC$tzSign$tzHours:$tzMinutes',
      },
    );
  }
}
