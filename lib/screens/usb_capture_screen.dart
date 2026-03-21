import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/services/theme_service.dart';
import 'package:selene/services/usb_capture_service.dart';
import 'package:selene/utils/font_utils.dart';
import 'package:selene/widgets/video_player_widget.dart';
import 'package:url_launcher/url_launcher.dart';

/// USB 采集卡播放页面
///
/// 用于查看通过 USB 采集卡连接的服务器画面
/// 注意：Android 上播放 USB 摄像头需要特殊处理，v4l2 协议可能不被支持
class UsbCaptureScreen extends StatefulWidget {
  const UsbCaptureScreen({super.key});

  @override
  State<UsbCaptureScreen> createState() => _UsbCaptureScreenState();
}

class _UsbCaptureScreenState extends State<UsbCaptureScreen>
    with WidgetsBindingObserver {
  // 视频播放器控制器
  VideoPlayerWidgetController? _videoController;

  // 当前播放的 URL
  String? _currentUrl;

  // 是否正在加载
  bool _isLoading = true;

  // 错误信息
  String? _errorMessage;

  // 是否使用替代播放器
  bool _useAlternativePlayer = false;

  @override
  void initState() {
    super.initState();
    debugPrint('UsbCaptureScreen: initState');
    WidgetsBinding.instance.addObserver(this);

    // 延迟初始化，确保页面已构建
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeCaptureCard();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      // 应用进入后台时暂停播放
      _videoController?.pause();
    } else if (state == AppLifecycleState.resumed) {
      // 应用回到前台时恢复播放
      _videoController?.play();
    }
  }

  /// 初始化采集卡播放
  void _initializeCaptureCard() {
    final service = UsbCaptureService.instance;

    if (!service.isCaptureCardConnected) {
      setState(() {
        _isLoading = false;
        _errorMessage = '未检测到 USB 采集卡';
      });
      return;
    }

    // 获取采集卡流 URL
    final url = service.getCaptureStreamUrl();
    debugPrint('UsbCaptureScreen: 获取到 URL: $url');

    if (url != null) {
      // 在 Android 上，v4l2 协议可能不被支持
      // 尝试播放，如果失败会显示错误和替代方案
      _tryPlayUrl(url);
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = '无法获取采集卡视频流';
      });
    }
  }

  /// 尝试播放指定 URL
  void _tryPlayUrl(String url) {
    debugPrint('UsbCaptureScreen: 尝试播放 $url');
    setState(() {
      _currentUrl = url;
      _isLoading = true;
      _errorMessage = null;
    });
  }

  /// 处理播放器错误
  void _onPlayerError(String error) {
    debugPrint('UsbCaptureScreen: 播放器错误: $error');

    // 如果是 v4l2 相关错误，显示特殊提示
    if (_currentUrl?.startsWith('v4l2://') == true && Platform.isAndroid) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Android 系统暂不支持直接播放 USB 摄像头\n\n'
            '错误: $error\n\n'
            '建议使用第三方 USB 摄像头应用，如:\n'
            '• USB Camera (by Shenzhen Alex)\n'
            '• CameraFi';
        _useAlternativePlayer = true;
      });
    } else {
      setState(() {
        _isLoading = false;
        _errorMessage = '播放失败: $error';
      });
    }
  }

  /// 处理播放器就绪
  void _onPlayerReady() {
    debugPrint('UsbCaptureScreen: 播放器就绪');
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 处理返回按钮
  void _onBackPressed() {
    Navigator.of(context).pop();
  }

  /// 打开推荐应用
  Future<void> _openRecommendedApps() async {
    // 打开应用商店搜索 USB Camera
    final url = Uri.parse('market://search?q=usb+camera');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      // 如果打不开应用商店，打开网页搜索
      final webUrl =
          Uri.parse('https://play.google.com/store/search?q=usb+camera&c=apps');
      if (await canLaunchUrl(webUrl)) {
        await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        final isDark = themeService.isDarkMode;

        return Scaffold(
          backgroundColor: Colors.black,
          body: AnnotatedRegion<SystemUiOverlayStyle>(
            value:
                isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
            child: SafeArea(
              child: Column(
                children: [
                  // 顶部导航栏
                  _buildAppBar(isDark),
                  // 视频播放区域
                  Expanded(
                    child: _buildVideoPlayer(isDark),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建顶部导航栏
  Widget _buildAppBar(bool isDark) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 返回按钮
          IconButton(
            onPressed: _onBackPressed,
            icon: Icon(
              Platform.isIOS ? LucideIcons.chevronLeft : LucideIcons.arrowLeft,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 8),
          // 标题
          Expanded(
            child: Text(
              'USB 采集卡',
              style: FontUtils.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // 刷新按钮
          IconButton(
            onPressed: _initializeCaptureCard,
            icon: const Icon(
              LucideIcons.refreshCw,
              color: Colors.white,
              size: 20,
            ),
            tooltip: '重新连接',
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  /// 构建视频播放器
  Widget _buildVideoPlayer(bool isDark) {
    // 显示错误状态
    if (_errorMessage != null) {
      return _buildErrorState(isDark);
    }

    // 显示加载状态
    if (_isLoading || _currentUrl == null) {
      return _buildLoadingState(isDark);
    }

    // 显示视频播放器
    return VideoPlayerWidget(
      url: _currentUrl,
      live: true, // 启用直播模式
      onBackPressed: _onBackPressed,
      onControllerCreated: (controller) {
        _videoController = controller;
      },
      onReady: _onPlayerReady,
      onError: _onPlayerError,
      onVideoCompleted: () {
        // 直播流不会完成，这里处理意外断开
        debugPrint('UsbCaptureScreen: 视频流结束');
      },
      videoTitle: 'USB 采集卡',
    );
  }

  /// 构建加载状态
  Widget _buildLoadingState(bool isDark) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '正在连接采集卡...',
            style: FontUtils.poppins(
              fontSize: 14,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _currentUrl ?? '',
            style: FontUtils.poppins(
              fontSize: 12,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 16),
          // 提示信息
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  LucideIcons.info,
                  size: 16,
                  color: Colors.white54,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '如果长时间无法播放，可能是您的设备不支持直接预览 USB 摄像头',
                    style: FontUtils.poppins(
                      fontSize: 12,
                      color: Colors.white54,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建错误状态
  Widget _buildErrorState(bool isDark) {
    final isV4l2Error = _useAlternativePlayer;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isV4l2Error ? LucideIcons.smartphone : LucideIcons.monitorX,
              size: 64,
              color: isV4l2Error
                  ? Colors.orange.withValues(alpha: 0.5)
                  : Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              isV4l2Error ? '需要第三方应用' : '无法显示画面',
              style: FontUtils.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _errorMessage!,
              style: FontUtils.poppins(
                fontSize: 13,
                color: Colors.white54,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (isV4l2Error) ...[
              // 打开应用商店按钮
              ElevatedButton.icon(
                onPressed: _openRecommendedApps,
                icon: const Icon(LucideIcons.externalLink, size: 18),
                label: const Text('查找 USB 摄像头应用'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            // 重试按钮
            TextButton.icon(
              onPressed: _initializeCaptureCard,
              icon: const Icon(LucideIcons.refreshCw, size: 18),
              label: const Text('重试'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white70,
              ),
            ),
            const SizedBox(height: 24),
            // 技术信息
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '技术信息',
                    style: FontUtils.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white54,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '当前 URL: ${_currentUrl ?? '未设置'}',
                    style: FontUtils.poppins(
                      fontSize: 11,
                      color: Colors.white38,
                    ),
                  ),
                  Text(
                    '平台: ${Platform.operatingSystem}',
                    style: FontUtils.poppins(
                      fontSize: 11,
                      color: Colors.white38,
                    ),
                  ),
                  if (isV4l2Error)
                    Text(
                      '说明: Android 系统限制，无法直接访问 /dev/video 设备',
                      style: FontUtils.poppins(
                        fontSize: 11,
                        color: Colors.orange.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
