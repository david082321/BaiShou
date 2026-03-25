// 工具仓库 — 纯整合层
//
// 不 import 任何具体工具类。只调用两个接口：
// 1. builtInToolsProvider → 内置工具
// 2. communityToolsProvider → 社区工具（当前为空）
// 合并后返回统一的工具列表，供 UI 和 Agent 运行时使用。

import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:baishou/agent/tools/built_in_tool_provider.dart';
import 'package:baishou/agent/tools/community_tool_provider.dart';
import 'package:baishou/agent/models/ai_provider_model.dart';
import 'package:baishou/core/services/api_config_service.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tool_repository.g.dart';

/// 工具仓库（纯整合层）
///
/// 职责：
/// 1. 从 builtIn 和 community 两个来源获取工具
/// 2. 合并后提供 allTools / enabledTools
/// 3. 构建 ToolRegistry 供 AgentRunner 使用
///
/// 不持有任何具体工具类的引用，完全通过接口解耦。
@riverpod
class ToolRepository extends _$ToolRepository {
  @override
  List<AgentTool> build() {
    final builtIn = ref.watch(builtInToolsProvider);
    final community = ref.watch(communityToolsProvider);
    return [...builtIn, ...community];
  }

  /// 所有工具（内置 + 社区）
  List<AgentTool> get allTools => state;

  /// 启用的工具（过滤掉被用户禁用的）
  List<AgentTool> get enabledTools {
    final apiConfig = ref.read(apiConfigServiceProvider);
    final disabledIds = apiConfig.disabledToolIds;
    final ragEnabled = apiConfig.ragEnabled;
    // RAG 关闭时自动排除 memory_store 和 vector_search
    const ragToolIds = {'memory_store', 'vector_search'};

    // 根据活跃 Provider 的 webSearchMode 决定是否启用外部搜索工具
    final activeProvider = apiConfig.getActiveProvider();
    final searchMode = activeProvider?.webSearchMode ?? WebSearchMode.off;
    // 外部搜索工具 ID（仅在 tavily 模式下启用）
    const externalSearchToolIds = {'web_search', 'url_read'};

    return state.where((t) {
      if (disabledIds.contains(t.id)) return false;
      if (!ragEnabled && ragToolIds.contains(t.id)) return false;
      // 非 tavily 模式时，自动排除外部搜索工具
      if (searchMode != WebSearchMode.tavily && externalSearchToolIds.contains(t.id)) return false;
      return true;
    }).toList();
  }

  /// 构建 ToolRegistry（供 AgentRunner 使用）
  ToolRegistry buildRegistry() {
    final registry = ToolRegistry();
    for (final tool in enabledTools) {
      registry.register(tool);
    }
    return registry;
  }
}
