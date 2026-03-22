import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/utils/font_utils.dart';

/// USB 采集卡提示组件
///
/// 当检测到 USB 视频采集卡插入时显示提示条，用户点击可查看服务器画面
class UsbCaptureNotification extends StatelessWidget {
  final VoidCallback? onTap;

  const UsbCaptureNotification({
    super.key,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.2),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                // 图标
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    LucideIcons.monitor,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                // 文字内容
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '检测到服务器画面输入',
                        style: FontUtils.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary(isDark: isDark),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '点击查看实时画面',
                        style: FontUtils.poppins(
                          fontSize: 12,
                          color: AppColors.textSecondary(isDark: isDark),
                        ),
                      ),
                    ],
                  ),
                ),
                // 箭头图标
                Icon(
                  LucideIcons.chevronRight,
                  color: AppColors.primary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// USB 采集卡连接提示对话框
///
/// 首次连接采集卡时显示的说明对话框
class UsbCaptureInfoDialog extends StatelessWidget {
  final VoidCallback? onViewPressed;
  final VoidCallback? onDismissPressed;

  const UsbCaptureInfoDialog({
    super.key,
    this.onViewPressed,
    this.onDismissPressed,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 图标
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              LucideIcons.monitor,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 16),
          // 标题
          Text(
            '检测到 USB 采集卡',
            style: AppTypography.headlineSmallStyle(isDark: isDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          // 说明文字
          Text(
            '您可以通过 USB 采集卡查看服务器的实时画面。点击"查看画面"开始使用。',
            style: AppTypography.bodyMediumStyle(isDark: isDark).copyWith(
              color: AppColors.textSecondary(isDark: isDark),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: onDismissPressed ?? () => Navigator.of(context).pop(),
          child: Text(
            '稍后再说',
            style: FontUtils.poppins(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: onViewPressed,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          child: Text(
            '查看画面',
            style: FontUtils.poppins(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
