import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:selene/design/colors.dart';

/// Design System 2026 - 字体系统
///
/// 采用 Inter 作为主字体，JetBrains Mono 作为等宽字体
/// 提供统一的文字样式和尺寸规范
class AppTypography {
  AppTypography._();

  // ==================== 字体族 ====================
  /// 主字体族
  static String get primaryFontFamily =>
      Platform.isWindows ? 'Microsoft YaHei' : 'Inter';

  /// 等宽字体族
  static String get monoFontFamily => 'JetBrains Mono';

  // ==================== 字号规范 ====================
  /// 超大标题 - 用于 Hero 区域
  static const double displayLarge = 48.0;

  /// 大标题 - 用于页面标题
  static const double displayMedium = 36.0;

  /// 中标题 - 用于区块标题
  static const double displaySmall = 28.0;

  /// 大标题 - 用于卡片标题
  static const double headlineLarge = 24.0;

  /// 中标题 - 用于列表标题
  static const double headlineMedium = 20.0;

  /// 小标题 - 用于小标题
  static const double headlineSmall = 18.0;

  /// 大正文 - 用于重要正文
  static const double bodyLarge = 16.0;

  /// 中正文 - 默认正文
  static const double bodyMedium = 14.0;

  /// 小正文 - 用于辅助文字
  static const double bodySmall = 12.0;

  /// 标签文字 - 用于标签和徽章
  static const double labelLarge = 14.0;

  /// 小标签 - 用于小标签
  static const double labelMedium = 12.0;

  /// 超小标签 - 用于时间戳等
  static const double labelSmall = 10.0;

  // ==================== 字重规范 ====================
  static const FontWeight thin = FontWeight.w100;
  static const FontWeight extraLight = FontWeight.w200;
  static const FontWeight light = FontWeight.w300;
  static const FontWeight regular = FontWeight.w400;
  static const FontWeight medium = FontWeight.w500;
  static const FontWeight semiBold = FontWeight.w600;
  static const FontWeight bold = FontWeight.w700;
  static const FontWeight extraBold = FontWeight.w800;
  static const FontWeight black = FontWeight.w900;

  // ==================== 行高规范 ====================
  static const double tight = 1.2;
  static const double normal = 1.5;
  static const double relaxed = 1.75;

  // ==================== 获取字体样式 ====================

  /// 获取主字体样式
  static TextStyle primary({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
  }) {
    if (Platform.isWindows) {
      return TextStyle(
        fontFamily: 'Microsoft YaHei',
        fontSize: fontSize ?? bodyMedium,
        fontWeight: fontWeight ?? regular,
        color: color,
        height: height ?? normal,
        letterSpacing: letterSpacing,
        decoration: decoration,
      );
    }
    return GoogleFonts.inter(
      fontSize: fontSize ?? bodyMedium,
      fontWeight: fontWeight ?? regular,
      color: color,
      height: height ?? normal,
      letterSpacing: letterSpacing,
      decoration: decoration,
    );
  }

  /// 获取等宽字体样式
  static TextStyle mono({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize ?? bodyMedium,
      fontWeight: fontWeight ?? regular,
      color: color,
      height: height ?? normal,
      letterSpacing: letterSpacing,
    );
  }

  /// 获取品牌字体样式（用于 Logo）
  static TextStyle brand({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
  }) {
    return GoogleFonts.spaceGrotesk(
      fontSize: fontSize ?? displayMedium,
      fontWeight: fontWeight ?? semiBold,
      color: color,
      letterSpacing: 2.0,
    );
  }

  // ==================== 预设文字样式 ====================

  /// 超大显示文字
  static TextStyle displayLargeStyle({bool isDark = false}) => primary(
        fontSize: displayLarge,
        fontWeight: bold,
        color: AppColors.textPrimary(isDark: isDark),
        height: tight,
        letterSpacing: -1.0,
      );

  /// 大显示文字
  static TextStyle displayMediumStyle({bool isDark = false}) => primary(
        fontSize: displayMedium,
        fontWeight: bold,
        color: AppColors.textPrimary(isDark: isDark),
        height: tight,
        letterSpacing: -0.5,
      );

  /// 小显示文字
  static TextStyle displaySmallStyle({bool isDark = false}) => primary(
        fontSize: displaySmall,
        fontWeight: semiBold,
        color: AppColors.textPrimary(isDark: isDark),
        height: tight,
      );

  /// 大标题
  static TextStyle headlineLargeStyle({bool isDark = false}) => primary(
        fontSize: headlineLarge,
        fontWeight: semiBold,
        color: AppColors.textPrimary(isDark: isDark),
        height: tight,
      );

  /// 中标题
  static TextStyle headlineMediumStyle({bool isDark = false}) => primary(
        fontSize: headlineMedium,
        fontWeight: semiBold,
        color: AppColors.textPrimary(isDark: isDark),
        height: tight,
      );

  /// 小标题
  static TextStyle headlineSmallStyle({bool isDark = false}) => primary(
        fontSize: headlineSmall,
        fontWeight: semiBold,
        color: AppColors.textPrimary(isDark: isDark),
        height: tight,
      );

  /// 大正文
  static TextStyle bodyLargeStyle({bool isDark = false}) => primary(
        fontSize: bodyLarge,
        fontWeight: regular,
        color: AppColors.textPrimary(isDark: isDark),
        height: normal,
      );

  /// 中正文
  static TextStyle bodyMediumStyle({bool isDark = false}) => primary(
        fontSize: bodyMedium,
        fontWeight: regular,
        color: AppColors.textPrimary(isDark: isDark),
        height: normal,
      );

  /// 小正文
  static TextStyle bodySmallStyle({bool isDark = false}) => primary(
        fontSize: bodySmall,
        fontWeight: regular,
        color: AppColors.textSecondary(isDark: isDark),
        height: normal,
      );

  /// 大标签
  static TextStyle labelLargeStyle({bool isDark = false}) => primary(
        fontSize: labelLarge,
        fontWeight: medium,
        color: AppColors.textPrimary(isDark: isDark),
        height: tight,
        letterSpacing: 0.5,
      );

  /// 中标签
  static TextStyle labelMediumStyle({bool isDark = false}) => primary(
        fontSize: labelMedium,
        fontWeight: medium,
        color: AppColors.textSecondary(isDark: isDark),
        height: tight,
        letterSpacing: 0.5,
      );

  /// 小标签
  static TextStyle labelSmallStyle({bool isDark = false}) => primary(
        fontSize: labelSmall,
        fontWeight: medium,
        color: AppColors.textTertiary(isDark: isDark),
        height: tight,
        letterSpacing: 0.5,
      );

  /// 按钮文字
  static TextStyle buttonStyle({bool isDark = false}) => primary(
        fontSize: bodyMedium,
        fontWeight: semiBold,
        color: Colors.white,
        height: tight,
        letterSpacing: 0.5,
      );

  /// 渐变文字样式
  static TextStyle gradientStyle({
    required Gradient gradient,
    double? fontSize,
    FontWeight? fontWeight,
  }) {
    return primary(
      fontSize: fontSize ?? headlineMedium,
      fontWeight: fontWeight ?? bold,
    );
  }

  /// 视频标题样式
  static TextStyle videoTitle({bool isDark = false, double? fontSize}) =>
      primary(
        fontSize: fontSize ?? bodyMedium,
        fontWeight: semiBold,
        color: AppColors.textPrimary(isDark: isDark),
        height: tight,
      );

  /// 视频副标题样式
  static TextStyle videoSubtitle({bool isDark = false, double? fontSize}) =>
      primary(
        fontSize: fontSize ?? bodySmall,
        fontWeight: medium,
        color: AppColors.textSecondary(isDark: isDark),
        height: tight,
      );

  /// 徽章文字样式
  static TextStyle badgeStyle({bool isDark = false}) => primary(
        fontSize: labelSmall,
        fontWeight: bold,
        color: Colors.white,
        height: tight,
      );
}

/// 渐变文字 Widget
class GradientText extends StatelessWidget {
  final String text;
  final Gradient gradient;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  const GradientText({
    super.key,
    required this.text,
    required this.gradient,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
  });

  @override
  Widget build(BuildContext context) {
    final defaultStyle = AppTypography.displayMediumStyle();
    final effectiveStyle = style ?? defaultStyle;

    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(
        Rect.fromLTWH(0, 0, bounds.width, bounds.height),
      ),
      child: Text(
        text,
        style: effectiveStyle.copyWith(color: Colors.white),
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      ),
    );
  }
}
