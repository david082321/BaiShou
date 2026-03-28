import 'package:baishou/core/services/api_config_service.dart';
import 'package:baishou/core/storage/storage_path_provider.dart';
import 'package:baishou/features/onboarding/data/providers/onboarding_provider.dart';
import 'package:baishou/features/onboarding/presentation/widgets/compression_chart.dart';
import 'package:baishou/i18n/strings.g.dart';
import 'package:baishou/core/storage/permission_service.dart';
import 'package:baishou/core/widgets/app_toast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:io';
import 'dart:math' as math;

/// 白守品牌浅蓝
const Color _brandBlue = Color(0xFF9AD4EA);
const Color _brandBlueDark = Color(0xFF5BA8CD);

/// 每页的主题配色方案
class _SlideTheme {
  final Color iconColor;
  final Color glowColor; // icon 容器发光色
  final List<Color> bgGradient;
  final IconData icon;

  const _SlideTheme({
    required this.iconColor,
    required this.glowColor,
    required this.bgGradient,
    required this.icon,
  });
}

final List<_SlideTheme> _slideThemes = [
  // 0: Welcome
  _SlideTheme(
    iconColor: _brandBlue,
    glowColor: _brandBlue.withOpacity(0.2),
    bgGradient: [const Color(0xFFF0F9FF), Colors.white],
    icon: Icons.pets, // placeholder, welcome uses app icon
  ),
  // 1: Philosophy
  _SlideTheme(
    iconColor: const Color(0xFF7EC8E3),
    glowColor: const Color(0xFF7EC8E3).withOpacity(0.15),
    bgGradient: [const Color(0xFFF5FBFF), const Color(0xFFEFF8FF)],
    icon: Icons.auto_stories_outlined,
  ),
  // 2: Compression
  _SlideTheme(
    iconColor: const Color(0xFF64B5F6),
    glowColor: const Color(0xFF64B5F6).withOpacity(0.15),
    bgGradient: [const Color(0xFFF0F7FF), const Color(0xFFE8F4FD)],
    icon: Icons.layers_outlined,
  ),
  // 3: Storage
  _SlideTheme(
    iconColor: const Color(0xFFFFB74D),
    glowColor: const Color(0xFFFFB74D).withOpacity(0.15),
    bgGradient: [const Color(0xFFFFF8F0), const Color(0xFFFFF3E0)],
    icon: Icons.folder_open_outlined,
  ),
  // 4: API Config
  _SlideTheme(
    iconColor: const Color(0xFF90CAF9),
    glowColor: const Color(0xFF90CAF9).withOpacity(0.15),
    bgGradient: [const Color(0xFFF5F9FF), const Color(0xFFECF3FF)],
    icon: Icons.cloud_outlined,
  ),
  // 5: Privacy
  _SlideTheme(
    iconColor: const Color(0xFF81C784),
    glowColor: const Color(0xFF81C784).withOpacity(0.15),
    bgGradient: [const Color(0xFFF2FBF3), const Color(0xFFE8F5E9)],
    icon: Icons.lock_outline_rounded,
  ),
];

/// 向用户介绍应用核心理念（灵魂备份、记忆压缩）并引导其完成基础配置（如 API Key）。
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  final TextEditingController _apiKeyController = TextEditingController();
  static const int _numPages = 6;

  int _currentPage = 0;
  late AnimationController _fadeController;
  late AnimationController _floatController;

  @override
  void initState() {
    super.initState();

    final geminiProvider = ref.read(apiConfigServiceProvider).getProvider('gemini');
    _apiKeyController.text = geminiProvider?.apiKey ?? '';

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..forward();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _apiKeyController.dispose();
    _fadeController.dispose();
    _floatController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    // 使用 forward(from: 0) 代替 reset()+forward()，
    // 避免 reset() 产生的中间帧闪烁（opacity 瞬间跳到 0 再动画回来）
    _fadeController.forward(from: 0);
  }

  void _nextPage() {
    if (_currentPage < _numPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 650),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _finishOnboarding() async {
    if (_apiKeyController.text.isNotEmpty) {
      final configService = ref.read(apiConfigServiceProvider);
      final geminiProvider = configService.getProvider('gemini');
      if (geminiProvider != null) {
        await configService.updateProvider(
          geminiProvider.copyWith(apiKey: _apiKeyController.text),
        );
      }
    }
    await ref.read(onboardingCompletedProvider.notifier).complete();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 动态渐变背景
          AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeInOut,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: _slideThemes[_currentPage].bgGradient,
              ),
            ),
          ),
          // 背景装饰圆
          ..._buildBackgroundOrbs(),
          // 主内容
          SafeArea(
            child: Column(
              children: [
                // 顶部跳过按钮
                _buildTopBar(),
                // 页面内容
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    onPageChanged: _onPageChanged,
                    children: [
                      _buildWelcomeSlide(),
                      _buildPhilosophySlide(),
                      _buildCompressionSlide(),
                      _buildStorageSlide(),
                      _buildApiConfigSlide(),
                      _buildPrivacySlide(),
                    ],
                  ),
                ),
                // 底部导航控件
                _buildBottomControls(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 背景装饰性半透明光斑
  List<Widget> _buildBackgroundOrbs() {
    final theme = _slideThemes[_currentPage];
    return [
      Positioned(
        top: -60,
        right: -40,
        child: AnimatedBuilder(
          animation: _floatController,
          builder: (_, __) {
            final offset = math.sin(_floatController.value * math.pi) * 8;
            return Transform.translate(
              offset: Offset(0, offset),
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      theme.iconColor.withOpacity(0.08),
                      theme.iconColor.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
      Positioned(
        bottom: -30,
        left: -50,
        child: AnimatedBuilder(
          animation: _floatController,
          builder: (_, __) {
            final offset =
                math.cos(_floatController.value * math.pi) * 6;
            return Transform.translate(
              offset: Offset(0, offset),
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      theme.glowColor,
                      theme.iconColor.withOpacity(0.0),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ];
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (_currentPage < _numPages - 1)
            TextButton(
              onPressed: _finishOnboarding,
              child: Text(
                t.onboarding.skip,
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 15,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────── 页面内容构建 ───────────────────────────

  Widget _slideWrapper({required List<Widget> children}) {
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: _fadeController,
        curve: Curves.easeOut,
      ),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.05),
          end: Offset.zero,
        ).animate(CurvedAnimation(
          parent: _fadeController,
          curve: Curves.easeOutCubic,
        )),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 发光图标容器（每页通用）
  Widget _glowIcon(int slideIndex, {double size = 72}) {
    final theme = _slideThemes[slideIndex];
    return AnimatedBuilder(
      animation: _floatController,
      builder: (_, __) {
        final scale = 1.0 + math.sin(_floatController.value * math.pi) * 0.03;
        return Transform.scale(
          scale: scale,
          child: Container(
            width: size + 40,
            height: size + 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  theme.iconColor.withOpacity(0.12),
                  theme.iconColor.withOpacity(0.04),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
            child: Center(
              child: Container(
                width: size + 8,
                height: size + 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.7),
                  border: Border.all(
                    color: theme.iconColor.withOpacity(0.2),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.iconColor.withOpacity(0.15),
                      blurRadius: 20,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Icon(
                  theme.icon,
                  size: size * 0.55,
                  color: theme.iconColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 中文优先字体回退栈
  static const _zhFontFallback = ['PingFang SC', 'Microsoft YaHei', 'Noto Sans SC', 'Heiti SC'];

  Widget _slideTitle(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
            height: 1.3,
            fontFamilyFallback: _zhFontFallback,
          ),
    );
  }

  Widget _slideBody(String text) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.grey.shade600,
            height: 1.7,
            fontSize: 16,
            fontFamilyFallback: _zhFontFallback,
          ),
    );
  }

  // ─── Slide 0: Welcome ────────────────────────────────────────

  Widget _buildWelcomeSlide() {
    // 桌面端限制图标尺寸，避免过大溢出
    final isDesktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    final iconSize = isDesktop ? 100.0 : 140.0;
    final iconRadius = isDesktop ? 24.0 : 32.0;

    return _slideWrapper(
      children: [
        AnimatedBuilder(
          animation: _floatController,
          builder: (_, __) {
            final scale =
                1.0 + math.sin(_floatController.value * math.pi) * 0.04;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(iconRadius),
                  boxShadow: [
                    BoxShadow(
                      color: _brandBlue.withOpacity(0.25),
                      blurRadius: 30,
                      spreadRadius: 4,
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(iconRadius),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: iconSize,
                    height: iconSize,
                    errorBuilder: (_, __, ___) => Icon(
                      Icons.pets,
                      size: 60,
                      color: _brandBlue,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 36),
        Text(
          t.onboarding.welcome_title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
                color: _brandBlueDark,
                fontFamilyFallback: _zhFontFallback,
              ),
        ),
        const SizedBox(height: 16),
        _slideBody(t.onboarding.welcome_desc),
      ],
    );
  }

  // ─── Slide 1: Philosophy ─────────────────────────────────────

  Widget _buildPhilosophySlide() {
    return _slideWrapper(
      children: [
        _glowIcon(1),
        const SizedBox(height: 36),
        _slideTitle(t.onboarding.philosophy_title),
        const SizedBox(height: 20),
        _slideBody(t.onboarding.philosophy_desc),
      ],
    );
  }

  // ─── Slide 2: Compression ────────────────────────────────────

  Widget _buildCompressionSlide() {
    return _slideWrapper(
      children: [
        _glowIcon(2, size: 56),
        const SizedBox(height: 20),
        _slideTitle(t.onboarding.compression_title),
        const SizedBox(height: 8),
        _slideBody(t.onboarding.compression_desc),
        const SizedBox(height: 24),
        const SizedBox(height: 240, child: CompressionChart()),
        const SizedBox(height: 16),
      ],
    );
  }

  // ─── Slide 3: Storage ────────────────────────────────────────

  Widget _buildStorageSlide() {
    final storageService = ref.watch(storagePathServiceProvider);
    return _slideWrapper(
      children: [
        _glowIcon(3),
        const SizedBox(height: 36),
        _slideTitle(t.onboarding.storage_title),
        const SizedBox(height: 20),
        _slideBody(t.onboarding.storage_desc),
        const SizedBox(height: 28),
        // 当前路径卡片
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: const Color(0xFFFFB74D).withOpacity(0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFB74D).withOpacity(0.08),
                blurRadius: 12,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.onboarding.current_storage,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 6),
              FutureBuilder(
                future: storageService.getRootDirectory(),
                builder: (context, snapshot) {
                  return Text(
                    snapshot.data?.path ?? '...',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () async {
            if (Platform.isAndroid) {
              final permissionSvc = ref.read(permissionServiceProvider.notifier);
              final hasPermission = await permissionSvc.hasStoragePermission();
              if (!hasPermission) {
                final granted = await permissionSvc.requestStoragePermission();
                if (!granted) {
                  if (mounted) {
                    AppToast.showError(
                      context,
                      t.common.permission.storage_denied,
                    );
                  }
                  return;
                }
              }
            }
            String? selectedDirectory =
                await FilePicker.platform.getDirectoryPath();
            if (selectedDirectory != null) {
              await storageService.updateRootDirectory(selectedDirectory);
              setState(() {});
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFFFB74D),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
          label: Text(t.onboarding.change_storage),
        ),
      ],
    );
  }

  // ─── Slide 4: API Config ─────────────────────────────────────

  Widget _buildApiConfigSlide() {
    return _slideWrapper(
      children: [
        _glowIcon(4),
        const SizedBox(height: 36),
        _slideTitle(t.onboarding.api_guide_title),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFF90CAF9).withOpacity(0.25),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF90CAF9).withOpacity(0.08),
                blurRadius: 12,
              ),
            ],
          ),
          child: _slideBody(t.onboarding.api_guide_desc),
        ),
      ],
    );
  }

  // ─── Slide 5: Privacy ────────────────────────────────────────

  Widget _buildPrivacySlide() {
    return _slideWrapper(
      children: [
        _glowIcon(5),
        const SizedBox(height: 36),
        _slideTitle(t.onboarding.privacy_title),
        const SizedBox(height: 20),
        _slideBody(t.onboarding.privacy_desc),
        const SizedBox(height: 40),
        // 品牌 slogan
        Text(
          '「纯白誓约，守护一生」',
          style: TextStyle(
            fontSize: 15,
            color: Colors.grey.shade600,
            letterSpacing: 2,
            fontFamilyFallback: _zhFontFallback,
          ),
        ),
      ],
    );
  }

  // ─────────────────────────── 底部控件 ───────────────────────────

  Widget _buildBottomControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
      child: Row(
        children: [
          // 胶囊指示条
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(_numPages, (i) {
              final isActive = _currentPage == i;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.only(right: 6),
                width: isActive ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: isActive
                      ? _slideThemes[_currentPage].iconColor
                      : Colors.grey.shade300,
                ),
              );
            }),
          ),
          const Spacer(),
          // 返回按钮
          if (_currentPage > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: TextButton(
                onPressed: _previousPage,
                style: TextButton.styleFrom(
                  foregroundColor: Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_ios_rounded, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 4),
                    Text(t.common.back),
                  ],
                ),
              ),
            ),
          // 下一步 / 完成按钮
          _buildNextButton(),
        ],
      ),
    );
  }

  Widget _buildNextButton() {
    final isLast = _currentPage == _numPages - 1;
    final theme = _slideThemes[_currentPage];

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      child: FilledButton(
        onPressed: _nextPage,
        style: FilledButton.styleFrom(
          backgroundColor: isLast ? theme.iconColor : _brandBlueDark,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isLast ? t.onboarding.get_started : t.common.next,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            if (!isLast) ...[
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            ],
          ],
        ),
      ),
    );
  }
}
