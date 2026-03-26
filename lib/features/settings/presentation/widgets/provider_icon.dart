/// AI 供应商图标工具函数
///
/// 根据 ProviderType 返回对应的品牌图标 Widget。
/// 可在设置页、选择器弹窗等多处复用。

import 'package:baishou/agent/models/ai_provider_model.dart';
import 'package:flutter/material.dart';

Widget getProviderIcon(ProviderType type, {double size = 20}) {
  switch (type) {
    case ProviderType.openai:
      return Image.asset(
        'assets/ai_provider_icon/openai.png',
        width: size,
        height: size,
      );
    case ProviderType.gemini:
      return Image.asset(
        'assets/ai_provider_icon/gemini-color.png',
        width: size,
        height: size,
      );
    case ProviderType.anthropic:
      return Image.asset(
        'assets/ai_provider_icon/claude-color.png',
        width: size,
        height: size,
      );
    case ProviderType.deepseek:
      return Image.asset(
        'assets/ai_provider_icon/deepseek-color.png',
        width: size,
        height: size,
      );
    case ProviderType.kimi:
      return Image.asset(
        'assets/ai_provider_icon/moonshot.png',
        width: size,
        height: size,
      );
    case ProviderType.ollama:
      return Image.asset(
        'assets/ai_provider_icon/ollama.png',
        width: size,
        height: size,
      );
    case ProviderType.siliconflow:
      return Image.asset(
        'assets/ai_provider_icon/silicon.png',
        width: size,
        height: size,
      );
    case ProviderType.openrouter:
      return Image.asset(
        'assets/ai_provider_icon/openrouter.png',
        width: size,
        height: size,
      );
    case ProviderType.dashscope:
      return Image.asset(
        'assets/ai_provider_icon/dashscope.png',
        width: size,
        height: size,
      );
    case ProviderType.doubao:
      return Image.asset(
        'assets/ai_provider_icon/doubao.png',
        width: size,
        height: size,
      );
    case ProviderType.grok:
      return Image.asset(
        'assets/ai_provider_icon/grok.png',
        width: size,
        height: size,
      );
    case ProviderType.mistral:
      return Image.asset(
        'assets/ai_provider_icon/mistral.png',
        width: size,
        height: size,
      );
    case ProviderType.lmstudio:
      return Image.asset(
        'assets/ai_provider_icon/lmstudio.png',
        width: size,
        height: size,
      );
    default:
      return Icon(
        Icons.cloud_outlined,
        color: Colors.grey.shade700,
        size: size,
      );
  }
}
