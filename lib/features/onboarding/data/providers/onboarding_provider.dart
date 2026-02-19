import 'package:baishou/core/providers/shared_preferences_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'onboarding_provider.g.dart';

@Riverpod(keepAlive: true)
class OnboardingCompleted extends _$OnboardingCompleted {
  static const _key = 'has_seen_onboarding';

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(_key) ?? false;
  }

  Future<void> complete() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_key, true);
    ref.invalidateSelf();
  }
}
