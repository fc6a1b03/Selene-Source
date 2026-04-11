import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/services/advanced_download_manager.dart';
import 'package:selene/services/theme_service.dart';

/// Windows 无边框标题栏
///
/// 完全透明融入应用，仅显示悬浮控制按钮
class WindowsTitleBar extends StatelessWidget {
  final bool forceBlack;
  final Color? customBackgroundColor;

  const WindowsTitleBar({
    super.key,
    this.forceBlack = false,
    this.customBackgroundColor,
  });

  /// 处理关闭按钮点击
  void _handleClose(BuildContext context) async {
    // 检查是否有正在下载的任务
    final downloadManager = AdvancedDownloadManager();
    final activeTasks = downloadManager.activeTasks;
    final bool hasActiveDownloads = activeTasks.isNotEmpty;

    // 显示确认对话框
    final bool? shouldClose = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        title: Row(
          children: [
            Icon(
              Icons.exit_to_app,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(width: 12),
            const Text('确认关闭'),
          ],
        ),
        content: Text(
          hasActiveDownloads
              ? '有 ${activeTasks.length} 个下载任务正在进行中，关闭应用将会暂停这些任务。\n\n确定要关闭应用吗？'
              : '确定要关闭应用吗？',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('关闭'),
          ),
        ],
      ),
    );

    if (shouldClose == true) {
      appWindow.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        final isDark = themeService.isDarkMode;

        // 文字/图标颜色
        final foregroundColor =
            isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;

        return SizedBox(
          height: 40,
          child: Row(
            children: [
              // 左侧可拖动区域
              Expanded(
                child: MoveWindow(
                  child: Container(
                    height: 40,
                    color: Colors.transparent,
                  ),
                ),
              ),
              // 右侧窗口控制按钮组
              _buildWindowControls(context, foregroundColor, isDark),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWindowControls(
      BuildContext context, Color foregroundColor, bool isDark) {
    return Container(
      margin: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.darkSurface.withValues(alpha: 0.6)
            : AppColors.lightSurface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark
              ? AppColors.darkBorder.withValues(alpha: 0.3)
              : AppColors.lightBorder.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _WindowControlButton(
            onPressed: () => appWindow.minimize(),
            icon: _MinimizeIcon(color: foregroundColor),
            isDark: isDark,
          ),
          _WindowControlButton(
            onPressed: () => appWindow.maximizeOrRestore(),
            icon: _MaximizeIcon(color: foregroundColor),
            isDark: isDark,
          ),
          _WindowControlButton(
            onPressed: () => _handleClose(context),
            icon: Icon(Icons.close, size: 14, color: foregroundColor),
            isDark: isDark,
            isCloseButton: true,
          ),
        ],
      ),
    );
  }
}

/// 窗口控制按钮
class _WindowControlButton extends StatefulWidget {
  final VoidCallback onPressed;
  final Widget icon;
  final bool isDark;
  final bool isCloseButton;

  const _WindowControlButton({
    required this.onPressed,
    required this.icon,
    required this.isDark,
    this.isCloseButton = false,
  });

  @override
  State<_WindowControlButton> createState() => _WindowControlButtonState();
}

class _WindowControlButtonState extends State<_WindowControlButton> {
  bool _isHovered = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    Color? backgroundColor;

    if (_isPressed) {
      backgroundColor = widget.isCloseButton
          ? const Color(0xFFDC2626)
          : (widget.isDark
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.08));
    } else if (_isHovered) {
      backgroundColor = widget.isCloseButton
          ? const Color(0xFFEF4444)
          : (widget.isDark
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.black.withValues(alpha: 0.05));
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() {
        _isHovered = false;
        _isPressed = false;
      }),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) {
          setState(() => _isPressed = false);
          widget.onPressed();
        },
        onTapCancel: () => setState(() => _isPressed = false),
        child: Container(
          width: 36,
          height: 28,
          decoration: BoxDecoration(
            color: backgroundColor ?? Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: widget.isCloseButton && _isHovered
                ? const Icon(
                    Icons.close,
                    size: 14,
                    color: Colors.white,
                  )
                : widget.icon,
          ),
        ),
      ),
    );
  }
}

/// 最小化图标
class _MinimizeIcon extends StatelessWidget {
  final Color color;

  const _MinimizeIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: color, width: 1.5),
        ),
      ),
    );
  }
}

/// 最大化/还原图标
class _MaximizeIcon extends StatelessWidget {
  final Color color;

  const _MaximizeIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.5),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
