import 'dart:io';

import 'package:baishou/features/settings/presentation/pages/views/about_settings_card.dart';
import 'package:baishou/features/settings/presentation/pages/views/appearance_settings_card.dart';
import 'package:baishou/features/settings/presentation/pages/views/data_management_card.dart';
import 'package:baishou/features/settings/presentation/pages/views/hotkey_settings_card.dart';
import 'package:baishou/features/settings/presentation/pages/views/identity_settings_card.dart';
import 'package:baishou/features/settings/presentation/pages/views/mcp_settings_card.dart';
import 'package:baishou/features/settings/presentation/pages/views/profile_settings_card.dart';
import 'package:baishou/features/settings/presentation/pages/views/storage_settings_card.dart';
import 'package:baishou/features/settings/presentation/pages/views/workspace_settings_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 常规设置视图
/// 纯组合层：将各独立卡片组件排列在一起。
class GeneralSettingsView extends ConsumerWidget {
  const GeneralSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;

    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const ProfileSettingsCard(),
        const IdentitySettingsCard(),
        const AppearanceSettingsCard(),
        if (isDesktop) const HotkeySettingsCard(),
        if (isDesktop) const McpSettingsCard(),
        const WorkspaceSettingsCard(),
        const StorageSettingsCard(),
        const DataManagementCard(),
        const AboutSettingsCard(),
      ],
    );
  }
}
