// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'diary_repository_impl.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(diaryRepository)
final diaryRepositoryProvider = DiaryRepositoryProvider._();

final class DiaryRepositoryProvider
    extends
        $FunctionalProvider<DiaryRepository, DiaryRepository, DiaryRepository>
    with $Provider<DiaryRepository> {
  DiaryRepositoryProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'diaryRepositoryProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$diaryRepositoryHash();

  @$internal
  @override
  $ProviderElement<DiaryRepository> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  DiaryRepository create(Ref ref) {
    return diaryRepository(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(DiaryRepository value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<DiaryRepository>(value),
    );
  }
}

String _$diaryRepositoryHash() => r'd12de5b8cf05f23b6e7408df41a32bb423bee197';
