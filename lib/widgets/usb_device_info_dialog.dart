import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/utils/font_utils.dart';

/// USB 设备信息对话框
///
/// 美观地显示 USB 设备详细信息
class UsbDeviceInfoDialog extends StatelessWidget {
  final List<Map<dynamic, dynamic>> devices;
  final bool isDarkMode;

  const UsbDeviceInfoDialog({
    super.key,
    required this.devices,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 600),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 标题栏
            _buildHeader(),
            // 设备列表
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: devices.length,
                itemBuilder: (context, index) {
                  return _buildDeviceCard(context, devices[index], index);
                },
              ),
            ),
            // 底部按钮
            _buildFooter(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              LucideIcons.usb,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'USB 设备',
                  style: FontUtils.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '检测到 ${devices.length} 个设备',
                  style: FontUtils.poppins(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(
      BuildContext context, Map<dynamic, dynamic> device, int index) {
    final vid = device['vid'] as int? ?? 0;
    final pid = device['pid'] as int? ?? 0;
    final name = device['productName'] as String? ?? 'Unknown Device';
    final manufacturer = device['manufacturerName'] as String? ?? 'Unknown';
    final chipName = device['chipName'] as String? ?? 'Unknown';
    final isCaptureCard = device['isCaptureCard'] as bool? ?? false;
    final hasVideo = device['hasVideoInterface'] as bool? ?? false;
    final hasAudio = device['hasAudioInterface'] as bool? ?? false;
    final interfaceCount = device['interfaceCount'] as int? ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: isCaptureCard
            ? LinearGradient(
                colors: [
                  AppColors.primary.withValues(alpha: 0.15),
                  AppColors.secondary.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isCaptureCard
            ? null
            : (isDarkMode ? const Color(0xFF2D3748) : const Color(0xFFF7FAFC)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCaptureCard
              ? AppColors.primary.withValues(alpha: 0.3)
              : (isDarkMode
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.05)),
          width: isCaptureCard ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // 设备头部
            Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // 设备图标
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient:
                          isCaptureCard ? AppColors.primaryGradient : null,
                      color: isCaptureCard
                          ? null
                          : (isDarkMode
                              ? const Color(0xFF4A5568)
                              : const Color(0xFFE2E8F0)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      hasVideo ? LucideIcons.video : LucideIcons.usb,
                      color: isCaptureCard
                          ? Colors.white
                          : (isDarkMode
                              ? Colors.white70
                              : const Color(0xFF4A5568)),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 设备名称和芯片
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: FontUtils.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: isDarkMode
                                ? Colors.white
                                : const Color(0xFF1F2937),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          chipName,
                          style: FontUtils.poppins(
                            fontSize: 12,
                            color: isCaptureCard
                                ? AppColors.primary
                                : (isDarkMode
                                    ? Colors.white60
                                    : const Color(0xFF6B7280)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 采集卡标记
                  if (isCaptureCard)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '采集卡',
                        style: FontUtils.poppins(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 分割线
            Divider(
              height: 1,
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.black.withValues(alpha: 0.05),
            ),
            // 详细信息
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildInfoRow('厂商', manufacturer, LucideIcons.building2),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                      'VID',
                      '0x${vid.toRadixString(16).toUpperCase().padLeft(4, '0')} ($vid)',
                      LucideIcons.scanLine),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                      'PID',
                      '0x${pid.toRadixString(16).toUpperCase().padLeft(4, '0')} ($pid)',
                      LucideIcons.hash),
                  const SizedBox(height: 8),
                  _buildInfoRow('接口', '$interfaceCount 个', LucideIcons.plug),
                  const SizedBox(height: 12),
                  // 功能标签
                  Row(
                    children: [
                      if (hasVideo)
                        _buildFeatureTag(
                            '视频', LucideIcons.video, const Color(0xFF10B981)),
                      if (hasVideo) const SizedBox(width: 8),
                      if (hasAudio)
                        _buildFeatureTag(
                            '音频', LucideIcons.mic, const Color(0xFF8B5CF6)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color: isDarkMode
              ? Colors.white.withValues(alpha: 0.4)
              : const Color(0xFF9CA3AF),
        ),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: FontUtils.poppins(
            fontSize: 12,
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.5)
                : const Color(0xFF6B7280),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: FontUtils.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDarkMode ? Colors.white : const Color(0xFF374151),
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildFeatureTag(String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12,
            color: color,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: FontUtils.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 复制按钮
          TextButton.icon(
            onPressed: () => _copyDeviceInfo(context),
            icon: Icon(
              LucideIcons.copy,
              size: 16,
              color: AppColors.primary,
            ),
            label: Text(
              '复制信息',
              style: FontUtils.poppins(
                fontSize: 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 关闭按钮
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              '关闭',
              style: FontUtils.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _copyDeviceInfo(BuildContext context) {
    final buffer = StringBuffer();
    buffer.writeln('USB 设备信息 (${devices.length} 个):');
    buffer.writeln();

    for (var i = 0; i < devices.length; i++) {
      final d = devices[i];
      buffer.writeln('设备 ${i + 1}: ${d['productName']}');
      buffer.writeln('  芯片: ${d['chipName']}');
      buffer.writeln('  厂商: ${d['manufacturerName']}');
      buffer.writeln(
          '  VID: 0x${(d['vid'] as int).toRadixString(16).toUpperCase().padLeft(4, '0')}');
      buffer.writeln(
          '  PID: 0x${(d['pid'] as int).toRadixString(16).toUpperCase().padLeft(4, '0')}');
      buffer.writeln('  接口: ${d['interfaceCount']} 个');
      buffer.writeln('  视频: ${d['hasVideoInterface'] == true ? '支持' : '不支持'}');
      buffer.writeln('  音频: ${d['hasAudioInterface'] == true ? '支持' : '不支持'}');
      buffer.writeln();
    }

    // 复制到剪贴板
    Clipboard.setData(ClipboardData(text: buffer.toString()));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '设备信息已复制',
          style: FontUtils.poppins(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF27AE60),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}
