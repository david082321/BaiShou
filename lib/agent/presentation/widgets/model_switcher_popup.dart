/// \u6a21\u578b\u5feb\u901f\u5207\u6362\u5f39\u51fa\u5c42
///
/// \u684c\u9762\u7aef\uff1a\u4ee5 Popup Dialog \u5f62\u5f0f\u5f39\u51fa\uff0c\u5e26\u641c\u7d22\u548c\u5206\u7ec4
/// \u79fb\u52a8\u7aef\uff1a\u4ee5 BottomSheet \u5f62\u5f0f\u5f39\u51fa\uff0c\u5e26\u641c\u7d22\u548c\u5206\u7ec4

import 'dart:io';
import 'package:baishou/agent/models/ai_provider_model.dart';
import 'package:baishou/features/settings/presentation/widgets/provider_icon.dart';
import 'package:flutter/material.dart';

/// \u663e\u793a\u6a21\u578b\u5207\u6362\u5668
///
/// \u8fd4\u56de (providerId, modelId) \u5143\u7ec4\uff0c\u5982\u679c\u7528\u6237\u53d6\u6d88\u5219\u8fd4\u56de null
Future<(String, String)?> showModelSwitcherPopup({
  required BuildContext context,
  required List<AiProviderModel> providers,
  required String? currentProviderId,
  required String? currentModelId,
}) async {
  final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  if (isDesktop) {
    return _showDesktopPopup(
      context: context,
      providers: providers,
      currentProviderId: currentProviderId,
      currentModelId: currentModelId,
    );
  } else {
    return _showMobileSheet(
      context: context,
      providers: providers,
      currentProviderId: currentProviderId,
      currentModelId: currentModelId,
    );
  }
}

/// \u684c\u9762\u7aef\uff1aDialog \u5f39\u7a97
Future<(String, String)?> _showDesktopPopup({
  required BuildContext context,
  required List<AiProviderModel> providers,
  required String? currentProviderId,
  required String? currentModelId,
}) {
  return showDialog<(String, String)>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 420,
        height: 500,
        child: _ModelSwitcherContent(
          providers: providers,
          currentProviderId: currentProviderId,
          currentModelId: currentModelId,
          onSelect: (pid, mid) => Navigator.pop(ctx, (pid, mid)),
        ),
      ),
    ),
  );
}

/// \u79fb\u52a8\u7aef\uff1aBottomSheet
Future<(String, String)?> _showMobileSheet({
  required BuildContext context,
  required List<AiProviderModel> providers,
  required String? currentProviderId,
  required String? currentModelId,
}) {
  return showModalBottomSheet<(String, String)>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (_, scrollController) => _ModelSwitcherContent(
        providers: providers,
        currentProviderId: currentProviderId,
        currentModelId: currentModelId,
        scrollController: scrollController,
        onSelect: (pid, mid) => Navigator.pop(ctx, (pid, mid)),
      ),
    ),
  );
}

// \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
// \u5185\u5bb9\u7ec4\u4ef6\uff08\u684c\u9762/\u79fb\u52a8\u5171\u7528\uff09
// \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550

class _ModelSwitcherContent extends StatefulWidget {
  final List<AiProviderModel> providers;
  final String? currentProviderId;
  final String? currentModelId;
  final ScrollController? scrollController;
  final void Function(String providerId, String modelId) onSelect;

  const _ModelSwitcherContent({
    required this.providers,
    this.currentProviderId,
    this.currentModelId,
    this.scrollController,
    required this.onSelect,
  });

  @override
  State<_ModelSwitcherContent> createState() => _ModelSwitcherContentState();
}

class _ModelSwitcherContentState extends State<_ModelSwitcherContent> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // \u7b5b\u9009 providers \u548c models
    final filteredProviders = <AiProviderModel>[];
    final filteredModels = <String, List<String>>{};

    for (final provider in widget.providers) {
      final modelList = provider.enabledModels.isNotEmpty
          ? provider.enabledModels
          : provider.models;

      final matched = _searchQuery.isEmpty
          ? modelList
          : modelList
              .where((m) => m.toLowerCase().contains(_searchQuery))
              .toList();

      if (matched.isNotEmpty) {
        filteredProviders.add(provider);
        filteredModels[provider.id] = matched;
      }
    }

    return Column(
      children: [
        // \u2500\u2500 \u6807\u9898\u680f \u2500\u2500
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Row(
            children: [
              Icon(Icons.swap_vert_rounded,
                  size: 20, color: colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                '切换模型',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),

        // \u2500\u2500 \u641c\u7d22\u6846 \u2500\u2500
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
            decoration: InputDecoration(
              hintText: '搜索模型...',
              hintStyle: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
              prefixIcon:
                  Icon(Icons.search_rounded, size: 18, color: colorScheme.outline),
              filled: true,
              fillColor:
                  colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              isDense: true,
            ),
            style: theme.textTheme.bodySmall,
          ),
        ),

        // \u2500\u2500 \u6a21\u578b\u5206\u7ec4\u5217\u8868 \u2500\u2500
        Expanded(
          child: filteredProviders.isEmpty
              ? Center(
                  child: Text(
                    '没有匹配的模型',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.outline,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: widget.scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: filteredProviders.length,
                  itemBuilder: (ctx, i) {
                    final provider = filteredProviders[i];
                    final models = filteredModels[provider.id] ?? [];

                    return _ProviderGroup(
                      provider: provider,
                      models: models,
                      currentProviderId: widget.currentProviderId,
                      currentModelId: widget.currentModelId,
                      onSelect: widget.onSelect,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

// \u2500\u2500\u2500 Provider \u5206\u7ec4\u5361\u7247 \u2500\u2500\u2500

class _ProviderGroup extends StatelessWidget {
  final AiProviderModel provider;
  final List<String> models;
  final String? currentProviderId;
  final String? currentModelId;
  final void Function(String providerId, String modelId) onSelect;

  const _ProviderGroup({
    required this.provider,
    required this.models,
    this.currentProviderId,
    this.currentModelId,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isCurrentProvider = provider.id == currentProviderId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Provider \u5934\u90e8
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Row(
              children: [
                getProviderIcon(provider.type, size: 16),
                const SizedBox(width: 8),
                Text(
                  provider.name,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${models.length}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.outline,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // \u6a21\u578b\u5217\u8868
          ...models.map((modelId) {
            final isSelected =
                isCurrentProvider && modelId == currentModelId;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelect(provider.id, modelId),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primaryContainer.withValues(alpha: 0.3)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      // \u6a21\u578b\u56fe\u6807\uff08\u590d\u7528 provider icon\uff09
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: getProviderIcon(provider.type, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          modelId,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected)
                        Icon(
                          Icons.check_circle_rounded,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
