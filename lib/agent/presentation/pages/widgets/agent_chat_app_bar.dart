import 'package:baishou/agent/presentation/notifiers/agent_chat_state.dart';
import 'package:baishou/agent/presentation/widgets/chat_cost_dialog.dart';
import 'package:flutter/material.dart';

class AgentChatAppBar extends StatelessWidget implements PreferredSizeWidget {
  final bool isMobile;
  final String? assistantName;
  final String currentModel;
  final AgentChatState chatState;
  final VoidCallback? onMenuTap;
  final VoidCallback onTitleTap;

  const AgentChatAppBar({
    super.key,
    required this.isMobile,
    required this.assistantName,
    required this.currentModel,
    required this.chatState,
    required this.onTitleTap,
    this.onMenuTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AppBar(
      leading: isMobile
          ? IconButton(
              icon: const Icon(Icons.menu_rounded),
              onPressed: onMenuTap,
            )
          : null,
      automaticallyImplyLeading: false,
      title: GestureDetector(
        onTap: onTitleTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (currentModel.isNotEmpty || assistantName != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        [
                          if (assistantName != null) '✨ $assistantName',
                          if (currentModel.isNotEmpty) currentModel,
                        ].join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.outline,
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.unfold_more,
                      size: 14,
                      color: theme.colorScheme.outline,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      centerTitle: true,
      elevation: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      actions: [
        if (chatState.totalCostMicros > 0 || chatState.totalInputTokens > 0)
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () => showCostDetailDialog(context, chatState),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.3,
                      ),
                    ),
                  ),
                  child: Text(
                    '\$${(chatState.totalCostMicros / 1000000).toStringAsFixed(4)}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'RobotoMono',
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
