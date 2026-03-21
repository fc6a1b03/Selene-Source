import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:selene/components/animations/video_loading_animation.dart';
import 'package:selene/utils/device_utils.dart';

/// 切换播放源/集数时的加载蒙版组件 - Design System 2026
///
/// 使用流体动画、霓虹光效和玻璃态设计
class SwitchLoadingOverlay extends StatelessWidget {
  final bool isVisible;
  final String message;
  final AnimationController animationController;
  final VoidCallback? onBackPressed;

  const SwitchLoadingOverlay({
    super.key,
    required this.isVisible,
    required this.message,
    required this.animationController,
    this.onBackPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: animationController,
        builder: (context, child) {
          return ColoredBox(
            color: Colors.black.withValues(
              alpha: 0.7 + (animationController.value * 0.1),
            ),
            child: Stack(
              children: [
                // 背景装饰圆环
                Positioned.fill(
                  child: CustomPaint(
                    painter: _BackgroundRingsPainter(
                      progress: animationController.value,
                    ),
                  ),
                ),

                // 左上角返回按钮
                if (onBackPressed != null)
                  Positioned(
                    top: 4,
                    left: 8.0,
                    child: DeviceUtils.isPC()
                        ? _HoverBackButton(
                            onTap: onBackPressed!,
                            iconColor: Colors.white,
                          )
                        : GestureDetector(
                            onTap: onBackPressed,
                            behavior: HitTestBehavior.opaque,
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.arrow_back,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ),
                  ),

                // 中心加载内容
                Center(
                  child: VideoLoadingAnimation(
                    progress: 0.6 + (animationController.value * 0.4),
                    message: message,
                    emoji: '🎬',
                    isDarkMode: true,
                    size: 140,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 背景装饰圆环绘制器
class _BackgroundRingsPainter extends CustomPainter {
  final double progress;

  _BackgroundRingsPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.max(size.width, size.height) / 2;

    for (var i = 0; i < 3; i++) {
      final ringProgress = (progress + i * 0.33) % 1.0;
      final radius = maxRadius * (0.3 + ringProgress * 0.7);
      final alpha = (1.0 - ringProgress) * 0.15;

      final paint = Paint()
        ..color = Colors.white.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;

      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

/// 带 hover 效果的返回按钮（PC 端专用）
class _HoverBackButton extends StatefulWidget {
  final VoidCallback onTap;
  final Color iconColor;

  const _HoverBackButton({
    required this.onTap,
    required this.iconColor,
  });

  @override
  State<_HoverBackButton> createState() => _HoverBackButtonState();
}

class _HoverBackButtonState extends State<_HoverBackButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: _isHovering
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.withValues(alpha: 0.5),
                )
              : null,
          child: Icon(
            Icons.arrow_back,
            color: widget.iconColor,
            size: 20,
          ),
        ),
      ),
    );
  }
}
