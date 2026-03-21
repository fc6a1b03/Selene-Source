import 'package:flutter/material.dart';
import 'package:selene/design/colors.dart';

/// Design System 2026 - 阴影与光效系统
///
/// 提供统一的阴影定义和光效效果，包括：
/// - 标准阴影（小/中/大）
/// - 霓虹光效
/// - 玻璃拟态效果
/// - 发光效果
class AppShadows {
  AppShadows._();

  // ==================== 标准阴影 ====================

  /// 小阴影 - 用于按钮、小卡片
  static List<BoxShadow> get small => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  /// 中阴影 - 用于卡片、面板
  static List<BoxShadow> get medium => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ];

  /// 大阴影 - 用于浮层、对话框
  static List<BoxShadow> get large => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 8),
        ),
      ];

  /// 超大阴影 - 用于模态框、抽屉
  static List<BoxShadow> get xlarge => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.16),
          blurRadius: 32,
          offset: const Offset(0, 16),
        ),
      ];

  // ==================== 彩色阴影 ====================

  /// 主色阴影 - 紫色
  static List<BoxShadow> primary({double intensity = 0.3}) => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: intensity),
          blurRadius: 20,
          offset: const Offset(0, 4),
          spreadRadius: -4,
        ),
      ];

  /// 辅助色阴影 - 粉色
  static List<BoxShadow> secondary({double intensity = 0.3}) => [
        BoxShadow(
          color: AppColors.secondary.withValues(alpha: intensity),
          blurRadius: 20,
          offset: const Offset(0, 4),
          spreadRadius: -4,
        ),
      ];

  /// 强调色阴影 - 蓝色
  static List<BoxShadow> accent({double intensity = 0.3}) => [
        BoxShadow(
          color: AppColors.accent.withValues(alpha: intensity),
          blurRadius: 20,
          offset: const Offset(0, 4),
          spreadRadius: -4,
        ),
      ];

  /// 成功色阴影 - 绿色
  static List<BoxShadow> success({double intensity = 0.3}) => [
        BoxShadow(
          color: AppColors.success.withValues(alpha: intensity),
          blurRadius: 20,
          offset: const Offset(0, 4),
          spreadRadius: -4,
        ),
      ];

  // ==================== 霓虹光效 ====================

  /// 主色霓虹发光
  static List<BoxShadow> get neonPrimary => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.6),
          blurRadius: 30,
          spreadRadius: -5,
        ),
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.3),
          blurRadius: 60,
          spreadRadius: -10,
        ),
      ];

  /// 辅助色霓虹发光
  static List<BoxShadow> get neonSecondary => [
        BoxShadow(
          color: AppColors.secondary.withValues(alpha: 0.6),
          blurRadius: 30,
          spreadRadius: -5,
        ),
        BoxShadow(
          color: AppColors.secondary.withValues(alpha: 0.3),
          blurRadius: 60,
          spreadRadius: -10,
        ),
      ];

  /// 蓝色霓虹发光
  static List<BoxShadow> get neonBlue => [
        BoxShadow(
          color: AppColors.accent.withValues(alpha: 0.6),
          blurRadius: 30,
          spreadRadius: -5,
        ),
        BoxShadow(
          color: AppColors.accent.withValues(alpha: 0.3),
          blurRadius: 60,
          spreadRadius: -10,
        ),
      ];

  /// 渐变霓虹发光 - 主色到辅助色
  static List<BoxShadow> get neonGradient => [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.4),
          blurRadius: 20,
          spreadRadius: -2,
        ),
        BoxShadow(
          color: AppColors.secondary.withValues(alpha: 0.4),
          blurRadius: 40,
          spreadRadius: -8,
        ),
      ];

  // ==================== 玻璃拟态效果 ====================

  /// 深色玻璃阴影
  static List<BoxShadow> get darkGlass => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.3),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.05),
          blurRadius: 1,
          offset: const Offset(0, -1),
        ),
      ];

  /// 浅色玻璃阴影
  static List<BoxShadow> get lightGlass => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.8),
          blurRadius: 1,
          offset: const Offset(0, -1),
        ),
      ];

  /// 玻璃边框光效
  static List<BoxShadow> glassBorder({required bool isDark}) => [
        BoxShadow(
          color: isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.white.withValues(alpha: 0.8),
          blurRadius: 1,
          offset: const Offset(0, -1),
        ),
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.05),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];

  // ==================== 内阴影 ====================

  /// 内阴影 - 用于按下状态
  static List<BoxShadow> get inner => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ];

  /// 内发光 - 用于选中状态
  static List<BoxShadow> innerGlow(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.3),
          blurRadius: 8,
          spreadRadius: -2,
        ),
      ];

  // ==================== 特殊效果 ====================

  /// 悬浮效果 - 用于卡片悬停
  static List<BoxShadow> get floating => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.1),
          blurRadius: 40,
          offset: const Offset(0, 20),
          spreadRadius: -10,
        ),
      ];

  /// 聚焦光环
  static List<BoxShadow> focusRing(Color color) => [
        BoxShadow(
          color: color.withValues(alpha: 0.4),
          spreadRadius: 3,
        ),
        BoxShadow(
          color: color.withValues(alpha: 0.2),
          blurRadius: 8,
          spreadRadius: 4,
        ),
      ];

  /// 底部渐变阴影 - 用于图片渐变遮罩
  static BoxShadow get bottomGradient => BoxShadow(
        color: Colors.black.withValues(alpha: 0.6),
        blurRadius: 100,
        offset: const Offset(0, 50),
      );
}

/// 光效装饰器
class GlowDecoration extends StatelessWidget {
  final Widget child;
  final Color glowColor;
  final double intensity;
  final double blurRadius;
  final double spreadRadius;

  const GlowDecoration({
    super.key,
    required this.child,
    required this.glowColor,
    this.intensity = 0.5,
    this.blurRadius = 30,
    this.spreadRadius = -5,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: intensity),
            blurRadius: blurRadius,
            spreadRadius: spreadRadius,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// 霓虹边框装饰
class NeonBorder extends StatelessWidget {
  final Widget child;
  final Gradient gradient;
  final double borderWidth;
  final double blurRadius;

  const NeonBorder({
    super.key,
    required this.child,
    this.gradient = AppColors.primaryGradient,
    this.borderWidth = 2,
    this.blurRadius = 10,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: gradient,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.5),
            blurRadius: blurRadius,
            spreadRadius: -2,
          ),
        ],
      ),
      padding: EdgeInsets.all(borderWidth),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16 - borderWidth),
          color: Colors.transparent,
        ),
        child: child,
      ),
    );
  }
}
