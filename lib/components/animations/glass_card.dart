import 'package:flutter/material.dart';
import 'package:selene/design/design_system.dart';

/// 玻璃拟态卡片组件
///
/// 提供毛玻璃效果的卡片容器，支持：
/// - 自定义圆角
/// - 边框光效
/// - 悬停动画
/// - 渐变边框
class GlassCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double? width;
  final double? height;
  final bool isDark;
  final List<BoxShadow>? shadows;
  final Gradient? gradient;
  final Border? border;
  final VoidCallback? onTap;
  final bool enableHover;

  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding = const EdgeInsets.all(16.0),
    this.margin = EdgeInsets.zero,
    this.width,
    this.height,
    required this.isDark,
    this.shadows,
    this.gradient,
    this.border,
    this.onTap,
    this.enableHover = true,
  });

  @override
  Widget build(BuildContext context) {
    Widget card = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: gradient ?? _buildGlassGradient(),
        border: border ?? _buildGlassBorder(),
        boxShadow: shadows ?? AppShadows.glassBorder(isDark: isDark),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius - 1),
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );

    if (enableHover && onTap != null) {
      card = HoverAnimation(
        child: card,
      );
    }

    if (onTap != null) {
      card = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: card,
      );
    }

    return card;
  }

  Gradient _buildGlassGradient() {
    if (isDark) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF1E293B).withValues(alpha: 0.85),
          const Color(0xFF0F172A).withValues(alpha: 0.75),
        ],
      );
    }
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.white.withValues(alpha: 0.85),
        Colors.white.withValues(alpha: 0.55),
      ],
    );
  }

  Border _buildGlassBorder() {
    return Border.all(
      color: isDark
          ? Colors.white.withValues(alpha: 0.1)
          : Colors.white.withValues(alpha: 0.5),
    );
  }
}

/// 霓虹卡片组件
///
/// 带有发光边框效果的卡片
class NeonCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final double? width;
  final double? height;
  final Gradient glowGradient;
  final double glowIntensity;
  final VoidCallback? onTap;

  const NeonCard({
    super.key,
    required this.child,
    this.borderRadius = 20,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.width,
    this.height,
    this.glowGradient = AppColors.primaryGradient,
    this.glowIntensity = 0.5,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget card = Container(
      width: width,
      height: height,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: glowGradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: glowIntensity),
            blurRadius: 20,
            spreadRadius: -5,
          ),
        ],
      ),
      padding: const EdgeInsets.all(2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius - 2),
          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius - 2),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );

    if (onTap != null) {
      card = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: HoverAnimation(child: card),
      );
    }

    return card;
  }
}

/// 渐变边框卡片
class GradientBorderCard extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final double borderWidth;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Gradient gradient;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const GradientBorderCard({
    super.key,
    required this.child,
    this.borderRadius = 16,
    this.borderWidth = 2,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
    this.gradient = AppColors.primaryGradient,
    this.backgroundColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    Widget card = Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        gradient: gradient,
      ),
      padding: EdgeInsets.all(borderWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius - borderWidth),
          color: backgroundColor ??
              (isDark ? AppColors.darkSurface : AppColors.lightSurface),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(borderRadius - borderWidth),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );

    if (onTap != null) {
      card = GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: HoverAnimation(child: card),
      );
    }

    return card;
  }
}
