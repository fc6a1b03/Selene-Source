import 'package:flutter/material.dart';
import 'package:selene/design/design_system.dart';

/// 现代化徽章组件
///
/// 用于显示状态、标签、计数等
class ModernBadge extends StatelessWidget {
  final String text;
  final Color? backgroundColor;
  final Color? textColor;
  final IconData? icon;
  final double borderRadius;
  final EdgeInsetsGeometry padding;
  final bool isAnimated;
  final Gradient? gradient;
  final bool isGlass;

  const ModernBadge({
    super.key,
    required this.text,
    this.backgroundColor,
    this.textColor,
    this.icon,
    this.borderRadius = 8,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.isAnimated = false,
    this.gradient,
    this.isGlass = false,
  });

  /// 主色徽章
  factory ModernBadge.primary(String text, {bool isDark = false}) {
    return ModernBadge(
      text: text,
      backgroundColor: AppColors.primary,
      textColor: Colors.white,
    );
  }

  /// 成功徽章
  factory ModernBadge.success(String text) {
    return ModernBadge(
      text: text,
      backgroundColor: AppColors.success,
      textColor: Colors.white,
    );
  }

  /// 警告徽章
  factory ModernBadge.warning(String text) {
    return ModernBadge(
      text: text,
      backgroundColor: AppColors.warning,
      textColor: Colors.white,
    );
  }

  /// 错误徽章
  factory ModernBadge.error(String text) {
    return ModernBadge(
      text: text,
      backgroundColor: AppColors.error,
      textColor: Colors.white,
    );
  }

  /// 渐变徽章
  factory ModernBadge.gradient(String text, {Gradient? gradient}) {
    return ModernBadge(
      text: text,
      gradient: gradient ?? AppColors.primaryGradient,
      textColor: Colors.white,
    );
  }

  /// 玻璃徽章
  factory ModernBadge.glass(String text, {required bool isDark}) {
    return ModernBadge(
      text: text,
      isGlass: true,
      textColor: isDark ? Colors.white : AppColors.lightTextPrimary,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget badge = Container(
      padding: padding,
      decoration: _buildDecoration(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: textColor ?? Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: AppTypography.badgeStyle().copyWith(
              color: textColor ?? Colors.white,
            ),
          ),
        ],
      ),
    );

    if (isAnimated) {
      badge = PulseAnimation(
        child: badge,
      );
    }

    return badge;
  }

  BoxDecoration _buildDecoration() {
    if (gradient != null) {
      return BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: AppShadows.primary(),
      );
    }

    if (isGlass) {
      return BoxDecoration(
        color: (backgroundColor ?? Colors.white).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.3),
        ),
      );
    }

    return BoxDecoration(
      color: backgroundColor ?? AppColors.primary,
      borderRadius: BorderRadius.circular(borderRadius),
      boxShadow: backgroundColor != null
          ? [
              BoxShadow(
                color: backgroundColor!.withValues(alpha: 0.4),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ]
          : null,
    );
  }
}

/// 计数徽章（小红点）
class CountBadge extends StatelessWidget {
  final int count;
  final double size;
  final Color? backgroundColor;
  final bool showZero;

  const CountBadge({
    super.key,
    required this.count,
    this.size = 20,
    this.backgroundColor,
    this.showZero = false,
  });

  @override
  Widget build(BuildContext context) {
    if (count == 0 && !showZero) {
      return const SizedBox.shrink();
    }

    final displayCount = count > 99 ? '99+' : count.toString();

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.5),
            blurRadius: 8,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Center(
        child: Text(
          displayCount,
          style: AppTypography.primary(
            fontSize: size * 0.5,
            fontWeight: AppTypography.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

/// 状态指示点
class StatusDot extends StatelessWidget {
  final Color color;
  final double size;
  final bool isPulsing;

  const StatusDot({
    super.key,
    required this.color,
    this.size = 10,
    this.isPulsing = false,
  });

  factory StatusDot.online({double size = 10}) {
    return StatusDot(
      color: AppColors.success,
      size: size,
      isPulsing: true,
    );
  }

  factory StatusDot.busy({double size = 10}) {
    return StatusDot(
      color: AppColors.error,
      size: size,
    );
  }

  factory StatusDot.away({double size = 10}) {
    return StatusDot(
      color: AppColors.warning,
      size: size,
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget dot = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: size * 0.8,
            spreadRadius: -2,
          ),
        ],
      ),
    );

    if (isPulsing) {
      dot = PulseAnimation(
        duration: const Duration(milliseconds: 2000),
        minScale: 0.8,
        maxScale: 1.2,
        child: dot,
      );
    }

    return dot;
  }
}

/// 评分徽章
class RatingBadge extends StatelessWidget {
  final double rating;
  final double? size;
  final bool showStar;

  const RatingBadge({
    super.key,
    required this.rating,
    this.size,
    this.showStar = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveSize = size ?? 32.0;

    // 根据评分确定颜色
    Color color;
    if (rating >= 8) {
      color = AppColors.success;
    } else if (rating >= 6) {
      color = AppColors.warning;
    } else {
      color = AppColors.error;
    }

    return Container(
      width: effectiveSize,
      height: effectiveSize,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [color, color.darken(0.2)],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.5),
            blurRadius: 10,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Center(
        child: Text(
          rating.toStringAsFixed(1),
          style: AppTypography.primary(
            fontSize: effectiveSize * 0.35,
            fontWeight: AppTypography.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
