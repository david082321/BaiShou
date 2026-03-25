import 'package:flutter_test/flutter_test.dart';
import 'package:baishou/features/settings/domain/services/user_profile_service.dart';

void main() {
  group('UserProfile', () {
    group('toMarkdownBlock', () {
      test('空 identityFacts 返回空字符串', () {
        const profile = UserProfile(nickname: 'Test');
        expect(profile.toMarkdownBlock(), '');
      });

      test('单条 KV 格式化为 Markdown', () {
        const profile = UserProfile(
          nickname: 'Test',
          identityFacts: {'生日': '1998-05-20'},
        );
        final block = profile.toMarkdownBlock();
        expect(block, contains('### User Profile'));
        expect(block, contains('- **生日**: 1998-05-20'));
      });

      test('多条 KV 全部输出', () {
        const profile = UserProfile(
          nickname: '小明',
          identityFacts: {
            '生日': '1998-05-20',
            '性别': '男',
            '职业': '前端开发',
            '禁忌': '海鲜过敏',
          },
        );
        final block = profile.toMarkdownBlock();
        expect(block, contains('### User Profile'));
        expect(block, contains('- **生日**: 1998-05-20'));
        expect(block, contains('- **性别**: 男'));
        expect(block, contains('- **职业**: 前端开发'));
        expect(block, contains('- **禁忌**: 海鲜过敏'));
      });
    });

    group('copyWith', () {
      test('只改 nickname，identityFacts 不变', () {
        const profile = UserProfile(
          nickname: 'Old',
          identityFacts: {'key': 'value'},
        );
        final updated = profile.copyWith(nickname: 'New');
        expect(updated.nickname, 'New');
        expect(updated.identityFacts, {'key': 'value'});
      });

      test('只改 identityFacts，nickname 不变', () {
        const profile = UserProfile(
          nickname: 'Test',
          identityFacts: {'old': 'data'},
        );
        final updated = profile.copyWith(identityFacts: {'new': 'data'});
        expect(updated.nickname, 'Test');
        expect(updated.identityFacts, {'new': 'data'});
      });

      test('改 avatarPath', () {
        const profile = UserProfile(nickname: 'Test');
        final updated = profile.copyWith(avatarPath: '/path/to/avatar.png');
        expect(updated.avatarPath, '/path/to/avatar.png');
        expect(updated.nickname, 'Test');
      });
    });

    group('default values', () {
      test('默认 identityFacts 为空 Map', () {
        const profile = UserProfile(nickname: 'Test');
        expect(profile.identityFacts, isEmpty);
        expect(profile.avatarPath, isNull);
      });
    });
  });
}
