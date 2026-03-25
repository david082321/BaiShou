import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;

import '../../../../core/providers/shared_preferences_provider.dart';
import 'package:baishou/i18n/strings.g.dart';

class UserProfile {
  final String nickname;
  final String? avatarPath;
  final Map<String, String> identityFacts;

  const UserProfile({
    required this.nickname,
    this.avatarPath,
    this.identityFacts = const {},
  });

  UserProfile copyWith({
    String? nickname,
    String? avatarPath,
    Map<String, String>? identityFacts,
  }) {
    return UserProfile(
      nickname: nickname ?? this.nickname,
      avatarPath: avatarPath ?? this.avatarPath,
      identityFacts: identityFacts ?? this.identityFacts,
    );
  }

  /// 将身份卡序列化为 Markdown 格式，用于注入 System Prompt
  String toMarkdownBlock() {
    if (identityFacts.isEmpty) return '';
    final buffer = StringBuffer();
    buffer.writeln('### User Profile');
    for (final entry in identityFacts.entries) {
      buffer.writeln('- **${entry.key}**: ${entry.value}');
    }
    return buffer.toString();
  }
}

class UserProfileNotifier extends Notifier<UserProfile> {
  static const String _keyNickname = 'user_nickname';
  static const String _keyAvatarPath = 'user_avatar_path';
  static const String _keyIdentityFacts = 'user_identity_facts';
  late SharedPreferences _prefs;

  @override
  UserProfile build() {
    _prefs = ref.watch(sharedPreferencesProvider);
    return UserProfile(
      nickname: _prefs.getString(_keyNickname) ?? t.settings.default_nickname,
      avatarPath: _prefs.getString(_keyAvatarPath),
      identityFacts: _loadFacts(),
    );
  }

  Map<String, String> _loadFacts() {
    final jsonStr = _prefs.getString(_keyIdentityFacts);
    if (jsonStr == null || jsonStr.isEmpty) return {};
    try {
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveFacts(Map<String, String> facts) async {
    await _prefs.setString(_keyIdentityFacts, jsonEncode(facts));
  }

  Future<void> updateNickname(String nickname) async {
    await _prefs.setString(_keyNickname, nickname);
    state = state.copyWith(nickname: nickname);
  }

  /// 添加或更新一条身份卡事实
  Future<void> addFact(String key, String value) async {
    final updated = Map<String, String>.from(state.identityFacts);
    updated[key] = value;
    await _saveFacts(updated);
    state = state.copyWith(identityFacts: updated);
  }

  /// 删除一条身份卡事实
  Future<void> removeFact(String key) async {
    final updated = Map<String, String>.from(state.identityFacts);
    updated.remove(key);
    await _saveFacts(updated);
    state = state.copyWith(identityFacts: updated);
  }

  /// 批量更新所有身份卡事实
  Future<void> updateAllFacts(Map<String, String> facts) async {
    await _saveFacts(facts);
    state = state.copyWith(identityFacts: facts);
  }

  Future<void> updateAvatar(File newAvatar) async {
    final appDir = await getApplicationDocumentsDirectory();
    final avatarDir = Directory(path.join(appDir.path, 'avatars'));

    if (!avatarDir.existsSync()) {
      await avatarDir.create(recursive: true);
    }

    final fileName =
        'avatar_${DateTime.now().millisecondsSinceEpoch}${path.extension(newAvatar.path)}';
    final savedImage = await newAvatar.copy(
      path.join(avatarDir.path, fileName),
    );

    // 如果存在旧头像且不同，则删除
    if (state.avatarPath != null) {
      final oldFile = File(state.avatarPath!);
      if (oldFile.existsSync()) {
        try {
          await oldFile.delete();
        } catch (e) {
          // ignore error
        }
      }
    }

    await _prefs.setString(_keyAvatarPath, savedImage.path);
    state = state.copyWith(avatarPath: savedImage.path);
  }
}

final userProfileProvider = NotifierProvider<UserProfileNotifier, UserProfile>(
  UserProfileNotifier.new,
);
