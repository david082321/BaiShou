import 'package:baishou/agent/tools/search/web_search_service.dart';
import 'package:baishou/core/services/api_config_service.dart';
import 'package:baishou/core/widgets/app_toast.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 网络搜索设置页面
/// 网络搜索设置视图，左侧/顶部可以选择引擎，下方配置参数
class WebSearchSettingsView extends ConsumerStatefulWidget {
  const WebSearchSettingsView({super.key});

  @override
  ConsumerState<WebSearchSettingsView> createState() =>
      _WebSearchSettingsViewState();
}

class _WebSearchSettingsViewState extends ConsumerState<WebSearchSettingsView> {
  late TextEditingController _apiKeyController;
  bool _isObscure = true;

  @override
  void initState() {
    super.initState();
    final config = ref.read(apiConfigServiceProvider);
    _apiKeyController = TextEditingController(text: config.tavilyApiKey);
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // watch 会在配置改变时重建
    final config = ref.watch(apiConfigServiceProvider);
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: config,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _buildEngineSelectionCard(context, config, theme),
            const SizedBox(height: 16),
            _buildApiConfigurationCard(context, config, theme),
            const SizedBox(height: 16),
            _buildPreferencesCard(context, config, theme),
          ],
        );
      },
    );
  }

  Widget _buildEngineSelectionCard(
    BuildContext context,
    ApiConfigService config,
    ThemeData theme,
  ) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: 16,
              top: 16,
              right: 16,
              bottom: 8,
            ),
            child: Text(
              t.agent.tools.param_search_engine,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          RadioListTile<String>(
            title: Text(t.settings.web_search_engine_duckduckgo),
            subtitle: Text(
              t.settings.web_search_engine_duckduckgo_desc,
            ),
            value: SearchEngine.duckduckgo.name,
            groupValue: config.webSearchEngine,
            onChanged: (val) {
              if (val != null) config.setWebSearchEngine(val);
            },
          ),
          RadioListTile<String>(
            title: Text(t.settings.web_search_engine_tavily),
            subtitle: Text(
              t.settings.web_search_engine_tavily_desc,
            ),
            value: SearchEngine.tavily.name,
            groupValue: config.webSearchEngine,
            onChanged: (val) {
              if (val != null) config.setWebSearchEngine(val);
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildApiConfigurationCard(
    BuildContext context,
    ApiConfigService config,
    ThemeData theme,
  ) {
    if (config.webSearchEngine != SearchEngine.tavily.name) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.agent.tools.param_tavily_api_key,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              t.agent.tools.param_tavily_api_key_desc,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _apiKeyController,
              obscureText: _isObscure,
              decoration: InputDecoration(
                hintText: 'tvly-xxxxxx',
                prefixIcon: const Icon(Icons.key),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(
                        _isObscure ? Icons.visibility : Icons.visibility_off,
                      ),
                      tooltip: _isObscure
                          ? t.agent.tools.param_search_engine
                          : '',
                      onPressed: () => setState(() => _isObscure = !_isObscure),
                    ),
                    IconButton(
                      icon: const Icon(Icons.save),
                      tooltip: t.common.save,
                      onPressed: () {
                        config.setTavilyApiKey(_apiKeyController.text);
                        AppToast.showSuccess(context, t.common.success);
                      },
                    ),
                  ],
                ),
              ),
              onSubmitted: (val) {
                config.setTavilyApiKey(val);
                AppToast.showSuccess(context, t.common.success);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreferencesCard(
    BuildContext context,
    ApiConfigService config,
    ThemeData theme,
  ) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: 16,
              top: 16,
              right: 16,
              bottom: 8,
            ),
            child: Text(
              t.settings.general,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          _buildSliderRow(
            context,
            theme,
            icon: Icons.format_list_numbered,
            title: t.agent.tools.param_max_results,
            desc: t.agent.tools.param_max_results_desc,
            value: config.webSearchMaxResults.toDouble(),
            min: 1,
            max: 30,

            onChanged: (val) => config.setWebSearchMaxResults(val.toInt()),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.auto_awesome),
            title: Text(t.agent.tools.param_rag_enabled),
            subtitle: Text(t.agent.tools.param_rag_enabled_desc),
            value: config.webSearchRagEnabled,
            onChanged: (val) {
              config.setWebSearchRagEnabled(val);
            },
          ),
          if (config.webSearchRagEnabled) ...[
            const Divider(height: 1),
            _buildSliderRow(
              context,
              theme,
              icon: Icons.compress,
              title: t.agent.tools.param_rag_max_chunks,
              desc: t.agent.tools.param_rag_max_chunks_desc,
              value: config.webSearchRagMaxChunks.toDouble(),
              min: 1,
              max: 50,
  
              onChanged: (val) => config.setWebSearchRagMaxChunks(val.toInt()),
            ),
            const Divider(height: 1),
            _buildSliderRow(
              context,
              theme,
              icon: Icons.library_books,
              title: t.agent.tools.param_rag_chunks_per_source,
              desc: t.agent.tools.param_rag_chunks_per_source_desc,
              value: config.webSearchRagChunksPerSource.toDouble(),
              min: 1,
              max: 20,
  
              onChanged: (val) =>
                  config.setWebSearchRagChunksPerSource(val.toInt()),
            ),
          ] else ...[
            const Divider(height: 1),
            _buildSliderRow(
              context,
              theme,
              icon: Icons.short_text,
              title: t.agent.tools.param_plain_snippet_length,
              desc: t.agent.tools.param_plain_snippet_length_desc,
              value: config.webSearchPlainSnippetLength.toDouble(),
              min: 500,
              max: 30000,
  
              onChanged: (val) =>
                  config.setWebSearchPlainSnippetLength(val.toInt()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSliderRow(
    BuildContext context,
    ThemeData theme, {
    required IconData icon,
    required String title,
    required String desc,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：icon + 标题 + 描述
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title),
                    Text(
                      desc,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 第二行：滑动条 + 数值
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                  ),
                  child: Slider(
                    value: value,
                    min: min,
                    max: max,
                    onChanged: onChanged,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  value.toInt().toString(),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
