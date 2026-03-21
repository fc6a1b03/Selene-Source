import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selene/design/design_system.dart';

/// 霓虹按钮组件
///
/// 带有发光效果和渐变背景的现代化按钮
class NeonButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Gradient gradient;
  final double borderRadius;
  final double height;
  final EdgeInsetsGeometry padding;
  final bool isLoading;
  final bool isFullWidth;
  final TextStyle? textStyle;

  const NeonButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.gradient = AppColors.primaryGradient,
    this.borderRadius = 16,
    this.height = 52,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
    this.isLoading = false,
    this.isFullWidth = false,
    this.textStyle,
  });

  @override
  State<NeonButton> createState() => _NeonButtonState();
}

class _NeonButtonState extends State<NeonButton> {
  final ValueNotifier<bool> _isPressed = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isHovered = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _isPressed.dispose();
    _isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => _isHovered.value = true,
      onExit: (_) => _isHovered.value = false,
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) {
          _isPressed.value = true;
          HapticFeedback.lightImpact();
        },
        onTapUp: (_) => _isPressed.value = false,
        onTapCancel: () => _isPressed.value = false,
        onTap: widget.isLoading ? null : widget.onPressed,
        child: ValueListenableBuilder<bool>(
          valueListenable: _isPressed,
          builder: (context, isPressed, child) {
            return ValueListenableBuilder<bool>(
              valueListenable: _isHovered,
              builder: (context, isHovered, child) {
                final scale = isPressed ? 0.97 : (isHovered ? 1.02 : 1.0);
                return AnimatedScale(
                  scale: scale,
                  duration: AppAnimations.fast,
                  curve: AppAnimations.standard,
                  child: Container(
                    height: widget.height,
                    width: widget.isFullWidth ? double.infinity : null,
                    padding: widget.padding,
                    decoration: BoxDecoration(
                      gradient: widget.gradient,
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                      boxShadow: _buildShadows(isPressed, isHovered),
                    ),
                    child: AnimatedOpacity(
                      duration: AppAnimations.fast,
                      opacity: widget.onPressed == null ? 0.5 : 1.0,
                      child: _buildContent(),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  List<BoxShadow> _buildShadows(bool isPressed, bool isHovered) {
    if (isPressed) {
      return [
        BoxShadow(
          color: AppColors.primary.withValues(alpha: 0.3),
          blurRadius: 10,
          offset: const Offset(0, 2),
        ),
      ];
    }

    final baseShadows = [
      BoxShadow(
        color: AppColors.primary.withValues(alpha: 0.4),
        blurRadius: 20,
        offset: const Offset(0, 8),
        spreadRadius: -4,
      ),
    ];

    if (isHovered) {
      baseShadows.add(
        BoxShadow(
          color: AppColors.secondary.withValues(alpha: 0.3),
          blurRadius: 30,
          spreadRadius: -2,
        ),
      );
    }

    return baseShadows;
  }

  Widget _buildContent() {
    if (widget.isLoading) {
      return const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      );
    }

    final children = <Widget>[];

    if (widget.icon != null) {
      children.add(Icon(widget.icon, color: Colors.white, size: 20));
      children.add(const SizedBox(width: 8));
    }

    children.add(
      Text(
        widget.text,
        style: widget.textStyle ??
            AppTypography.buttonStyle().copyWith(
              fontSize: 16,
              fontWeight: AppTypography.semiBold,
            ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: children,
    );
  }
}

/// 轮廓霓虹按钮
class NeonOutlineButton extends StatefulWidget {
  final String text;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color borderColor;
  final double borderRadius;
  final double height;
  final EdgeInsetsGeometry padding;
  final bool isFullWidth;
  final TextStyle? textStyle;

  const NeonOutlineButton({
    super.key,
    required this.text,
    this.onPressed,
    this.icon,
    this.borderColor = AppColors.primary,
    this.borderRadius = 16,
    this.height = 52,
    this.padding = const EdgeInsets.symmetric(horizontal: 24),
    this.isFullWidth = false,
    this.textStyle,
  });

  @override
  State<NeonOutlineButton> createState() => _NeonOutlineButtonState();
}

class _NeonOutlineButtonState extends State<NeonOutlineButton> {
  final ValueNotifier<bool> _isHovered = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _isHovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return MouseRegion(
      onEnter: (_) => _isHovered.value = true,
      onExit: (_) => _isHovered.value = false,
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onPressed,
        child: ValueListenableBuilder<bool>(
          valueListenable: _isHovered,
          builder: (context, isHovered, child) {
            return AnimatedContainer(
              duration: AppAnimations.fast,
              height: widget.height,
              width: widget.isFullWidth ? double.infinity : null,
              padding: widget.padding,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(widget.borderRadius),
                border: Border.all(
                  color: isHovered
                      ? widget.borderColor
                      : widget.borderColor.withValues(alpha: 0.5),
                  width: isHovered ? 2 : 1.5,
                ),
                boxShadow: isHovered
                    ? [
                        BoxShadow(
                          color: widget.borderColor.withValues(alpha: 0.3),
                          blurRadius: 15,
                          spreadRadius: -2,
                        ),
                      ]
                    : null,
              ),
              child: _buildContent(isDark),
            );
          },
        ),
      ),
    );
  }

  Widget _buildContent(bool isDark) {
    final children = <Widget>[];

    if (widget.icon != null) {
      children.add(
        Icon(
          widget.icon,
          color: widget.borderColor,
          size: 20,
        ),
      );
      children.add(const SizedBox(width: 8));
    }

    children.add(
      Text(
        widget.text,
        style: widget.textStyle ??
            AppTypography.primary(
              fontSize: 16,
              fontWeight: AppTypography.semiBold,
              color: widget.borderColor,
            ),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: children,
    );
  }
}

/// 图标霓虹按钮
class NeonIconButton extends StatefulWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;
  final Color? backgroundColor;
  final double borderRadius;
  final bool isGlow;

  const NeonIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 48,
    this.color,
    this.backgroundColor,
    this.borderRadius = 12,
    this.isGlow = true,
  });

  @override
  State<NeonIconButton> createState() => _NeonIconButtonState();
}

class _NeonIconButtonState extends State<NeonIconButton> {
  final ValueNotifier<bool> _isHovered = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isPressed = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _isHovered.dispose();
    _isPressed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveColor = widget.color ?? AppColors.primary;

    return MouseRegion(
      onEnter: (_) => _isHovered.value = true,
      onExit: (_) => _isHovered.value = false,
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTapDown: (_) => _isPressed.value = true,
        onTapUp: (_) => _isPressed.value = false,
        onTapCancel: () => _isPressed.value = false,
        onTap: widget.onPressed,
        child: ValueListenableBuilder<bool>(
          valueListenable: _isPressed,
          builder: (context, isPressed, child) {
            return ValueListenableBuilder<bool>(
              valueListenable: _isHovered,
              builder: (context, isHovered, child) {
                final scale = isPressed ? 0.9 : (isHovered ? 1.1 : 1.0);
                return AnimatedScale(
                  scale: scale,
                  duration: AppAnimations.fast,
                  curve: AppAnimations.emphasize,
                  child: Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      color: widget.backgroundColor ??
                          (isDark
                              ? AppColors.darkElevated
                              : AppColors.lightSurface),
                      borderRadius: BorderRadius.circular(widget.borderRadius),
                      boxShadow: widget.isGlow && isHovered
                          ? [
                              BoxShadow(
                                color: effectiveColor.withValues(alpha: 0.5),
                                blurRadius: 20,
                                spreadRadius: -5,
                              ),
                            ]
                          : AppShadows.small,
                    ),
                    child: Icon(
                      widget.icon,
                      color: effectiveColor,
                      size: widget.size * 0.4,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
