import 'package:baishou/core/theme/app_theme.dart';
import 'package:flutter/material.dart';

class TimelineNode extends StatelessWidget {
  final Widget child;
  final bool isLast;
  final bool isFirst;
  final Widget? indicator;
  final Color? lineColor;

  const TimelineNode({
    super.key,
    required this.child,
    this.isLast = false,
    this.isFirst = false,
    this.indicator,
    this.lineColor,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 时间轴列
          SizedBox(
            width: 40,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                // 线条
                if (!isLast)
                  Positioned(
                    top: 0,
                    bottom: 0,
                    left: 20, // 40 宽度居中
                    child: Container(
                      width: 2,
                      color:
                          lineColor ?? AppTheme.backgroundDark.withOpacity(0.1),
                    ),
                  ),
                // 圆点
                Positioned(
                  top: 24, // 与卡片顶部内容对齐
                  left: 15, // 居中: 20 - (10/2) = 15
                  child:
                      indicator ??
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: AppTheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primary.withOpacity(0.3),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                ),
              ],
            ),
          ),
          // 内容
          Expanded(child: child),
        ],
      ),
    );
  }
}
