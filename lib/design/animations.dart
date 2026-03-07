import 'package:flutter/material.dart';

/// Design System 2026 - 动画系统
///
/// 提供统一的动画时长、曲线和过渡效果
/// 遵循流畅、自然、有弹性的动画原则
class AppAnimations {
  AppAnimations._();

  // ==================== 时长规范 ====================

  /// 微交互 - 按钮反馈、小状态变化
  static const Duration micro = Duration(milliseconds: 100);

  /// 快速 - 悬停效果、小过渡
  static const Duration fast = Duration(milliseconds: 200);

  /// 正常 - 标准过渡、页面切换
  static const Duration normal = Duration(milliseconds: 300);

  /// 中等 - 复杂动画、列表项
  static const Duration medium = Duration(milliseconds: 400);

  /// 慢速 - 强调动画、入场效果
  static const Duration slow = Duration(milliseconds: 500);

  /// 展示 - 英雄动画、大型过渡
  static const Duration showcase = Duration(milliseconds: 800);

  // ==================== 曲线规范 ====================

  /// 标准曲线 - 自然减速
  static const Curve standard = Curves.easeOutCubic;

  /// 入场曲线 - 快速开始，缓慢结束
  static const Curve enter = Curves.easeOutQuart;

  /// 出场曲线 - 缓慢开始，快速结束
  static const Curve exit = Curves.easeInQuart;

  /// 强调曲线 - 有弹性
  static const Curve emphasize = Curves.elasticOut;

  /// 弹性曲线 - 强弹性
  static const Curve bounce = Curves.bounceOut;

  /// 线性曲线 - 匀速
  static const Curve linear = Curves.linear;

  /// 平滑曲线 - 非常平滑
  static const Curve smooth = Curves.fastEaseInToSlowEaseOut;

  // ==================== 预设过渡 ====================

  /// 淡入过渡
  static Widget fadeIn({
    required Widget child,
    Duration duration = normal,
    Curve curve = enter,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: child,
        );
      },
      child: child,
    );
  }

  /// 缩放入场
  static Widget scaleIn({
    required Widget child,
    Duration duration = normal,
    Curve curve = emphasize,
    double begin = 0.8,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: begin, end: 1),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: child,
        );
      },
      child: child,
    );
  }

  /// 滑入动画 - 从底部
  static Widget slideUp({
    required Widget child,
    Duration duration = normal,
    Curve curve = enter,
    double offset = 50,
  }) {
    return TweenAnimationBuilder<Offset>(
      tween: Tween(
        begin: Offset(0, offset / 100),
        end: Offset.zero,
      ),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        return FractionalTranslation(
          translation: value,
          child: child,
        );
      },
      child: child,
    );
  }

  /// 滑入动画 - 从左侧
  static Widget slideInLeft({
    required Widget child,
    Duration duration = normal,
    Curve curve = enter,
  }) {
    return TweenAnimationBuilder<Offset>(
      tween: Tween(
        begin: const Offset(-0.3, 0),
        end: Offset.zero,
      ),
      duration: duration,
      curve: curve,
      builder: (context, value, child) {
        return FractionalTranslation(
          translation: value,
          child: child,
        );
      },
      child: child,
    );
  }

  /// 组合入场动画 - 淡入 + 缩放 + 上移
  static Widget entrance({
    required Widget child,
    Duration duration = medium,
    double delay = 0,
  }) {
    return _DelayedEntrance(
      delay: Duration(milliseconds: (delay * 1000).round()),
      duration: duration,
      child: child,
    );
  }

  /// 交错列表动画
  static Widget staggeredList({
    required List<Widget> children,
    Duration itemDelay = fast,
    Duration duration = normal,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: children.asMap().entries.map((entry) {
        final index = entry.key;
        final child = entry.value;
        return _DelayedEntrance(
          delay: Duration(milliseconds: index * itemDelay.inMilliseconds),
          duration: duration,
          child: child,
        );
      }).toList(),
    );
  }
}

/// 延迟入场组件
class _DelayedEntrance extends StatefulWidget {
  final Duration delay;
  final Duration duration;
  final Widget child;

  const _DelayedEntrance({
    required this.delay,
    required this.duration,
    required this.child,
  });

  @override
  State<_DelayedEntrance> createState() => _DelayedEntranceState();
}

class _DelayedEntranceState extends State<_DelayedEntrance>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _scale;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.6, curve: Curves.easeOut),
      ),
    );

    _scale = Tween<double>(begin: 0.9, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.8, curve: Curves.elasticOut),
      ),
    );

    _slide = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    Future.delayed(widget.delay, () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: _opacity.value,
          child: Transform.scale(
            scale: _scale.value,
            child: FractionalTranslation(
              translation: _slide.value,
              child: child,
            ),
          ),
        );
      },
      child: widget.child,
    );
  }
}

/// 悬停动画组件
class HoverAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double scale;
  final double elevation;

  const HoverAnimation({
    super.key,
    required this.child,
    this.duration = AppAnimations.fast,
    this.scale = 1.02,
    this.elevation = 8,
  });

  @override
  State<HoverAnimation> createState() => _HoverAnimationState();
}

class _HoverAnimationState extends State<HoverAnimation> {
  final ValueNotifier<bool> _isHovered = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _isHovered.value = true,
      onExit: (_) => _isHovered.value = false,
      child: AnimatedBuilder(
        animation: _isHovered,
        builder: (context, child) {
          return AnimatedScale(
            scale: _isHovered.value ? widget.scale : 1.0,
            duration: widget.duration,
            curve: AppAnimations.standard,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

/// 脉冲动画
class PulseAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final double minScale;
  final double maxScale;

  const PulseAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
    this.minScale = 1.0,
    this.maxScale = 1.05,
  });

  @override
  State<PulseAnimation> createState() => _PulseAnimationState();
}

class _PulseAnimationState extends State<PulseAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _scale = Tween<double>(
      begin: widget.minScale,
      end: widget.maxScale,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _controller.repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) {
        return Transform.scale(
          scale: _scale.value,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 闪烁动画 - 用于加载指示器
class ShimmerAnimation extends StatefulWidget {
  final Widget child;
  final Duration duration;
  final Color shimmerColor;

  const ShimmerAnimation({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 1500),
    this.shimmerColor = Colors.white,
  });

  @override
  State<ShimmerAnimation> createState() => _ShimmerAnimationState();
}

class _ShimmerAnimationState extends State<ShimmerAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _position;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _position = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOutSine,
      ),
    );

    _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _position,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                Colors.transparent,
                widget.shimmerColor.withValues(alpha: 0.3),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5, 1.0],
              transform: GradientTranslation(_position.value),
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 渐变平移变换
class GradientTranslation extends GradientTransform {
  final double translation;

  const GradientTranslation(this.translation);

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * translation, 0, 0);
  }
}

/// 页面过渡动画 - 滑动 + 淡入
class PageTransition extends PageRouteBuilder<void> {
  final Widget child;
  final Duration duration;

  PageTransition({
    required this.child,
    this.duration = AppAnimations.normal,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => child,
          transitionDuration: duration,
          reverseTransitionDuration: duration,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            const begin = Offset(0.1, 0);
            const end = Offset.zero;
            final tween = Tween(begin: begin, end: end)
                .chain(CurveTween(curve: AppAnimations.enter));
            final offsetAnimation = animation.drive(tween);

            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: offsetAnimation,
                child: child,
              ),
            );
          },
        );
}
