/// 工具卡片组件
///
/// 展示单个 AgentTool 的信息、开关和可配参数

import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:baishou/agent/tools/tool_config_param.dart';
import 'package:baishou/core/services/api_config_service.dart';
import 'package:flutter/material.dart';

/// 工具卡片（StatefulWidget 便于局部刷新开关和参数）
class ToolCard extends StatefulWidget {
  final AgentTool tool;
  final ApiConfigService service;

  const ToolCard({super.key, required this.tool, required this.service});

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  AgentTool get tool => widget.tool;
  ApiConfigService get service => widget.service;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isEnabled = service.isToolEnabled(tool.id);
    final hasParams = tool.configurableParams.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      color: isEnabled
          ? colorScheme.surfaceContainerLow
          : colorScheme.surfaceContainerLow.withValues(alpha: 0.4),
      child: Column(
        children: [
          // 主行：图标+名称+描述+开关
          Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 8, hasParams ? 0 : 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 图标
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isEnabled
                        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                        : colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    tool.icon,
                    size: 20,
                    color: isEnabled
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                // 名称+描述
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            tool.displayName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: isEnabled
                                  ? colorScheme.onSurface
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              tool.id,
                              style: TextStyle(
                                fontSize: 10,
                                color: colorScheme.onSurfaceVariant,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // 开关
                Switch(
                  value: isEnabled,
                  onChanged: (val) async {
                    await service.toggleToolEnabled(tool.id, val);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          // 可配参数区
          if (hasParams && isEnabled) ...[
            Divider(
              height: 1,
              indent: 16,
              endIndent: 16,
              color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                children: tool.configurableParams.map((param) {
                  return _buildParamControl(param, colorScheme);
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 参数控件
  Widget _buildParamControl(ToolConfigParam param, ColorScheme colorScheme) {
    final currentValue =
        service.getToolConfigValue(tool.id, param.key) ?? param.defaultValue;

    switch (param.type) {
      case ParamType.integer:
        final intVal =
            (currentValue is int) ? currentValue : param.defaultValue as int;
        return Row(
          children: [
            if (param.icon != null) ...[
              Icon(param.icon, size: 16, color: colorScheme.onSurfaceVariant),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                param.label,
                style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
              ),
            ),
            Container(
              height: 32,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: intVal <= (param.min ?? 1)
                        ? null
                        : () async {
                            await service.setToolConfigValue(
                              tool.id, param.key, intVal - 1);
                            setState(() {});
                          },
                    child: Container(
                      width: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          right: BorderSide(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      child: Icon(
                        Icons.remove,
                        size: 16,
                        color: intVal <= (param.min ?? 1)
                            ? colorScheme.onSurface.withValues(alpha: 0.2)
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 44,
                    child: TextField(
                      controller: TextEditingController(text: '$intVal'),
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 2, vertical: 6),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (value) async {
                        final parsed = int.tryParse(value);
                        if (parsed != null) {
                          final clamped = parsed.clamp(
                            param.min ?? 1, param.max ?? 50);
                          await service.setToolConfigValue(
                            tool.id, param.key, clamped);
                          setState(() {});
                        }
                      },
                    ),
                  ),
                  GestureDetector(
                    onTap: intVal >= (param.max ?? 50)
                        ? null
                        : () async {
                            await service.setToolConfigValue(
                              tool.id, param.key, intVal + 1);
                            setState(() {});
                          },
                    child: Container(
                      width: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          left: BorderSide(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                      ),
                      child: Icon(
                        Icons.add,
                        size: 16,
                        color: intVal >= (param.max ?? 50)
                            ? colorScheme.onSurface.withValues(alpha: 0.2)
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      case ParamType.boolean:
        return Row(
          children: [
            Expanded(
              child: Text(
                param.label,
                style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
              ),
            ),
            Switch(
              value: currentValue == true,
              onChanged: (val) async {
                await service.setToolConfigValue(tool.id, param.key, val);
                setState(() {});
              },
            ),
          ],
        );
      case ParamType.string:
        return const SizedBox.shrink();
    }
  }
}
