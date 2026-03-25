/// BaiShou MCP Server — 通过 MCP 协议暴露白守工具给外部 AI
///
/// 基于 shelf HTTP 服务器实现 MCP JSON-RPC 2.0 协议。
/// 默认端口 31004，支持用户自定义。

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:baishou/agent/tools/agent_tool.dart';
import 'package:baishou/agent/tools/built_in_tool_provider.dart';
import 'package:baishou/core/services/api_config_service.dart';
import 'package:baishou/core/storage/storage_path_provider.dart';
import 'package:baishou/core/storage/vault_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';

part 'mcp_server_service.g.dart';

/// MCP 协议版本
const _mcpProtocolVersion = '2024-11-05';

/// MCP Server 实现
class McpServerService {
  final Ref _ref;
  HttpServer? _server;
  bool _running = false;

  McpServerService(this._ref);

  bool get isRunning => _running;
  int get port => _ref.read(apiConfigServiceProvider).mcpPort;

  /// 启动 MCP Server
  Future<void> start() async {
    if (_running) return;

    final configService = _ref.read(apiConfigServiceProvider);
    final mcpPort = configService.mcpPort;

    final router = Router()
      ..post('/mcp', _handleJsonRpc)
      ..get('/mcp', _handleGetInfo);

    final handler = const shelf.Pipeline()
        .addMiddleware(shelf.logRequests())
        .addMiddleware(_corsMiddleware())
        .addHandler(router.call);

    try {
      _server = await shelf_io.serve(
        handler,
        InternetAddress.loopbackIPv4,
        mcpPort,
      );
      _running = true;
      debugPrint('MCP Server started on http://localhost:$mcpPort/mcp');
    } catch (e) {
      debugPrint('MCP Server failed to start: $e');
      rethrow;
    }
  }

  /// 停止 MCP Server
  Future<void> stop() async {
    if (!_running) return;
    await _server?.close(force: true);
    _server = null;
    _running = false;
    debugPrint('MCP Server stopped');
  }

  /// 重启（适用于端口更换后）
  Future<void> restart() async {
    await stop();
    await start();
  }

  /// CORS 中间件（允许本地客户端跨域）
  shelf.Middleware _corsMiddleware() {
    return (innerHandler) {
      return (request) async {
        if (request.method == 'OPTIONS') {
          return shelf.Response.ok('', headers: _corsHeaders);
        }
        final response = await innerHandler(request);
        return response.change(headers: _corsHeaders);
      };
    };
  }

  static const _corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
  };

  /// GET /mcp → 返回服务器信息
  Future<shelf.Response> _handleGetInfo(shelf.Request request) async {
    return shelf.Response.ok(
      jsonEncode({
        'name': 'BaiShou MCP Server',
        'version': '1.0.0',
        'protocolVersion': _mcpProtocolVersion,
        'description': 'BaiShou AI Companion Diary - MCP Interface',
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// POST /mcp → 处理 JSON-RPC 2.0 请求
  Future<shelf.Response> _handleJsonRpc(shelf.Request request) async {
    String? body;
    try {
      body = await request.readAsString();
      final jsonBody = jsonDecode(body) as Map<String, dynamic>;

      final method = jsonBody['method'] as String?;
      final id = jsonBody['id'];
      final params = jsonBody['params'] as Map<String, dynamic>? ?? {};

      final result = switch (method) {
        'initialize' => _handleInitialize(params),
        'tools/list' => _handleToolsList(params),
        'tools/call' => await _handleToolsCall(params),
        'ping' => <String, dynamic>{},
        _ => throw _JsonRpcError(-32601, 'Method not found: $method'),
      };

      return _jsonRpcResponse(id, result);
    } on _JsonRpcError catch (e) {
      final id = body != null ? _extractId(body) : null;
      return _jsonRpcErrorResponse(id, e.code, e.message);
    } catch (e) {
      return _jsonRpcErrorResponse(null, -32700, 'Parse error: $e');
    }
  }

  /// initialize → 返回服务器信息和能力
  Map<String, dynamic> _handleInitialize(Map<String, dynamic> params) {
    return {
      'protocolVersion': _mcpProtocolVersion,
      'capabilities': {
        'tools': {'listChanged': false},
      },
      'serverInfo': {
        'name': 'BaiShou MCP Server',
        'version': '1.0.0',
      },
      'instructions':
          'BaiShou is an AI companion diary app. Use the tools below '
          'to read/edit diaries, search memories, and manage stored knowledge.',
    };
  }

  /// tools/list → 返回所有可用工具
  Map<String, dynamic> _handleToolsList(Map<String, dynamic> params) {
    final tools = _getAgentTools();
    return {
      'tools': tools.map((tool) => _agentToolToMcpTool(tool)).toList(),
    };
  }

  /// tools/call → 执行指定工具
  Future<Map<String, dynamic>> _handleToolsCall(
    Map<String, dynamic> params,
  ) async {
    final toolName = params['name'] as String?;
    if (toolName == null) {
      throw _JsonRpcError(-32602, 'Missing required parameter: name');
    }

    // 去掉 baishou_ 前缀以匹配 AgentTool ID
    final agentToolId = toolName.startsWith('baishou_')
        ? toolName.substring('baishou_'.length)
        : toolName;

    final tools = _getAgentTools();
    final tool = tools.where((t) => t.id == agentToolId).firstOrNull;
    if (tool == null) {
      throw _JsonRpcError(-32602, 'Unknown tool: $toolName');
    }

    final arguments = params['arguments'] as Map<String, dynamic>? ?? {};

    // 获取当前活跃 Vault 路径
    final vaultPath = await _getActiveVaultPath();

    final context = ToolContext(
      sessionId: 'mcp-external',
      vaultPath: vaultPath,
    );

    try {
      final result = await tool.execute(arguments, context);
      return {
        'content': [
          {'type': 'text', 'text': result.output},
        ],
        'isError': !result.success,
      };
    } catch (e) {
      return {
        'content': [
          {'type': 'text', 'text': 'Tool execution failed: $e'},
        ],
        'isError': true,
      };
    }
  }

  /// 获取当前活跃 Vault 的路径
  Future<String> _getActiveVaultPath() async {
    try {
      // VaultService 是 AsyncNotifier<VaultInfo?>，通过 provider 获取 AsyncValue
      final asyncVault = _ref.read(vaultServiceProvider);
      final activeVault = asyncVault.value;
      if (activeVault == null) return '';

      final storageService = _ref.read(storagePathServiceProvider);
      final vaultDir = await storageService.getVaultDirectory(activeVault.name);
      return vaultDir.path;
    } catch (_) {
      return '';
    }
  }

  /// 获取所有 AgentTool 实例
  List<AgentTool> _getAgentTools() {
    return _ref.read(builtInToolsProvider);
  }

  /// 将 AgentTool 转换为 MCP Tool 定义
  Map<String, dynamic> _agentToolToMcpTool(AgentTool tool) {
    return {
      'name': 'baishou_${tool.id}',
      'description': tool.description,
      'inputSchema': tool.parameterSchema,
    };
  }

  /// JSON-RPC 成功响应
  shelf.Response _jsonRpcResponse(dynamic id, Map<String, dynamic> result) {
    return shelf.Response.ok(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// JSON-RPC 错误响应
  shelf.Response _jsonRpcErrorResponse(dynamic id, int code, String message) {
    return shelf.Response.ok(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  /// 从请求体中提取 id
  dynamic _extractId(String body) {
    try {
      return (jsonDecode(body) as Map<String, dynamic>)['id'];
    } catch (_) {
      return null;
    }
  }
}

/// JSON-RPC 错误
class _JsonRpcError {
  final int code;
  final String message;
  _JsonRpcError(this.code, this.message);
}

/// Riverpod Provider
@Riverpod(keepAlive: true)
McpServerService mcpServerService(Ref ref) {
  final service = McpServerService(ref);
  ref.onDispose(() => service.stop());
  return service;
}
