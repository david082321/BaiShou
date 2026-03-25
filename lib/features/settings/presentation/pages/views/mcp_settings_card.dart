import 'package:baishou/core/services/api_config_service.dart';
import 'package:baishou/core/services/mcp_server_service.dart';
import 'package:baishou/core/widgets/app_toast.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// MCP Server 设置卡片
class McpSettingsCard extends ConsumerStatefulWidget {
  const McpSettingsCard({super.key});

  @override
  ConsumerState<McpSettingsCard> createState() => _McpSettingsCardState();
}

class _McpSettingsCardState extends ConsumerState<McpSettingsCard> {
  late TextEditingController _portController;
  bool _isStarting = false;

  @override
  void initState() {
    super.initState();
    final configService = ref.read(apiConfigServiceProvider);
    _portController = TextEditingController(
      text: configService.mcpPort.toString(),
    );
  }

  @override
  void dispose() {
    _portController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final configService = ref.read(apiConfigServiceProvider);
    final mcpService = ref.read(mcpServerServiceProvider);
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(
              Icons.hub_outlined,
              color: mcpService.isRunning ? theme.colorScheme.primary : null,
            ),
            title: Text(t.settings.mcp_title),
            subtitle: Text(
              mcpService.isRunning
                  ? t.settings.mcp_running(port: configService.mcpPort)
                  : t.settings.mcp_desc,
            ),
            value: configService.mcpEnabled,
            onChanged: _isStarting ? null : (v) => _toggleMcp(v),
          ),
          if (configService.mcpEnabled) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.lan_outlined, size: 20),
                  const SizedBox(width: 12),
                  Text(t.settings.mcp_port, style: theme.textTheme.bodyMedium),
                  const Spacer(),
                  SizedBox(
                    width: 100,
                    child: TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onSubmitted: (value) => _updatePort(value),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                    tooltip: t.settings.mcp_restart,
                    onPressed: mcpService.isRunning
                        ? () => _updatePort(_portController.text)
                        : null,
                  ),
                ],
              ),
            ),
            // 状态指示
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 12),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: mcpService.isRunning ? Colors.green : Colors.grey,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    mcpService.isRunning
                        ? 'http://localhost:${configService.mcpPort}/mcp'
                        : t.settings.mcp_stopped,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _toggleMcp(bool enabled) async {
    setState(() => _isStarting = true);
    final configService = ref.read(apiConfigServiceProvider);
    final mcpService = ref.read(mcpServerServiceProvider);

    await configService.setMcpEnabled(enabled);

    try {
      if (enabled) {
        await mcpService.start();
      } else {
        await mcpService.stop();
      }
    } catch (e) {
      if (mounted) {
        AppToast.showError(context, 'MCP Server error: $e');
        await configService.setMcpEnabled(false);
      }
    }

    if (mounted) setState(() => _isStarting = false);
  }

  Future<void> _updatePort(String value) async {
    final port = int.tryParse(value);
    final configService = ref.read(apiConfigServiceProvider);
    final currentPort = configService.mcpPort;

    if (port == null || port < 1024 || port > 65535) {
      _portController.text = currentPort.toString();
      return;
    }

    if (port != currentPort) {
      // 端口改变：写入配置后，mcpAutoStarterProvider 会自动触发重启
      await configService.setMcpPort(port);
    } else {
      // 端口未改变：显式手动重启
      if (configService.mcpEnabled) {
        await _restartServer();
      }
    }
  }

  Future<void> _restartServer() async {
    setState(() => _isStarting = true);
    try {
      await ref.read(mcpServerServiceProvider).restart();
    } catch (e) {
      if (mounted) {
        AppToast.showError(context, 'MCP restart failed: $e');
      }
    }
    if (mounted) setState(() => _isStarting = false);
  }
}
