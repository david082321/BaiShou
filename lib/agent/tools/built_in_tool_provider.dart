import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/agent/session/session_manager.dart';
import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:baishou/agent/tools/diary/diary_delete_tool.dart';
import 'package:baishou/agent/tools/diary/diary_edit_tool.dart';
import 'package:baishou/agent/tools/diary/diary_list_tool.dart';
import 'package:baishou/agent/tools/diary/diary_read_tool.dart';
import 'package:baishou/agent/tools/diary/diary_search_tool.dart';
import 'package:baishou/agent/tools/memory/memory_delete_tool.dart';
import 'package:baishou/agent/tools/memory/memory_store_tool.dart';
import 'package:baishou/agent/tools/memory/vector_search_tool.dart';
import 'package:baishou/agent/tools/message/message_search_tool.dart';
import 'package:baishou/agent/tools/search/web_search_tool.dart';
import 'package:baishou/agent/tools/search/url_read_tool.dart';
import 'package:baishou/agent/tools/summary/summary_read_tool.dart';
import 'package:baishou/core/database/app_database.dart';
import 'package:baishou/core/services/api_config_service.dart';
import 'package:baishou/features/index/data/shadow_index_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'built_in_tool_provider.g.dart';

/// 提供所有内置工具实例
///
/// 新增内置工具时只需在此处添加，其他地方无需改动。
@riverpod
List<AgentTool> builtInTools(Ref ref) {
  return [
    // ── 日记工具 ──
    DiaryReadTool(),
    DiaryEditTool(),
    DiaryDeleteTool(),
    DiaryListTool(),
    DiarySearchTool(ref.read(shadowIndexDatabaseProvider.notifier)),

    // ── 总结工具 ──
    SummaryReadTool(ref.read(appDatabaseProvider)),

    // ── 记忆工具 ──
    MessageSearchTool(ref.read(sessionManagerProvider)),

    // ── 语义搜索工具 ──
    VectorSearchTool(ref.read(agentDatabaseProvider)),

    // ── 记忆存储 / 删除工具 ──
    MemoryStoreTool(),
    MemoryDeleteTool(ref.read(agentDatabaseProvider)),

    // ── 网络搜索工具 ──
    WebSearchTool(ref.read(apiConfigServiceProvider)),

    // ── 网页读取工具 ──
    UrlReadTool(),
  ];
}
