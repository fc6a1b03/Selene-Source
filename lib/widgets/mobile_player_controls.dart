import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:selene/components/animations/video_loading_animation.dart';
import 'package:selene/models/video_download_info.dart';
import 'package:selene/services/screenshot_service.dart';
import 'package:selene/widgets/dlna_device_dialog.dart';
import 'package:volume_controller/volume_controller.dart';

class MobilePlayerControls extends StatefulWidget {
  final Player player;
  final VideoState state;

  // ignore: avoid_positional_boolean_parameters
  final void Function(bool) onControlsVisibilityChanged;
  final VoidCallback? onBackPressed;

  // ignore: avoid_positional_boolean_parameters
  final void Function(bool) onFullscreenChange;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onPause;
  final String videoUrl;
  final bool isLastEpisode;
  final bool isLoadingVideo;
  final void Function(dynamic)? onCastStarted;
  final String? videoTitle;
  final int? currentEpisodeIndex;
  final int? totalEpisodes;
  final String? sourceName;
  final VoidCallback? onExitFullScreen;
  final bool live;
  final ValueNotifier<double> playbackSpeedListenable;
  final Future<void> Function(double speed) onSetSpeed;
  final Future<void> Function() onEnterPipMode;
  final bool isPipMode;
  final VoidCallback? onExitPip;

  // 下载相关参数
  final VideoDownloadInfo downloadInfo;
  final Future<void> Function({String? fileName}) onStartDownload;
  final Future<void> Function() onCancelDownload;
  final Future<String?> Function() onSaveAs;

  const MobilePlayerControls({
    super.key,
    required this.player,
    required this.state,
    required this.onControlsVisibilityChanged,
    this.onBackPressed,
    required this.onFullscreenChange,
    this.onNextEpisode,
    this.onPause,
    required this.videoUrl,
    this.isLastEpisode = false,
    this.isLoadingVideo = false,
    this.onCastStarted,
    this.videoTitle,
    this.currentEpisodeIndex,
    this.totalEpisodes,
    this.sourceName,
    this.onExitFullScreen,
    this.live = false,
    required this.playbackSpeedListenable,
    required this.onSetSpeed,
    required this.onEnterPipMode,
    required this.isPipMode,
    this.onExitPip,
    // 下载相关
    this.downloadInfo = const VideoDownloadInfo(),
    required this.onStartDownload,
    required this.onCancelDownload,
    required this.onSaveAs,
  });

  @override
  State<MobilePlayerControls> createState() => _MobilePlayerControlsState();
}

class _MobilePlayerControlsState extends State<MobilePlayerControls> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Timer? _hideTimer;
  bool _controlsVisible = true;
  bool _isLongPressing = false;
  double _originalPlaybackSpeed = 1.0;
  Duration? _dragPosition;
  bool _isSeekingViaSwipe = false;
  double _swipeStartX = 0;
  Duration _swipeStartPosition = Duration.zero;
  Size? _screenSize;
  bool _isLocked = false;
  bool _showVolumeIndicator = false;
  bool _showBrightnessIndicator = false;
  double _currentVolume = 0.5;
  double _currentBrightness = 0.5;
  Timer? _volumeHideTimer;
  Timer? _brightnessHideTimer;
  Timer? _timeUpdateTimer;
  String _currentTime = '';

  // 缓存全屏状态
  bool _cachedIsFullscreen = false;

  // 截图服务
  final ScreenshotService _screenshotService = ScreenshotService();
  bool _isCapturingScreenshot = false;

  @override
  void initState() {
    super.initState();
    _initSystemControls();
    _listenPlayerStreams();
    _updateCurrentTime();
    _startTimeUpdateTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // PiP 模式下默认隐藏控制栏
      if (widget.isPipMode) {
        setState(() => _controlsVisible = false);
        widget.onControlsVisibilityChanged(false);
      } else {
        _forceStartHideTimer();
        widget.onControlsVisibilityChanged(true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _cachedIsFullscreen = widget.state.isFullscreen();
    } catch (e) {
      // 保留先前的缓存值
    }
  }

  @override
  void didUpdateWidget(covariant MobilePlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    try {
      _cachedIsFullscreen = widget.state.isFullscreen();
    } catch (e) {
      // 忽略
    }
    // 处理 PiP 模式变化
    if (oldWidget.isPipMode && !widget.isPipMode) {
      // 退出 PiP 模式 - 显示控制栏
      setState(() => _controlsVisible = true);
      widget.onControlsVisibilityChanged(true);
      _startHideTimer();
    } else if (!oldWidget.isPipMode && widget.isPipMode) {
      // 进入 PiP 模式 - 隐藏控制栏，保持播放状态不变
      setState(() => _controlsVisible = false);
      widget.onControlsVisibilityChanged(false);
      _hideTimer?.cancel();
    }
  }

  void _initSystemControls() {
    VolumeController.instance.showSystemUI = false;
    VolumeController.instance.getVolume().then((value) {
      if (!mounted) return;
      setState(() => _currentVolume = value);
    }).catchError((_) {});
    ScreenBrightness().application.then((value) {
      if (!mounted) return;
      setState(() => _currentBrightness = value);
    }).catchError((_) {});
  }

  // 用于节流位置更新
  DateTime? _lastPositionUpdate;
  static const _positionUpdateInterval = Duration(milliseconds: 500);

  void _listenPlayerStreams() {
    _subscriptions.add(
      widget.player.stream.playing.listen((playing) {
        if (!mounted) return;
        if (playing && _controlsVisible) {
          _startHideTimer();
        }
        if (!playing) {
          _hideTimer?.cancel();
          if (!_controlsVisible) {
            setState(() => _controlsVisible = true);
            widget.onControlsVisibilityChanged(true);
          }
        }
      }),
    );

    _subscriptions.add(
      widget.player.stream.position.listen((_) {
        if (!mounted) return;
        if (_controlsVisible && !_isSeekingViaSwipe) {
          // 节流：每 500ms 最多更新一次 UI
          final now = DateTime.now();
          if (_lastPositionUpdate == null ||
              now.difference(_lastPositionUpdate!) > _positionUpdateInterval) {
            _lastPositionUpdate = now;
            setState(() {});
          }
        }
      }),
    );

    _subscriptions.add(
      widget.player.stream.completed.listen((_) {
        if (!mounted) return;
        setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _hideTimer?.cancel();
    _volumeHideTimer?.cancel();
    _brightnessHideTimer?.cancel();
    _timeUpdateTimer?.cancel();
    VolumeController.instance.showSystemUI = true;
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  bool get _isFullscreen {
    if (_cachedIsFullscreen) return true;
    try {
      final v = widget.state.isFullscreen();
      _cachedIsFullscreen = v;
      return v;
    } catch (e) {
      return _cachedIsFullscreen;
    }
  }

  bool get _isPlaying => widget.player.state.playing;

  Duration get _position => widget.player.state.position;

  Duration get _duration => widget.player.state.duration;

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_isPlaying) {
      // PiP 模式下控制栏隐藏时间更短
      final hideDuration = widget.isPipMode
          ? const Duration(seconds: 1)
          : const Duration(seconds: 3);
      _hideTimer = Timer(hideDuration, () {
        if (!mounted) return;
        setState(() => _controlsVisible = false);
        widget.onControlsVisibilityChanged(false);
      });
    }
  }

  void _forceStartHideTimer() {
    _hideTimer?.cancel();
    // PiP 模式下控制栏隐藏时间更短
    final hideDuration = widget.isPipMode
        ? const Duration(seconds: 1)
        : const Duration(seconds: 3);
    _hideTimer = Timer(hideDuration, () {
      if (!mounted) return;
      setState(() => _controlsVisible = false);
      widget.onControlsVisibilityChanged(false);
    });
  }

  void _onUserInteraction() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
      widget.onControlsVisibilityChanged(true);
    }
    _startHideTimer();
  }

  void _toggleControlsVisibility() {
    if (_isLocked) {
      setState(() => _controlsVisible = !_controlsVisible);
      if (_controlsVisible) {
        _startHideTimer();
      } else {
        _hideTimer?.cancel();
      }
      return;
    }
    setState(() => _controlsVisible = !_controlsVisible);
    widget.onControlsVisibilityChanged(_controlsVisible);
    if (_controlsVisible) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _onLongPressStart(LongPressStartDetails details) {
    if (_isLocked || widget.live || !_isPlaying) return;
    setState(() {
      _isLongPressing = true;
      _originalPlaybackSpeed = widget.playbackSpeedListenable.value;
    });
    widget.onSetSpeed(2.0);
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_isLocked || !_isLongPressing || widget.live) return;
    widget.onSetSpeed(_originalPlaybackSpeed);
    setState(() => _isLongPressing = false);
  }

  void _onSwipeStart(DragStartDetails details) {
    if (_isLocked || widget.live) return;
    _screenSize ??= MediaQuery.of(context).size;
    setState(() {
      _isSeekingViaSwipe = true;
      _swipeStartX = details.globalPosition.dx;
      _swipeStartPosition = _position;
      _dragPosition = null;
      _controlsVisible = true;
    });
    _hideTimer?.cancel();
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    if (_isLocked ||
        !_isSeekingViaSwipe ||
        widget.live ||
        _screenSize == null) {
      return;
    }
    final screenWidth = _screenSize!.width;
    final swipeDistance = details.globalPosition.dx - _swipeStartX;
    final swipeRatio = swipeDistance / (screenWidth * 0.5);
    final duration = _duration;
    if (duration == Duration.zero) return;
    final targetPosition = _swipeStartPosition +
        Duration(
          milliseconds: (duration.inMilliseconds * swipeRatio * 0.1).round(),
        );
    final clamped = Duration(
      milliseconds:
          targetPosition.inMilliseconds.clamp(0, duration.inMilliseconds),
    );
    setState(() => _dragPosition = clamped);
  }

  void _onSwipeEnd(DragEndDetails details) {
    if (_isLocked || !_isSeekingViaSwipe || widget.live) return;
    if (_dragPosition != null) {
      widget.player.seek(_dragPosition!);
    }
    setState(() {
      _isSeekingViaSwipe = false;
      _dragPosition = null;
    });
    _startHideTimer();
  }

  void _onVolumeSwipeStart(DragStartDetails details) {
    if (!_isFullscreen || _isLocked) return;
    _volumeHideTimer?.cancel();
    _hideTimer?.cancel();
    setState(() => _controlsVisible = true);
  }

  void _onVolumeSwipeUpdate(DragUpdateDetails details) {
    if (!_isFullscreen || _isLocked) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final volumeChange = -(details.delta.dy / screenHeight) * 2;
    setState(() {
      _currentVolume = (_currentVolume + volumeChange).clamp(0.0, 1.0);
      _showVolumeIndicator = true;
    });
    VolumeController.instance.setVolume(_currentVolume);
    _startVolumeHideTimer();
  }

  void _onVolumeSwipeEnd(DragEndDetails details) {
    if (!_isFullscreen || _isLocked) return;
    _startVolumeHideTimer();
    _startHideTimer();
  }

  void _startVolumeHideTimer() {
    _volumeHideTimer?.cancel();
    _volumeHideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showVolumeIndicator = false);
      }
    });
  }

  void _onBrightnessSwipeStart(DragStartDetails details) {
    if (!_isFullscreen || _isLocked) return;
    _brightnessHideTimer?.cancel();
    _hideTimer?.cancel();
    setState(() => _controlsVisible = true);
  }

  void _onBrightnessSwipeUpdate(DragUpdateDetails details) {
    if (!_isFullscreen || _isLocked) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final brightnessChange = -(details.delta.dy / screenHeight) * 2;
    setState(() {
      _currentBrightness =
          (_currentBrightness + brightnessChange).clamp(0.0, 1.0);
      _showBrightnessIndicator = true;
    });
    ScreenBrightness().setApplicationScreenBrightness(_currentBrightness);
    _startBrightnessHideTimer();
  }

  void _onBrightnessSwipeEnd(DragEndDetails details) {
    if (!_isFullscreen || _isLocked) return;
    _startBrightnessHideTimer();
    _startHideTimer();
  }

  void _startBrightnessHideTimer() {
    _brightnessHideTimer?.cancel();
    _brightnessHideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _showBrightnessIndicator = false);
      }
    });
  }

  void _updateCurrentTime() {
    final now = DateTime.now();
    setState(() {
      _currentTime = DateFormat('HH:mm').format(now);
    });
  }

  void _startTimeUpdateTimer() {
    _timeUpdateTimer?.cancel();
    _timeUpdateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        _updateCurrentTime();
      }
    });
  }

  Future<void> _togglePlayPause() async {
    _onUserInteraction();
    if (_isPlaying) {
      await widget.player.pause();
      widget.onPause?.call();
    } else {
      await widget.player.play();
    }
  }

  Future<void> _enterFullscreen() async {
    final shouldLockPortrait = _determineShouldLockPortrait();
    try {
      // 设置屏幕方向（根据视频尺寸固定）
      await _setScreenOrientation(shouldLockPortrait);
      await _hideSystemUI();
    } catch (e) {
      debugPrint('[Fullscreen] Failed while applying orientation/ui: $e');
    }
    // 进入全屏
    await widget.state.enterFullscreen();
    widget.onFullscreenChange(true);
    // Android 需要延迟后再次设置方向，防止系统回调改变方向
    if (Platform.isAndroid) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await _setScreenOrientation(shouldLockPortrait);
    }
    _onUserInteraction();
  }

  /// 判断是否应该锁定竖屏
  ///
  /// 逻辑：
  /// - 竖屏视频（高>宽）：保持竖屏全屏
  /// - 横屏视频（宽>高）：旋转为横屏全屏
  bool _determineShouldLockPortrait() {
    try {
      final videoWidth = widget.player.state.width ?? 0;
      final videoHeight = widget.player.state.height ?? 0;
      // 如果视频尺寸有效，根据视频比例判断
      if (videoWidth > 0 && videoHeight > 0) {
        final videoAspectRatio = videoWidth / videoHeight;
        // 视频比例小于1.0表示竖屏视频（高>宽）
        return videoAspectRatio < 1.0;
      }
      // 视频尺寸未知时，根据当前屏幕方向判断
      final screenSize = MediaQuery.of(context).size;
      final screenAspectRatio = screenSize.width / screenSize.height;
      return screenAspectRatio < 1.0;
    } catch (e) {
      debugPrint('[Fullscreen] _determineShouldLockPortrait error: $e');
      return false;
    }
  }

  Future<void> _setScreenOrientation(bool shouldLockPortrait) async {
    try {
      if (shouldLockPortrait) {
        await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp],
        );
      } else {
        await SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    } catch (e) {
      debugPrint('[Fullscreen] Failed to set orientation: $e');
    }
  }

  Future<void> _hideSystemUI() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (e) {
      debugPrint('[Fullscreen] Failed to hide system UI: $e');
    }
  }

  Future<void> _exitFullscreen() async {
    widget.onFullscreenChange(false);
    await widget.state.exitFullscreen();
    widget.onExitFullScreen?.call();
    setState(() {
      _controlsVisible = true;
      _isLocked = false;
    });
    widget.onControlsVisibilityChanged(true);
    _startHideTimer();
    try {
      await Future.wait([
        _restoreSystemUI(),
        _restoreScreenOrientation(),
      ]);
    } catch (e) {
      debugPrint('[Fullscreen] Error restoring system state: $e');
    }
  }

  Future<void> _restoreSystemUI() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (e) {
      debugPrint('[Fullscreen] Failed to restore system UI: $e');
    }
  }

  Future<void> _restoreScreenOrientation() async {
    try {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (e) {
      debugPrint('[Fullscreen] Failed to restore orientation: $e');
    }
  }

  Future<void> _showDLNADialog() async {
    if (_isPlaying) {
      await widget.player.pause();
      widget.onPause?.call();
    }
    if (_isFullscreen) {
      await _exitFullscreen();
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    final resumePos = widget.player.state.position;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => DLNADeviceDialog(
        currentUrl: widget.videoUrl,
        resumePosition: resumePos,
        videoTitle: widget.videoTitle,
        currentEpisodeIndex: widget.currentEpisodeIndex,
        totalEpisodes: widget.totalEpisodes,
        sourceName: widget.sourceName,
        onCastStarted: widget.onCastStarted,
      ),
    );
  }

  Future<void> _showSpeedDialog() async {
    final speeds = [0.5, 0.75, 1.0, 1.5, 2.0];
    final currentSpeed = widget.playbackSpeedListenable.value;
    final screenHeight = MediaQuery.of(context).size.height;
    final result = await showModalBottomSheet<double>(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: screenHeight * 0.75,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: speeds.map((speed) {
                  final selected = (speed - currentSpeed).abs() < 0.01;
                  return ListTile(
                    title: Text(
                      '${speed}x',
                      style: TextStyle(
                        color: selected
                            ? Colors.red
                            : (isDark ? Colors.white : Colors.black87),
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    onTap: () => Navigator.of(context).pop(speed),
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
    if (result != null) {
      await widget.onSetSpeed(result);
    }
  }

  Future<void> _enterPipMode() async {
    debugPrint('_enterPipMode');
    setState(() => _controlsVisible = false);
    widget.onControlsVisibilityChanged(false);
    _hideTimer?.cancel();
    await widget.onEnterPipMode();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  // ===== 下载按钮处理 =====

  Future<void> _handleDownloadTap() async {
    _onUserInteraction();

    final info = widget.downloadInfo;

    switch (info.state) {
      case VideoDownloadState.idle:
      case VideoDownloadState.failed:
        // 开始下载
        await widget.onStartDownload();
        break;
      case VideoDownloadState.downloading:
        // 取消下载
        await widget.onCancelDownload();
        break;
      case VideoDownloadState.paused:
        // 恢复下载（移动端先取消重新下载）
        await widget.onCancelDownload();
        break;
      case VideoDownloadState.completed:
        // 另存为（移动端保存到相册）
        try {
          final path = await widget.onSaveAs();
          if (path != null && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('视频已保存到相册'),
                duration: Duration(seconds: 2),
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('保存失败: $e'),
                duration: const Duration(seconds: 3),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
        break;
    }
  }

  IconData _getDownloadIcon() {
    switch (widget.downloadInfo.state) {
      case VideoDownloadState.idle:
      case VideoDownloadState.failed:
        return Icons.download;
      case VideoDownloadState.downloading:
        return Icons.close;
      case VideoDownloadState.paused:
        return Icons.play_arrow;
      case VideoDownloadState.completed:
        return Icons.save_alt;
    }
  }

  Color _getDownloadColor() {
    switch (widget.downloadInfo.state) {
      case VideoDownloadState.idle:
      case VideoDownloadState.failed:
        return Colors.white;
      case VideoDownloadState.downloading:
        return Colors.orange;
      case VideoDownloadState.paused:
        return Colors.yellow;
      case VideoDownloadState.completed:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoadingVideo) {
      return ColoredBox(
        color: Colors.black.withValues(alpha: 0.7),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const VideoLoadingIndicator(
                size: 48,
                color: Colors.white,
              ),
              const SizedBox(height: 16),
              Text(
                '加载中...',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // PiP 模式下使用简化 UI
    if (widget.isPipMode) {
      return _buildPipModeUI();
    }

    Widget content = Stack(
      children: [
        _buildGestureLayer(),
        _buildTopGradient(),
        _buildBottomGradient(),
        if (_isFullscreen) _buildCurrentTime(),
        _buildBackButton(),
        _buildCastButton(),
        _buildDownloadButton(),
        _buildCenterPlayPause(),
        _buildProgressBar(),
        _buildBottomControls(),
        if (_isLongPressing && !_isLocked) _buildLongPressIndicator(),
        if (_isFullscreen && _showBrightnessIndicator && !_isLocked)
          _buildBrightnessIndicator(),
        if (_isFullscreen) _buildRightOverlay(),
      ],
    );

    if (_isFullscreen) {
      content = PopScope(
        canPop: !_isLocked,
        onPopInvokedWithResult: (didPop, result) async {
          if (!didPop && _isLocked) {
            setState(() {
              _isLocked = false;
              _controlsVisible = true;
            });
            _startHideTimer();
          }
        },
        child: content,
      );
    }

    return content;
  }

  /// 构建 PiP 模式下的简化 UI
  Widget _buildPipModeUI() {
    return Stack(
      children: [
        // 底部进度条（细线样式）
        if (!widget.live)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: _buildPipProgressBar(),
            ),
          ),

        // 中央播放/暂停按钮（简化版）- 只在暂停时显示
        if (!_isPlaying)
          Positioned.fill(
            child: Center(
              child: GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
            ),
          ),

        // 顶部控制栏（播放/暂停 + 还原按钮）
        // 注意：控制栏背景不拦截触摸事件，让 Android PiP 双击改变窗口大小手势正常工作
        Positioned(
          top: 8,
          right: 8,
          child: AnimatedOpacity(
            opacity: _controlsVisible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 播放/暂停按钮 - 仅按钮区域响应点击
                  GestureDetector(
                    onTap: _togglePlayPause,
                    behavior: HitTestBehavior.deferToChild,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isPlaying ? '暂停' : '播放',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // 分隔线 - 不响应点击，让事件穿透
                  IgnorePointer(
                    child: Container(
                      width: 1,
                      height: 16,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                  ),
                  // 还原按钮 - 仅按钮区域响应点击
                  GestureDetector(
                    onTap: () {
                      // 退出 PiP 模式，恢复全屏
                      widget.onExitPip?.call();
                    },
                    behavior: HitTestBehavior.deferToChild,
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.open_in_full,
                          color: Colors.white,
                          size: 14,
                        ),
                        SizedBox(width: 4),
                        Text(
                          '还原',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // 全屏点击区域（单击切换控制栏显示/隐藏）
        // 注意：不处理双击事件，让 Android PiP 双击改变窗口大小手势正常工作
        Positioned.fill(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _controlsVisible = !_controlsVisible;
              });
              widget.onControlsVisibilityChanged(_controlsVisible);
              if (_controlsVisible) {
                _startHideTimer();
              }
            },
            // 不设置 onDoubleTap，让双击事件穿透到 Android 系统处理 PiP 窗口大小切换
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }

  /// 构建 PiP 模式下的简化进度条
  Widget _buildPipProgressBar() {
    // 直播模式下显示无限循环进度条
    if (widget.live) {
      return Container(
        height: 3,
        color: Colors.transparent,
        child: LinearProgressIndicator(
          backgroundColor: Colors.white.withValues(alpha: 0.3),
          valueColor: AlwaysStoppedAnimation<Color>(Colors.red.shade400),
          minHeight: 3,
        ),
      );
    }

    final position = _position;
    final duration = _duration;

    if (duration == Duration.zero) {
      return const SizedBox.shrink();
    }

    final progress = position.inMilliseconds / duration.inMilliseconds;
    final clampedProgress = progress.clamp(0.0, 1.0);

    return Container(
      height: 3,
      color: Colors.transparent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            children: [
              // 背景
              Container(
                width: double.infinity,
                height: 3,
                color: Colors.white.withValues(alpha: 0.3),
              ),
              // 进度
              Container(
                width: constraints.maxWidth * clampedProgress,
                height: 3,
                color: const Color(0xFF27ae60),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGestureLayer() {
    return Positioned.fill(
      child: Row(
        children: [
          if (_isFullscreen)
            Expanded(
              child: GestureDetector(
                onTap: _toggleControlsVisibility,
                onLongPressStart: _onLongPressStart,
                onLongPressEnd: _onLongPressEnd,
                onLongPressCancel: () {
                  if (_isLongPressing) {
                    _onLongPressEnd(const LongPressEndDetails());
                  }
                },
                onHorizontalDragStart: _onSwipeStart,
                onHorizontalDragUpdate: _onSwipeUpdate,
                onHorizontalDragEnd: _onSwipeEnd,
                onVerticalDragStart: _onBrightnessSwipeStart,
                onVerticalDragUpdate: _onBrightnessSwipeUpdate,
                onVerticalDragEnd: _onBrightnessSwipeEnd,
                behavior: HitTestBehavior.opaque,
              ),
            ),
          Expanded(
            flex: _isFullscreen ? 2 : 1,
            child: GestureDetector(
              onTap: _toggleControlsVisibility,
              onLongPressStart: _onLongPressStart,
              onLongPressEnd: _onLongPressEnd,
              onLongPressCancel: () {
                if (_isLongPressing) {
                  _onLongPressEnd(const LongPressEndDetails());
                }
              },
              onHorizontalDragStart: _onSwipeStart,
              onHorizontalDragUpdate: _onSwipeUpdate,
              onHorizontalDragEnd: _onSwipeEnd,
              behavior: HitTestBehavior.opaque,
            ),
          ),
          if (_isFullscreen)
            Expanded(
              child: GestureDetector(
                onTap: _toggleControlsVisibility,
                onLongPressStart: _onLongPressStart,
                onLongPressEnd: _onLongPressEnd,
                onLongPressCancel: () {
                  if (_isLongPressing) {
                    _onLongPressEnd(const LongPressEndDetails());
                  }
                },
                onHorizontalDragStart: _onSwipeStart,
                onHorizontalDragUpdate: _onSwipeUpdate,
                onHorizontalDragEnd: _onSwipeEnd,
                onVerticalDragStart: _onVolumeSwipeStart,
                onVerticalDragUpdate: _onVolumeSwipeUpdate,
                onVerticalDragEnd: _onVolumeSwipeEnd,
                behavior: HitTestBehavior.opaque,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopGradient() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          child: Container(
            height: _isFullscreen ? 120 : 80,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.6),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentTime() {
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          child: Center(
            child: Text(
              _currentTime,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomGradient() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          child: Container(
            height: _isFullscreen ? 140 : 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.6),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBackButton() {
    return Positioned(
      top: _isFullscreen ? 8 : 4,
      left: _isFullscreen ? 16.0 : 8.0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_controlsVisible || _isLocked,
          child: GestureDetector(
            onTap: () {
              _onUserInteraction();
              if (_isFullscreen) {
                _exitFullscreen();
              } else {
                widget.onBackPressed?.call();
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.arrow_back,
                color: Colors.white,
                size: _isFullscreen ? 24 : 20,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCastButton() {
    return Positioned(
      top: _isFullscreen ? 8 : 4,
      right: _isFullscreen ? 56.0 : 48.0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_controlsVisible || _isLocked,
          child: GestureDetector(
            onTap: () async {
              _onUserInteraction();
              if (!widget.live) {
                await widget.player.pause();
              }
              await _showDLNADialog();
            },
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(8),
              child: Icon(
                Icons.cast,
                color: Colors.white,
                size: _isFullscreen ? 24 : 20,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDownloadButton() {
    // 直播模式不显示下载按钮
    if (widget.live) return const SizedBox.shrink();

    final info = widget.downloadInfo;
    final isDownloading = info.state == VideoDownloadState.downloading;
    final iconSize = _isFullscreen ? 24.0 : 20.0;

    return Positioned(
      top: _isFullscreen ? 8 : 4,
      right: _isFullscreen ? 16.0 : 8.0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_controlsVisible || _isLocked,
          child: GestureDetector(
            onTap: _handleDownloadTap,
            behavior: HitTestBehavior.opaque,
            // 统一使用与投屏按钮相同的 Container + padding 结构
            child: Container(
              padding: const EdgeInsets.all(8),
              child: isDownloading
                  ? _DownloadProgressWithCancel(
                      progress: info.progress,
                      size: iconSize,
                      onCancel: widget.onCancelDownload,
                    )
                  : Icon(
                      _getDownloadIcon(),
                      color: _getDownloadColor(),
                      size: iconSize,
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCenterPlayPause() {
    return Positioned.fill(
      child: Center(
        child: AnimatedOpacity(
          opacity:
              (!_isLocked && (!_isPlaying || _controlsVisible)) ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: _isLocked || (_isPlaying && !_controlsVisible),
            child: GestureDetector(
              onTap: _togglePlayPause,
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: _isFullscreen ? 64 : 48,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    if (widget.live) {
      return const SizedBox.shrink();
    }
    return Positioned(
      bottom: _isFullscreen ? 58.0 : 42.0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_controlsVisible || _isLocked,
          child: Container(
            height: 24,
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: _MobileVideoProgressBar(
              player: widget.player,
              live: widget.live,
              onDragStart: () {
                setState(() => _controlsVisible = true);
                _hideTimer?.cancel();
              },
              onDragEnd: () {
                setState(() => _dragPosition = null);
                _startHideTimer();
              },
              onDragUpdate: () {
                if (!_controlsVisible) {
                  setState(() => _controlsVisible = true);
                }
                _hideTimer?.cancel();
              },
              onPositionUpdate: (duration) {
                setState(() => _dragPosition = duration);
              },
              dragPosition: _dragPosition,
              isSeekingViaSwipe: _isSeekingViaSwipe,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomControls() {
    final position = _dragPosition ?? _position;
    final duration = _duration;
    return Positioned(
      bottom: _isFullscreen ? 4.0 : -6.0,
      left: 0,
      right: 0,
      child: AnimatedOpacity(
        opacity: (_controlsVisible && !_isLocked) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_controlsVisible || _isLocked,
          child: Padding(
            padding: EdgeInsets.only(
              left: _isFullscreen ? 16.0 : 8.0,
              right: _isFullscreen ? 16.0 : 8.0,
              bottom: _isFullscreen ? 8.0 : 8.0,
            ),
            child: Row(
              children: [
                GestureDetector(
                  onTap: _togglePlayPause,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(8, 8, 0, 8),
                    child: Icon(
                      _isPlaying ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: _isFullscreen ? 28 : 24,
                    ),
                  ),
                ),
                if (!widget.isLastEpisode && !widget.live)
                  GestureDetector(
                    onTap: () {
                      _onUserInteraction();
                      widget.onNextEpisode?.call();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.skip_next,
                        color: Colors.white,
                        size: _isFullscreen ? 28 : 24,
                      ),
                    ),
                  ),
                if (!widget.live)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8.0, right: 8.0),
                      child: Text(
                        '${_formatDuration(position)} / ${_formatDuration(duration)}',
                        style:
                            const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                if (widget.live) const Spacer(),
                if (!widget.live)
                  GestureDetector(
                    onTap: () async {
                      _onUserInteraction();
                      await _showSpeedDialog();
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: EdgeInsets.only(right: _isFullscreen ? 22 : 10),
                      child: Icon(
                        Icons.speed,
                        color: Colors.white,
                        size: _isFullscreen ? 22 : 20,
                      ),
                    ),
                  ),
                if (Platform.isAndroid)
                  GestureDetector(
                    onTap: () async {
                      _onUserInteraction();
                      try {
                        await _enterPipMode();
                      } catch (e) {
                        debugPrint('Failed to enter PiP mode: $e');
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.picture_in_picture_alt,
                        color: Colors.white,
                        size: _isFullscreen ? 22 : 20,
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: () {
                    _onUserInteraction();
                    if (_isFullscreen) {
                      _exitFullscreen();
                    } else {
                      _enterFullscreen();
                    }
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: EdgeInsets.only(
                      left: _isFullscreen ? 12 : 5,
                      right: _isFullscreen ? 12 : 8,
                    ),
                    child: Icon(
                      _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                      color: Colors.white,
                      size: _isFullscreen ? 28 : 24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLongPressIndicator() {
    return const Positioned(
      top: 10,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '2x',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: 6),
          Icon(Icons.fast_forward, color: Colors.white, size: 32),
        ],
      ),
    );
  }

  Widget _buildBrightnessIndicator() {
    return Positioned(
      left: 16.0,
      top: 0,
      bottom: 0,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _currentBrightness < 0.5
                    ? Icons.brightness_low
                    : Icons.brightness_high,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                width: 4,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: _currentBrightness,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${(_currentBrightness * 100).round()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _takeScreenshot() async {
    _onUserInteraction();

    if (_isCapturingScreenshot) return;

    setState(() {
      _isCapturingScreenshot = true;
    });

    try {
      // 使用视频标题或默认名称
      final fileName = widget.videoTitle != null
          ? '${widget.videoTitle}_screenshot.png'
          : null;

      final path = await _screenshotService.captureScreenshot(
        player: widget.player,
        fileName: fileName,
      );

      if (mounted) {
        if (path != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('截图已保存: $path'),
              duration: const Duration(seconds: 2),
              backgroundColor: Colors.green.withValues(alpha: 0.8),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('截图失败'),
              duration: Duration(seconds: 2),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturingScreenshot = false;
        });
      }
    }
  }

  Widget _buildRightOverlay() {
    if (_showVolumeIndicator && !_isLocked) {
      return Positioned(
        right: 16.0,
        top: 0,
        bottom: 0,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _currentVolume == 0
                      ? Icons.volume_off
                      : _currentVolume < 0.5
                          ? Icons.volume_down
                          : Icons.volume_up,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 100,
                  width: 4,
                  child: Stack(
                    children: [
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: _currentVolume,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${(_currentVolume * 100).round()}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Positioned(
      right: 16.0,
      top: 0,
      bottom: 0,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 截图按钮
            AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: GestureDetector(
                  onTap: _isCapturingScreenshot ? null : _takeScreenshot,
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: _isCapturingScreenshot
                        ? SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: 24,
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 屏幕锁定按钮
            AnimatedOpacity(
              opacity: _controlsVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: IgnorePointer(
                ignoring: !_controlsVisible,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _isLocked = !_isLocked;
                      _controlsVisible = true;
                    });
                    _startHideTimer();
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Icon(
                      _isLocked ? Icons.lock : Icons.lock_open,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileVideoProgressBar extends StatefulWidget {
  final Player player;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final VoidCallback? onDragUpdate;
  final void Function(Duration)? onPositionUpdate;
  final Duration? dragPosition;
  final bool isSeekingViaSwipe;
  final bool live;

  const _MobileVideoProgressBar({
    required this.player,
    this.onDragStart,
    this.onDragEnd,
    this.onDragUpdate,
    this.onPositionUpdate,
    this.dragPosition,
    this.isSeekingViaSwipe = false,
    this.live = false,
  });

  @override
  State<_MobileVideoProgressBar> createState() =>
      _MobileVideoProgressBarState();
}

class _MobileVideoProgressBarState extends State<_MobileVideoProgressBar> {
  bool _isDragging = false;
  double _dragValue = 0.0;
  bool _isSeeking = false;
  StreamSubscription<Duration>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _positionSubscription = widget.player.stream.position.listen((_) {
      if (mounted && !_isDragging && !_isSeeking) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = widget.player.state.duration;
    final position = widget.dragPosition ?? widget.player.state.position;

    double value = 0.0;
    if (duration.inMilliseconds > 0) {
      if (widget.live) {
        value = 1.0;
      } else {
        value = position.inMilliseconds / duration.inMilliseconds;
      }
    }

    if (_isDragging && !widget.live) {
      value = _dragValue;
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: widget.live
          ? null
          : (details) {
              _isDragging = true;
              widget.onDragStart?.call();
              _updateDrag(details.localPosition.dx, context);
            },
      onHorizontalDragUpdate: widget.live
          ? null
          : (details) {
              if (_isDragging) {
                widget.onDragUpdate?.call();
                _updateDrag(details.localPosition.dx, context);
              }
            },
      onHorizontalDragEnd: widget.live
          ? null
          : (details) async {
              if (_isDragging) {
                final seekPosition = Duration(
                  milliseconds: (_dragValue * duration.inMilliseconds).round(),
                );

                setState(() {
                  _isDragging = false;
                  _isSeeking = true;
                });

                await widget.player.seek(seekPosition);
                await Future<void>.delayed(const Duration(milliseconds: 100));

                if (mounted) {
                  setState(() {
                    _isSeeking = false;
                  });
                }

                widget.onDragEnd?.call();
              }
            },
      onTapDown: widget.live
          ? null
          : (details) async {
              widget.onDragStart?.call();
              _updateDrag(details.localPosition.dx, context);
              final seekPosition = Duration(
                milliseconds: (_dragValue * duration.inMilliseconds).round(),
              );

              setState(() {
                _isSeeking = true;
              });

              await widget.player.seek(seekPosition);
              await Future<void>.delayed(const Duration(milliseconds: 100));

              if (mounted) {
                setState(() {
                  _isSeeking = false;
                });
              }

              widget.onDragEnd?.call();
            },
      child: Container(
        height: 24,
        color: Colors.transparent,
        child: Center(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final progressWidth = constraints.maxWidth;
              final progressValue = value.clamp(0.0, 1.0);
              final thumbPosition = (progressValue * progressWidth)
                  .clamp(8.0, progressWidth - 8.0);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 9,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 9,
                    child: Container(
                      width: progressValue * progressWidth,
                      height: 6,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: Colors.red,
                      ),
                    ),
                  ),
                  if (!widget.live)
                    Positioned(
                      left: thumbPosition - 8,
                      top: 4,
                      child: AnimatedScale(
                        scale: widget.isSeekingViaSwipe ? 1.25 : 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.red,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _updateDrag(double dx, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final width = box.size.width;
    final value = (dx / width).clamp(0.0, 1.0);
    setState(() => _dragValue = value);
    if (!widget.live) {
      final duration = widget.player.state.duration;
      final position =
          Duration(milliseconds: (value * duration.inMilliseconds).round());
      widget.onPositionUpdate?.call(position);
    }
  }
}

/// 下载进度指示器，悬停/按压时显示取消图标
class _DownloadProgressWithCancel extends StatefulWidget {
  final double progress;
  final double size;
  final Future<void> Function() onCancel;

  const _DownloadProgressWithCancel({
    required this.progress,
    required this.size,
    required this.onCancel,
  });

  @override
  State<_DownloadProgressWithCancel> createState() =>
      _DownloadProgressWithCancelState();
}

class _DownloadProgressWithCancelState
    extends State<_DownloadProgressWithCancel> {
  bool _isPressed = false;

  Future<void> _handleTap() async {
    if (_isPressed) {
      // 点击 X 图标时取消下载
      await widget.onCancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    // 移动端使用 GestureDetector 检测按压状态
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) async {
        await _handleTap();
        if (mounted) {
          setState(() => _isPressed = false);
        }
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _isPressed
            ? Icon(
                Icons.close,
                color: Colors.orange,
                size: widget.size,
              )
            : CircularProgressIndicator(
                value: widget.progress > 0 ? widget.progress : null,
                strokeWidth: 2,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Colors.orange,
                ),
              ),
      ),
    );
  }
}
