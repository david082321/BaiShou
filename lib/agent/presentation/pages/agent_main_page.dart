/// Agent 主页面
///
/// 侧边栏两区布局：功能选项区 + 对话历史区

import 'dart:io';

import 'package:baishou/agent/database/agent_database.dart';
import 'package:baishou/agent/session/session_manager.dart';
import 'package:baishou/agent/presentation/notifiers/agent_chat_notifier.dart';
import 'package:baishou/agent/presentation/notifiers/assistant_notifier.dart';
import 'package:baishou/agent/presentation/pages/agent_chat_page.dart';
import 'package:baishou/agent/presentation/widgets/agent_sidebar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AgentMainPage extends ConsumerStatefulWidget {
  const AgentMainPage({super.key});

  @override
  ConsumerState<AgentMainPage> createState() => _AgentMainPageState();
}

class _AgentMainPageState extends ConsumerState<AgentMainPage> {
  List<AgentSession>? _sessions;
  bool _isLoading = true;
  String? _selectedSessionId;
  AgentAssistant? _currentAssistant;
  bool _isSidebarCollapsed = false;

  @override
  void initState() {
    super.initState();
    _initAssistantAndSessions();
  }

  Future<void> _initAssistantAndSessions() async {
    final service = ref.read(assistantServiceProvider);
    final assistant = await service.ensureDefaultAssistant();
    if (mounted) {
      setState(() => _currentAssistant = assistant);
      await _loadSessions();
    }
  }

  Future<void> _loadSessions() async {
    if (_currentAssistant == null) return;
    setState(() => _isLoading = true);
    try {
      final manager = ref.read(sessionManagerProvider);
      final sessions = await manager.getSessionsByAssistant(
        _currentAssistant!.id,
      );

      setState(() {
        _sessions = sessions;
        if ((_selectedSessionId == null ||
                !sessions.any((s) => s.id == _selectedSessionId)) &&
            sessions.isNotEmpty) {
          _selectedSessionId = sessions.first.id;
        }
        _isLoading = false;
      });

      if (_selectedSessionId != null && _selectedSessionId!.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final notifier = ref.read(agentChatProvider.notifier);
          notifier.loadSession(_selectedSessionId!);
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshSessionList() async {
    if (_currentAssistant == null) return;
    try {
      final manager = ref.read(sessionManagerProvider);
      final sessions = await manager.getSessionsByAssistant(
        _currentAssistant!.id,
      );
      if (mounted) {
        setState(() => _sessions = sessions);
      }
    } catch (_) {}
  }

  void _createNewSession() {
    final notifier = ref.read(agentChatProvider.notifier);
    notifier.clearChat();
    if (_currentAssistant != null) {
      notifier.setCurrentAssistantId(_currentAssistant!.id);
    }
    setState(() => _selectedSessionId = null);
  }

  void _switchAssistant(AgentAssistant assistant) {
    setState(() {
      _currentAssistant = assistant;
      _selectedSessionId = null;
      _sessions = null;
    });
    ref.read(agentChatProvider.notifier).clearChat();
    ref.read(agentChatProvider.notifier).setCurrentAssistantId(assistant.id);
    _loadSessions();
  }

  @override
  Widget build(BuildContext context) {
    // 监听 sessionId 变化
    ref.listen<AgentChatState>(agentChatProvider, (prev, next) {
      if (prev?.sessionId != next.sessionId && next.sessionId != null) {
        if (_selectedSessionId == null) {
          setState(() => _selectedSessionId = next.sessionId);
          _refreshSessionList();
        }
      }
    });

    final theme = Theme.of(context);
    final isDesktop =
        MediaQuery.of(context).size.width >= 700 ||
        Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isLinux;

    final sidebar = AgentSidebar(
      currentAssistant: _currentAssistant,
      sessions: _sessions,
      isLoading: _isLoading,
      selectedSessionId: _selectedSessionId,
      onSessionSelected: (id) {
        setState(() => _selectedSessionId = id);
        ref.read(agentChatProvider.notifier).loadSession(id);
      },
      onNewSession: _createNewSession,
      onAssistantSwitched: _switchAssistant,
      onSessionsChanged: _loadSessions,
      onCollapse: () => setState(() => _isSidebarCollapsed = true),
    );

    if (!isDesktop) {
      return Scaffold(
        body: const AgentChatPage(),
        drawerEdgeDragWidth: 120,
        drawer: Drawer(child: sidebar),
      );
    }

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: Row(
        children: [
          if (!_isSidebarCollapsed)
            SizedBox(width: 280, child: sidebar)
          else
            _buildCollapsedSidebar(theme),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 10,
                    offset: const Offset(-5, 0),
                  ),
                ],
              ),
              child: const AgentChatPage(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollapsedSidebar(ThemeData theme) {
    return Container(
      width: 40,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          const SizedBox(height: 20),
          IconButton(
            icon: const Icon(Icons.menu_rounded, size: 20),
            tooltip: '展开侧边栏',
            onPressed: () => setState(() => _isSidebarCollapsed = false),
          ),
        ],
      ),
    );
  }
}
