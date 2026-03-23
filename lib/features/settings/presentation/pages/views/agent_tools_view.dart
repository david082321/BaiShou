// Agent 工具管理页面
// 展示所有已注册工具的卡片列表，允许用户开关和配置参数

import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:baishou/agent/tools/tool_repository.dart';
import 'package:baishou/core/services/api_config_service.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:baishou/features/settings/presentation/pages/views/tool_card.dart';

class AgentToolsView extends ConsumerStatefulWidget {
  const AgentToolsView({super.key});

  @override
  ConsumerState<AgentToolsView> createState() => _AgentToolsViewState();
}

class _AgentToolsViewState extends ConsumerState<AgentToolsView> {
  bool _showCommunity = false;

  /// 按分类分组
  Map<String, List<AgentTool>> _groupByCategory(List<AgentTool> tools) {
    final map = <String, List<AgentTool>>{};
    for (final tool in tools) {
      map.putIfAbsent(tool.category, () => []).add(tool);
    }
    return map;
  }

  /// 分类显示名
  String _categoryDisplayName(String category) {
    switch (category) {
      case 'diary':
        return t.settings.agent_tools_category_diary;
      case 'summary':
        return t.settings.agent_tools_category_summary;
      case 'memory':
        return t.settings.agent_tools_category_memory;
      case 'search':
        return t.settings.agent_tools_category_search;
      default:
        return t.settings.agent_tools_category_general;
    }
  }

  /// 分类图标
  IconData _categoryIcon(String category) {
    switch (category) {
      case 'diary':
        return Icons.book_outlined;
      case 'summary':
        return Icons.summarize_outlined;
      case 'memory':
        return Icons.psychology_outlined;
      case 'search':
        return Icons.travel_explore_rounded;
      default:
        return Icons.extension_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final allTools = ref.watch(toolRepositoryProvider)
        .where((tool) => tool.showInSettings)
        .toList();
    final service = ref.watch(apiConfigServiceProvider);
    final colorScheme = Theme.of(context).colorScheme;
    final grouped = _groupByCategory(allTools);

    return Container(
      color: colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题区
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 32, 32, 8),
            child: Row(
              children: [
                Icon(
                  Icons.extension_outlined,
                  size: 28,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Text(
                  t.settings.agent_tools_title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              t.settings.agent_tools_desc,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // 切换滑钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showCommunity = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: !_showCommunity
                              ? colorScheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.verified_outlined,
                              size: 16,
                              color: !_showCommunity
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              t.agent.tools.built_in,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: !_showCommunity
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${allTools.length}',
                              style: TextStyle(
                                fontSize: 11,
                                color: !_showCommunity
                                    ? colorScheme.onPrimary.withValues(alpha: 0.7)
                                    : colorScheme.outline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _showCommunity = true),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: _showCommunity
                              ? colorScheme.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.storefront_outlined,
                              size: 16,
                              color: _showCommunity
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              t.agent.tools.community,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: _showCommunity
                                    ? colorScheme.onPrimary
                                    : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // 工具列表
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: _showCommunity
                  ? _buildCommunityView(colorScheme)
                  : _buildBuiltInView(grouped, service, colorScheme),
            ),
          ),
        ],
      ),
    );
  }

  /// 内置工具视图
  Widget _buildBuiltInView(
    Map<String, List<AgentTool>> grouped,
    ApiConfigService service,
    ColorScheme colorScheme,
  ) {
    return ListView(
      key: const ValueKey('built_in'),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        for (final category in grouped.keys) ...[
          _buildCategoryHeader(category, colorScheme),
          const SizedBox(height: 8),
          ...grouped[category]!.map(
            (tool) => ToolCard(tool: tool, service: service),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  /// 社区工具视图
  Widget _buildCommunityView(ColorScheme colorScheme) {
    return Center(
      key: const ValueKey('community'),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.rocket_launch_outlined,
            size: 56,
            color: colorScheme.outline.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            t.agent.tools.community_market_coming,
            style: TextStyle(
              fontSize: 16,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            t.agent.tools.community_coming_soon,
            style: TextStyle(
              fontSize: 13,
              color: colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  /// 分类标题
  Widget _buildCategoryHeader(String category, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 8),
      child: Row(
        children: [
          Icon(
            _categoryIcon(category),
            size: 18,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            _categoryDisplayName(category),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
