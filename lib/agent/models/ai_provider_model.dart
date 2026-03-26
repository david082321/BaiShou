import 'dart:convert';

enum ProviderType {
  openai,
  anthropic,
  gemini,
  deepseek,
  kimi,
  ollama,
  siliconflow,
  openrouter,
  dashscope,
  doubao,
  grok,
  mistral,
  lmstudio,
  custom,
}

/// 网络搜索模式
enum WebSearchMode {
  /// 关闭搜索
  off,

  /// 使用 Provider 内置搜索（OpenAI/Anthropic/Gemini 原生支持）
  builtin,

  /// 使用外部搜索工具（Tavily / DuckDuckGo 等，所有模型可用）
  tool,
}

/// 根据 ProviderType 返回默认的搜索模式
WebSearchMode defaultWebSearchMode(ProviderType type) => switch (type) {
  ProviderType.openai => WebSearchMode.builtin,
  ProviderType.anthropic => WebSearchMode.builtin,
  ProviderType.gemini => WebSearchMode.builtin,
  _ => WebSearchMode.tool,
};

class AiProviderModel {
  final String id;
  final String name;
  final ProviderType type;
  final String apiKey;
  final String baseUrl;
  final List<String> models;
  final String defaultDialogueModel;
  final String defaultNamingModel;
  final bool isEnabled;
  final List<String> enabledModels;
  final String? notes;
  final bool isSystem;
  final int sortOrder;
  final WebSearchMode webSearchMode;

  AiProviderModel({
    required this.id,
    required this.name,
    required this.type,
    this.apiKey = '',
    this.baseUrl = '',
    this.models = const [],
    this.defaultDialogueModel = '',
    this.defaultNamingModel = '',
    this.isEnabled = true,
    this.enabledModels = const [],
    this.notes,
    this.isSystem = true,
    this.sortOrder = 0,
    WebSearchMode? webSearchMode,
  }) : webSearchMode = webSearchMode ?? defaultWebSearchMode(type);

  AiProviderModel copyWith({
    String? id,
    String? name,
    ProviderType? type,
    String? apiKey,
    String? baseUrl,
    List<String>? models,
    String? defaultDialogueModel,
    String? defaultNamingModel,
    bool? isEnabled,
    List<String>? enabledModels,
    String? notes,
    bool? isSystem,
    int? sortOrder,
    WebSearchMode? webSearchMode,
  }) {
    return AiProviderModel(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      apiKey: apiKey ?? this.apiKey,
      baseUrl: baseUrl ?? this.baseUrl,
      models: models ?? this.models,
      defaultDialogueModel: defaultDialogueModel ?? this.defaultDialogueModel,
      defaultNamingModel: defaultNamingModel ?? this.defaultNamingModel,
      isEnabled: isEnabled ?? this.isEnabled,
      enabledModels: enabledModels ?? this.enabledModels,
      notes: notes ?? this.notes,
      isSystem: isSystem ?? this.isSystem,
      sortOrder: sortOrder ?? this.sortOrder,
      webSearchMode: webSearchMode ?? this.webSearchMode,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'type': type.name,
      'apiKey': apiKey,
      'baseUrl': baseUrl,
      'models': models,
      'defaultDialogueModel': defaultDialogueModel,
      'defaultNamingModel': defaultNamingModel,
      'isEnabled': isEnabled,
      'enabledModels': enabledModels,
      'notes': notes,
      'isSystem': isSystem,
      'sortOrder': sortOrder,
      'webSearchMode': webSearchMode.name,
    };
  }

  factory AiProviderModel.fromMap(Map<String, dynamic> map) {
    return AiProviderModel(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      type: ProviderType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => ProviderType.custom,
      ),
      apiKey: map['apiKey'] ?? '',
      baseUrl: map['baseUrl'] ?? '',
      models: List<String>.from(map['models'] ?? []),
      defaultDialogueModel:
          map['defaultDialogueModel'] ?? map['defaultModel'] ?? '',
      defaultNamingModel:
          map['defaultNamingModel'] ?? map['defaultModel'] ?? '',
      isEnabled: map['isEnabled'] ?? true,
      enabledModels: List<String>.from(map['enabledModels'] ?? []),
      notes: map['notes'],
      isSystem: map['isSystem'] ?? true,
      sortOrder: map['sortOrder'] ?? 0,
      webSearchMode: map['webSearchMode'] != null
          ? WebSearchMode.values.firstWhere(
              (e) => e.name == map['webSearchMode'],
              // 兼容旧数据中的 'tavily' 值
              orElse: () => map['webSearchMode'] == 'tavily'
                  ? WebSearchMode.tool
                  : WebSearchMode.off,
            )
          : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory AiProviderModel.fromJson(String source) =>
      AiProviderModel.fromMap(json.decode(source));
}
