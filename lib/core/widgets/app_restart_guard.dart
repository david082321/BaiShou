import 'package:flutter/material.dart';

/// 全局应用硬重启守卫
/// 利用对 MaterialApp 包裹一层 Keyed 节点，并在执行重启时换 Key，
/// 从而迫使整个 Flutter Widget 树 (包含内部所有的 ProviderScope 等) 完全从头执行构建。
class AppRestartGuard extends StatefulWidget {
  final Widget child;

  const AppRestartGuard({super.key, required this.child});

  static void rebirth(BuildContext context) {
    context.findAncestorStateOfType<_AppRestartGuardState>()?.restartApp();
  }

  @override
  State<AppRestartGuard> createState() => _AppRestartGuardState();
}

class _AppRestartGuardState extends State<AppRestartGuard> {
  Key _key = UniqueKey();

  void restartApp() {
    setState(() {
      _key = UniqueKey();
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: _key,
      child: widget.child,
    );
  }
}
