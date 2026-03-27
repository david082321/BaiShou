import 'package:flutter/material.dart';
import 'package:baishou/i18n/strings.g.dart';

class CompressionChart extends StatefulWidget {
  const CompressionChart({super.key});

  @override
  State<CompressionChart> createState() => _CompressionChartState();
}

class _CompressionChartState extends State<CompressionChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStairStep(
                  context,
                  t.common.daily,
                  const Color(0xFFB3E5FC),
                  alignment: Alignment.centerRight,
                  widthFactor: 0.25,
                  delay: 0.0,
                ),
                _buildConnector(),
                _buildStairStep(
                  context,
                  t.common.weekly,
                  const Color(0xFF81D4FA),
                  alignment: const Alignment(0.4, 0),
                  widthFactor: 0.28,
                  delay: 0.15,
                ),
                _buildConnector(),
                _buildStairStep(
                  context,
                  t.common.monthly,
                  const Color(0xFF4FC3F7),
                  alignment: const Alignment(-0.15, 0),
                  widthFactor: 0.32,
                  delay: 0.3,
                ),
                _buildConnector(),
                _buildStairStep(
                  context,
                  t.common.quarterly,
                  const Color(0xFF29B6F6),
                  alignment: Alignment.centerLeft,
                  widthFactor: 0.38,
                  delay: 0.45,
                ),
                const SizedBox(height: 16),
                // 基底年鉴
                _buildBaseBar(delay: 0.6),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStairStep(
    BuildContext context,
    String label,
    Color color, {
    required Alignment alignment,
    required double widthFactor,
    required double delay,
  }) {
    final progress = _delayedProgress(delay);
    return Opacity(
      opacity: progress.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 12 * (1 - progress)),
        child: Align(
          alignment: alignment,
          child: FractionallySizedBox(
            widthFactor: widthFactor,
            child: Container(
              height: 42,
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [color, color.withOpacity(0.75)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: color.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBaseBar({required double delay}) {
    final progress = _delayedProgress(delay);
    return Opacity(
      opacity: progress.clamp(0.0, 1.0),
      child: Transform.translate(
        offset: Offset(0, 16 * (1 - progress)),
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF9AD4EA), Color(0xFF64B5F6)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF9AD4EA).withOpacity(0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            t.common.yearly,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 17,
              letterSpacing: 3,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildConnector() {
    return const SizedBox(height: 3);
  }

  double _delayedProgress(double delay) {
    final raw = (_controller.value - delay) / (1.0 - delay);
    return Curves.easeOutCubic.transform(raw.clamp(0.0, 1.0));
  }
}
