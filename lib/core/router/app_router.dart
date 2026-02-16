import 'package:baishou/features/diary/presentation/pages/diary_editor_page.dart';
import 'package:baishou/features/diary/presentation/pages/diary_list_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'app_router.g.dart';

// 临时的 Home Page，稍后会被 features/diary 里的页面替代
class PlaceholderHomePage extends StatelessWidget {
  const PlaceholderHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('白守 BaiShou')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.favorite, size: 64, color: Colors.pinkAccent),
            const SizedBox(height: 16),
            Text(
              '以纯白的爱，守护你和TA的一生',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 32),
            const Text('Development in progress...'),
          ],
        ),
      ),
    );
  }
}

@riverpod
GoRouter goRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/',
    debugLogDiagnostics: true,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const DiaryListPage(),
        routes: [
          GoRoute(
            path: 'diary/edit',
            builder: (context, state) {
              // 从 query params 获取日期，默认为今天
              final dateStr = state.uri.queryParameters['date'];
              final date = dateStr != null
                  ? DateTime.parse(dateStr)
                  : DateTime.now();
              // TODO: 如果需要传递 initialDiary 对象，可以通过 extra 传递，
              // 但为了保持深层链接能力，建议只传 ID 或日期，并在页面内重新获取
              return DiaryEditorPage(date: date);
            },
          ),
        ],
      ),
    ],
  );
}
