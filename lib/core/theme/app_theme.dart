import 'package:flutter/material.dart';

/// 白守的主题配置
/// Sakura & Akatsuki 的配色风格
class AppTheme {
  // 私有构造函数
  AppTheme._();

  /// 樱花的粉色 (Primary)
  static const Color sakuraPink = Color(0xFFFFC0CB);
  static const Color sakuraDeep = Color(0xFFFF69B4);

  /// 拂晓的晨光 (Secondary/Tertiary)
  static const Color akatsukiDawn = Color(0xFFFF9E80);
  static const Color akatsukiDark = Color(0xFF2C2C2C);

  /// 亮色主题
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: sakuraPink,
        brightness: Brightness.light,
        primary: const Color(0xFFD81B60), // 更深一点的粉，保证对比度
        secondary: const Color(0xFF8E24AA),
        surface: const Color(0xFFFFF5F8), // 淡淡的樱花背景
      ),
      scaffoldBackgroundColor: const Color(0xFFFFF5F8),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      fontFamily: 'Noto Sans SC', // 假设后续会配置字体
    );
  }

  /// 暗色主题
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: akatsukiDark,
        brightness: Brightness.dark,
        primary: sakuraPink, // 暗色下用亮粉色点缀
        surface: const Color(0xFF1E1E1E),
      ),
      scaffoldBackgroundColor: const Color(0xFF1E1E1E),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      fontFamily: 'Noto Sans SC',
    );
  }
}
