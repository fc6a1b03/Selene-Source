import 'dart:async';
import 'dart:io';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:selene/models/video_download_info.dart';
import 'package:selene/services/screenshot_service.dart';
import 'package:selene/widgets/dlna_device_dialog.dart';

// 带 hover 效果的按钮组件
class HoverButton extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final EdgeInsets padding;

  const HoverButton({
    super.key,
    required this.child,
    required this.onTap,
    this.padding = const EdgeInsets.all(8),
  });

  @override
  State<HoverButton> createState() => _HoverButtonState();
}

class _HoverButtonState extends State<HoverButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: widget.padding,
          decoration: _isHovering
              ? BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.withValues(alpha: 0.5),
                )
              : null,
          child: widget.child,
        ),
      ),
    );
  }
}

class PCPlayerControls extends StatefulWidget {
  final VideoState state;
  final Player player;
  final VoidCallback? onBackPressed;
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
  // ignore: avoid_positional_boolean_parameters
  final void Function(bool isFullscreen)? onDLNAButtonPressed;
  // ignore: avoid_positional_boolean_parameters
  final void Function(bool isWebFullscreen)? onWebFullscreenChanged;
  final void Function(VoidCallback)? onExitWebFullscreenCallbackReady;
  final VoidCallback? onExitFullScreen;
  final bool live;
  final ValueNotifier<double> playbackSpeedListenable;
  final Future<void> Function(double speed) onSetSpeed;

  // 下载相关参数
  final VideoDownloadInfo downloadInfo;
  final Future<void> Function({String? fileName}) onStartDownload;
  final Future<void> Function() onCancelDownload;
  final Future<String?> Function() onSaveAs;

  const PCPlayerControls({
    super.key,
    required this.state,
    required this.player,
    this.onBackPressed,
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
    this.onDLNAButtonPressed,
    this.onWebFullscreenChanged,
    this.onExitWebFullscreenCallbackReady,
    this.onExitFullScreen,
    this.live = false,
    required this.playbackSpeedListenable,
    required this.onSetSpeed,
    // 下载相关
    this.downloadInfo = const VideoDownloadInfo(),
    required this.onStartDownload,
    required this.onCancelDownload,
    required this.onSaveAs,
  });

  @override
  State<PCPlayerControls> createState() => _PCPlayerControlsState();
}

class _PCPlayerControlsState extends State<PCPlayerControls> {
  Timer? _hideTimer;
  bool _controlsVisible = true;
  Size? _screenSize;
  Duration? _dragPosition;
  bool _isSeekingViaSwipe = false;
  double _swipeStartX = 0;
  Duration _swipeStartPosition = Duration.zero;
  StreamSubscription<dynamic>? _playingSubscription;
  StreamSubscription<dynamic>? _positionSubscription;
  bool _isFullscreen = false;
  bool _isWebFullscreen = false;
  bool _showSpeedMenu = false;
  final GlobalKey _speedButtonKey = GlobalKey();
  bool _isHoveringSpeedButton = false;
  bool _isHoveringSpeedMenu = false;
  bool _showVolumeMenu = false;
  final GlobalKey _volumeButtonKey = GlobalKey();
  bool _isHoveringVolumeButton = false;
  bool _isHoveringVolumeMenu = false;
  double _volumeBeforeMute = 1.0;
  Timer? _volumeMenuHideTimer;
  final FocusNode _focusNode = FocusNode();

  // 截图服务
  final ScreenshotService _screenshotService = ScreenshotService();
  bool _isCapturingScreenshot = false;

  @override
  void initState() {
    super.initState();
    _setupPlayerListeners();
    widget.onExitWebFullscreenCallbackReady?.call(exitWebFullscreen);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _forceStartHideTimer();
      _focusNode.requestFocus();
    });
  }

  // 用于节流位置更新
  DateTime? _lastPositionUpdate;
  static const _positionUpdateInterval = Duration(milliseconds: 500);

  void _setupPlayerListeners() {
    _playingSubscription = widget.player.stream.playing.listen((playing) {
      if (!mounted) return;

      if (playing) {
        if (_controlsVisible) {
          _startHideTimer();
        }
      } else {
        _hideTimer?.cancel();
        if (!_controlsVisible) {
          setState(() {
            _controlsVisible = true;
          });
        }
      }
    });

    _positionSubscription = widget.player.stream.position.listen((_) {
      if (mounted && _controlsVisible && !_isSeekingViaSwipe) {
        // 节流：每 500ms 最多更新一次 UI
        final now = DateTime.now();
        if (_lastPositionUpdate == null ||
            now.difference(_lastPositionUpdate!) > _positionUpdateInterval) {
          _lastPositionUpdate = now;
          setState(() {});
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _screenSize = MediaQuery.of(context).size;
  }

  @override
  void didUpdateWidget(PCPlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    try {
      final actualFullscreen = widget.state.isFullscreen();
      if (_isFullscreen != actualFullscreen) {
        if (_isFullscreen && !actualFullscreen) {
          widget.onExitFullScreen?.call();
        }
        setState(() {
          _isFullscreen = actualFullscreen;
        });
      }
    } catch (e) {
      // 保持当前状态
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _volumeMenuHideTimer?.cancel();
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _focusNode.dispose();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_showSpeedMenu ||
        _isHoveringSpeedButton ||
        _isHoveringSpeedMenu ||
        _showVolumeMenu ||
        _isHoveringVolumeButton ||
        _isHoveringVolumeMenu) {
      return;
    }
    if (widget.player.state.playing) {
      _hideTimer = Timer(const Duration(seconds: 3), () {
        if (!mounted) return;
        setState(() {
          _controlsVisible = false;
        });
      });
    }
  }

  void _forceStartHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _controlsVisible = false;
      });
    });
  }

  void _onUserInteraction() {
    setState(() {
      _controlsVisible = true;
    });
    _startHideTimer();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _showVolumeMenuTemporarily() {
    _volumeMenuHideTimer?.cancel();
    setState(() {
      _showVolumeMenu = true;
    });
    _volumeMenuHideTimer = Timer(const Duration(seconds: 1), () {
      if (mounted && !_isHoveringVolumeButton && !_isHoveringVolumeMenu) {
        setState(() {
          _showVolumeMenu = false;
        });
      }
    });
  }

  void _onBlankAreaTap() {
    if (widget.live) {
      return;
    }
    if (widget.player.state.playing) {
      widget.player.pause();
      widget.onPause?.call();
    } else {
      widget.player.play();
    }
    setState(() {});
  }

  void _onBlankAreaDoubleTap() {
    if (_isWebFullscreen && !_isFullscreen) {
      _toggleWebFullscreen();
    }
    _toggleFullscreen();
  }

  void _onSeekStart() {
    if (!mounted) return;
    setState(() {
      _controlsVisible = true;
      _dragPosition = null;
    });
    _hideTimer?.cancel();
    _startHideTimer();
  }

  void _onSeekEnd() {
    setState(() {
      _dragPosition = null;
    });
    _startHideTimer();
  }

  void _onSwipeStart(DragStartDetails details) {
    if (!mounted || widget.live) return;

    setState(() {
      _isSeekingViaSwipe = true;
      _swipeStartX = details.globalPosition.dx;
      _swipeStartPosition = widget.player.state.position;
      _controlsVisible = true;
    });

    _hideTimer?.cancel();
  }

  void _onSwipeUpdate(DragUpdateDetails details) {
    if (!mounted || !_isSeekingViaSwipe || _screenSize == null || widget.live) {
      return;
    }

    final screenWidth = _screenSize!.width;
    final swipeDistance = details.globalPosition.dx - _swipeStartX;
    final swipeRatio = swipeDistance / (screenWidth * 0.5);
    final duration = widget.player.state.duration;

    final targetPosition = _swipeStartPosition +
        Duration(
          milliseconds: (duration.inMilliseconds * swipeRatio * 0.1).round(),
        );
    final clampedPosition = Duration(
      milliseconds:
          targetPosition.inMilliseconds.clamp(0, duration.inMilliseconds),
    );

    setState(() {
      _dragPosition = clampedPosition;
    });
  }

  void _onSwipeEnd(DragEndDetails details) {
    if (!mounted || !_isSeekingViaSwipe || widget.live) return;

    if (_dragPosition != null) {
      widget.player.seek(_dragPosition!);
    }

    setState(() {
      _isSeekingViaSwipe = false;
      _dragPosition = null;
    });

    _startHideTimer();
  }

  void _toggleFullscreen() {
    if (_isFullscreen) {
      // 退出全屏
      if (Platform.isWindows) {
        // Windows: 使用 bitsdojo_window 恢复窗口
        appWindow.maximizeOrRestore();
      }
      widget.state.exitFullscreen();
    } else {
      // 进入全屏
      if (Platform.isWindows) {
        // Windows: 使用 bitsdojo_window 实现真正的全屏（覆盖任务栏）
        appWindow.maximize();
      }
      widget.state.enterFullscreen();
    }
  }

  void _toggleWebFullscreen() {
    final wasWebFullscreen = _isWebFullscreen;
    setState(() {
      _isWebFullscreen = !_isWebFullscreen;
    });
    widget.onWebFullscreenChanged?.call(_isWebFullscreen);
    if (wasWebFullscreen && !_isWebFullscreen) {
      widget.onExitFullScreen?.call();
    }
    _onUserInteraction();
  }

  void exitWebFullscreen() {
    if (_isWebFullscreen) {
      setState(() {
        _isWebFullscreen = false;
      });
      widget.onWebFullscreenChanged?.call(false);
      widget.onExitFullScreen?.call();
      _onUserInteraction();
    }
  }

  Future<void> _showDLNADialog() async {
    if (widget.player.state.playing) {
      if (!widget.live) {
        await widget.player.pause();
      }
      widget.onPause?.call();
    }

    if (_isFullscreen) {
      widget.onDLNAButtonPressed?.call(true);
      _toggleFullscreen();
    } else {
      await _showDLNADialogInternal();
    }
  }

  Future<void> _showDLNADialogInternal() async {
    final resumePos = widget.player.state.position;

    if (mounted) {
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
  }

  // ===== 截图功能 =====

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

  // ===== 下载按钮处理 =====

  Future<void> _handleDownloadTap() async {
    _onUserInteraction();

    final info = widget.downloadInfo;

    switch (info.state) {
      case VideoDownloadState.idle:
      case VideoDownloadState.failed:
        await widget.onStartDownload();
        break;
      case VideoDownloadState.downloading:
        await widget.onCancelDownload();
        break;
      case VideoDownloadState.paused:
        await widget.onCancelDownload();
        break;
      case VideoDownloadState.completed:
        try {
          final path = await widget.onSaveAs();
          if (path != null && mounted) {
            // 移动端显示保存成功提示
            if (Platform.isAndroid || Platform.isIOS) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('视频已保存到相册'),
                  duration: Duration(seconds: 2),
                ),
              );
            }
          }
        } catch (e) {
          if (mounted && (Platform.isAndroid || Platform.isIOS)) {
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

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (_isFullscreen) {
          _toggleFullscreen();
          return KeyEventResult.handled;
        }
      } else if (event.logicalKey == LogicalKeyboardKey.space) {
        _onUserInteraction();
        if (widget.player.state.playing) {
          widget.player.pause();
          widget.onPause?.call();
        } else {
          widget.player.play();
        }
        setState(() {});
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
        if (_isWebFullscreen) {
          _toggleWebFullscreen();
          return KeyEventResult.handled;
        }
        _toggleFullscreen();
        return KeyEventResult.handled;
      } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        return _handleSeek(-10);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        return _handleSeek(10);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        return _handleVolumeChange(10);
      } else if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        return _handleVolumeChange(-10);
      }
    }
    return KeyEventResult.ignored;
  }

  /// 处理进度调整（带安全边界检查）
  KeyEventResult _handleSeek(int seconds) {
    try {
      final currentPosition = widget.player.state.position;
      final duration = widget.player.state.duration;

      // 检查有效性
      if (duration == Duration.zero || duration.inMilliseconds < 0) {
        return KeyEventResult.ignored;
      }

      final newPosition = currentPosition + Duration(seconds: seconds);
      final clampedPosition = Duration(
        milliseconds: newPosition.inMilliseconds.clamp(
          0,
          duration.inMilliseconds,
        ),
      );
      widget.player.seek(clampedPosition);
      _onUserInteraction();
      return KeyEventResult.handled;
    } catch (e) {
      debugPrint('Seek error: $e');
      return KeyEventResult.ignored;
    }
  }

  /// 处理音量调整（带安全边界检查）
  KeyEventResult _handleVolumeChange(double delta) {
    try {
      final currentVolume = widget.player.state.volume;
      final newVolume = (currentVolume + delta).clamp(0.0, 100.0);
      widget.player.setVolume(newVolume);
      _onUserInteraction();
      _showVolumeMenuTemporarily();
      return KeyEventResult.handled;
    } catch (e) {
      debugPrint('Volume change error: $e');
      return KeyEventResult.ignored;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoadingVideo) {
      return ColoredBox(
        color: Colors.black.withValues(alpha: 0.7),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 3,
              ),
              SizedBox(height: 16),
              Text(
                '加载中...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final effectiveFullscreen = _isWebFullscreen || _isFullscreen;
    final info = widget.downloadInfo;
    final isDownloading = info.state == VideoDownloadState.downloading;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKeyEvent,
      child: MouseRegion(
        cursor: (effectiveFullscreen && !_controlsVisible)
            ? SystemMouseCursors.none
            : SystemMouseCursors.basic,
        onEnter: (_) {
          if (!_controlsVisible) {
            setState(() {
              _controlsVisible = true;
            });
          }
          _startHideTimer();
        },
        onHover: (_) {
          if (!_controlsVisible) {
            setState(() {
              _controlsVisible = true;
            });
          }
          _startHideTimer();
        },
        onExit: (_) {
          _hideTimer?.cancel();
          if (_controlsVisible &&
              !_showSpeedMenu &&
              !_isHoveringSpeedButton &&
              !_isHoveringSpeedMenu &&
              !_showVolumeMenu &&
              !_isHoveringVolumeButton &&
              !_isHoveringVolumeMenu) {
            setState(() {
              _controlsVisible = false;
            });
          }
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onHorizontalDragStart: _onSwipeStart,
                onHorizontalDragUpdate: _onSwipeUpdate,
                onHorizontalDragEnd: _onSwipeEnd,
                onTap: _onBlankAreaTap,
                onDoubleTap: _onBlankAreaDoubleTap,
                behavior: HitTestBehavior.opaque,
                child: Container(
                  color: Colors.transparent,
                ),
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  child: Container(
                    height: effectiveFullscreen ? 120 : 80,
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
            ),
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  child: Container(
                    height: effectiveFullscreen ? 140 : 100,
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
            ),
            Positioned(
              top: effectiveFullscreen ? 8 : 4,
              left: effectiveFullscreen ? 16.0 : 8.0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: HoverButton(
                    onTap: () async {
                      _onUserInteraction();
                      if (_isFullscreen) {
                        _toggleFullscreen();
                      } else if (_isWebFullscreen) {
                        _toggleWebFullscreen();
                      } else {
                        widget.onBackPressed?.call();
                      }
                    },
                    child: Icon(
                      Icons.arrow_back,
                      color: Colors.white,
                      size: effectiveFullscreen ? 24 : 20,
                    ),
                  ),
                ),
              ),
            ),
            // 顶部投屏按钮（非直播模式下在最左侧，直播模式下在中间）
            Positioned(
              top: effectiveFullscreen ? 8 : 4,
              right: effectiveFullscreen
                  ? (widget.live ? 56.0 : 96.0)
                  : (widget.live ? 48.0 : 88.0),
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: HoverButton(
                    onTap: () async {
                      _onUserInteraction();
                      await _showDLNADialog();
                    },
                    child: Icon(
                      Icons.cast,
                      color: Colors.white,
                      size: effectiveFullscreen ? 24 : 20,
                    ),
                  ),
                ),
              ),
            ),
            // 顶部截图按钮（非直播模式下在投屏和下载之间，直播模式下在最右侧）
            Positioned(
              top: effectiveFullscreen ? 8 : 4,
              right: effectiveFullscreen
                  ? (widget.live ? 16.0 : 56.0)
                  : (widget.live ? 8.0 : 48.0),
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_controlsVisible || _isCapturingScreenshot,
                  child: HoverButton(
                    onTap: _takeScreenshot,
                    child: _isCapturingScreenshot
                        ? SizedBox(
                            width: effectiveFullscreen ? 24 : 20,
                            height: effectiveFullscreen ? 24 : 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          )
                        : Icon(
                            Icons.camera_alt,
                            color: Colors.white,
                            size: effectiveFullscreen ? 24 : 20,
                          ),
                  ),
                ),
              ),
            ),
            // 顶部下载按钮（仅非直播模式）
            if (!widget.live)
              Positioned(
                top: effectiveFullscreen ? 8 : 4,
                right: effectiveFullscreen ? 16.0 : 8.0,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: HoverButton(
                      onTap: _handleDownloadTap,
                      child: isDownloading
                          ? _DownloadProgressWithCancel(
                              progress: info.progress,
                              size: effectiveFullscreen ? 24 : 20,
                            )
                          : Icon(
                              _getDownloadIcon(),
                              color: _getDownloadColor(),
                              size: effectiveFullscreen ? 24 : 20,
                            ),
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: Center(
                child: AnimatedOpacity(
                  opacity: (!widget.player.state.playing || _controlsVisible)
                      ? 1.0
                      : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: widget.player.state.playing && !_controlsVisible,
                    child: _CenterPlayButton(
                      isPlaying: widget.player.state.playing,
                      isFullscreen: effectiveFullscreen,
                      onTap: () {
                        _onUserInteraction();
                        if (widget.player.state.playing) {
                          widget.player.pause();
                          widget.onPause?.call();
                        } else {
                          widget.player.play();
                        }
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (!widget.live)
              Positioned(
                bottom: effectiveFullscreen ? 58.0 : 42.0,
                left: 0,
                right: 0,
                child: AnimatedOpacity(
                  opacity: _controlsVisible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    ignoring: !_controlsVisible,
                    child: Container(
                      height: 24,
                      margin: const EdgeInsets.symmetric(horizontal: 16),
                      child: CustomVideoProgressBar(
                        player: widget.player,
                        onDragStart: _onSeekStart,
                        onDragEnd: _onSeekEnd,
                        onDragUpdate: () {
                          if (!_controlsVisible) {
                            setState(() {
                              _controlsVisible = true;
                            });
                          }
                          _hideTimer?.cancel();
                        },
                        onPositionUpdate: (duration) {
                          setState(() {
                            _dragPosition = duration;
                          });
                        },
                        dragPosition: _dragPosition,
                        isSeekingViaSwipe: _isSeekingViaSwipe,
                        live: widget.live,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              bottom: effectiveFullscreen ? 4.0 : -6.0,
              left: 0,
              right: 0,
              child: AnimatedOpacity(
                opacity: _controlsVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: GestureDetector(
                    onTap: () {},
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: effectiveFullscreen ? 16.0 : 8.0,
                        right: effectiveFullscreen ? 16.0 : 8.0,
                        top: effectiveFullscreen ? 0.0 : 0.0,
                        bottom: effectiveFullscreen ? 8.0 : 8.0,
                      ),
                      child: Row(
                        children: [
                          HoverButton(
                            onTap: () {
                              _onUserInteraction();
                              if (widget.player.state.playing) {
                                widget.player.pause();
                                widget.onPause?.call();
                              } else {
                                widget.player.play();
                              }
                            },
                            child: Icon(
                              widget.player.state.playing
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                              size: effectiveFullscreen ? 28 : 24,
                            ),
                          ),
                          if (!widget.isLastEpisode && !widget.live)
                            Transform.translate(
                              offset: const Offset(-8, 0),
                              child: HoverButton(
                                onTap: () {
                                  _onUserInteraction();
                                  widget.onNextEpisode?.call();
                                },
                                child: Icon(
                                  Icons.skip_next,
                                  color: Colors.white,
                                  size: effectiveFullscreen ? 28 : 24,
                                ),
                              ),
                            ),
                          Transform.translate(
                            offset: const Offset(-8, 0),
                            child: MouseRegion(
                              key: _volumeButtonKey,
                              cursor: SystemMouseCursors.click,
                              onEnter: (_) {
                                setState(() {
                                  _isHoveringVolumeButton = true;
                                  _showVolumeMenu = true;
                                  _controlsVisible = true;
                                });
                                _hideTimer?.cancel();
                              },
                              onExit: (_) {
                                setState(() {
                                  _isHoveringVolumeButton = false;
                                });
                                Future<void>.delayed(
                                    const Duration(milliseconds: 100), () {
                                  if (!mounted) return;
                                  if (mounted &&
                                      !_isHoveringVolumeButton &&
                                      !_isHoveringVolumeMenu) {
                                    setState(() {
                                      _showVolumeMenu = false;
                                    });
                                    _startHideTimer();
                                  }
                                });
                              },
                              child: GestureDetector(
                                onTap: () {
                                  _onUserInteraction();
                                  final currentVolume =
                                      widget.player.state.volume;
                                  if (currentVolume > 0) {
                                    _volumeBeforeMute = currentVolume;
                                    widget.player.setVolume(0);
                                  } else {
                                    widget.player.setVolume(_volumeBeforeMute);
                                  }
                                  setState(() {});
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: _isHoveringVolumeButton
                                      ? BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Colors.grey
                                              .withValues(alpha: 0.5),
                                        )
                                      : null,
                                  child: Icon(
                                    _getVolumeIcon(widget.player.state.volume),
                                    color: Colors.white,
                                    size: effectiveFullscreen ? 22 : 20,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (!widget.live)
                            Expanded(
                              child: _buildPositionIndicator(),
                            ),
                          if (!widget.live)
                            MouseRegion(
                              key: _speedButtonKey,
                              cursor: SystemMouseCursors.click,
                              onEnter: (_) {
                                setState(() {
                                  _isHoveringSpeedButton = true;
                                  _showSpeedMenu = true;
                                  _controlsVisible = true;
                                });
                                _hideTimer?.cancel();
                              },
                              onExit: (_) {
                                setState(() {
                                  _isHoveringSpeedButton = false;
                                });
                                Future<void>.delayed(
                                    const Duration(milliseconds: 100), () {
                                  if (!mounted) return;
                                  if (mounted &&
                                      !_isHoveringSpeedButton &&
                                      !_isHoveringSpeedMenu) {
                                    setState(() {
                                      _showSpeedMenu = false;
                                    });
                                    _startHideTimer();
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: _isHoveringSpeedButton
                                    ? BoxDecoration(
                                        shape: BoxShape.circle,
                                        color:
                                            Colors.grey.withValues(alpha: 0.5),
                                      )
                                    : null,
                                child: Icon(
                                  Icons.speed,
                                  color: Colors.white,
                                  size: effectiveFullscreen ? 22 : 20,
                                ),
                              ),
                            ),
                          if (widget.live) const Spacer(),
                          if (!_isFullscreen)
                            HoverButton(
                              onTap: () {
                                _onUserInteraction();
                                _toggleWebFullscreen();
                              },
                              child: Icon(
                                _isWebFullscreen
                                    ? Icons.fullscreen_exit
                                    : Icons.fit_screen,
                                color: Colors.white,
                                size: effectiveFullscreen ? 28 : 24,
                              ),
                            ),
                          if (!_isWebFullscreen)
                            HoverButton(
                              onTap: () {
                                _onUserInteraction();
                                _toggleFullscreen();
                              },
                              child: Icon(
                                _isFullscreen
                                    ? Icons.fullscreen_exit
                                    : Icons.fullscreen,
                                color: Colors.white,
                                size: effectiveFullscreen ? 28 : 24,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_showSpeedMenu) _buildSpeedMenu(),
            if (_showVolumeMenu) _buildVolumeMenu(),
          ],
        ),
      ),
    );
  }

  IconData _getVolumeIcon(double volume) {
    if (volume == 0) {
      return Icons.volume_off;
    } else if (volume < 50) {
      return Icons.volume_down;
    } else {
      return Icons.volume_up;
    }
  }

  Widget _buildSpeedMenu() {
    final speeds = [0.5, 0.75, 1.0, 1.5, 2.0];
    final currentSpeed = widget.player.state.rate;

    final RenderBox? renderBox =
        _speedButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return const SizedBox.shrink();

    final buttonPosition = renderBox.localToGlobal(Offset.zero);
    final buttonSize = renderBox.size;

    final effectiveFullscreen = _isWebFullscreen || _isFullscreen;
    final menuWidth = effectiveFullscreen ? 120.0 : 90.0;
    final itemHeight = effectiveFullscreen ? 48.0 : 36.0;
    final menuHeight = speeds.length * itemHeight;
    final menuLeft =
        buttonPosition.dx + (buttonSize.width / 2) - (menuWidth / 2);
    final menuTop = buttonPosition.dy - menuHeight - (_isFullscreen ? 2 : 36);

    return Positioned(
      left: menuLeft,
      top: menuTop,
      child: MouseRegion(
        onEnter: (_) {
          setState(() {
            _isHoveringSpeedMenu = true;
          });
          _hideTimer?.cancel();
        },
        onExit: (_) {
          setState(() {
            _isHoveringSpeedMenu = false;
          });
          Future<void>.delayed(const Duration(milliseconds: 100), () {
            if (!mounted) return;
            if (mounted && !_isHoveringSpeedButton && !_isHoveringSpeedMenu) {
              setState(() {
                _showSpeedMenu = false;
              });
              _startHideTimer();
            }
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: menuWidth,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(effectiveFullscreen ? 8 : 6),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(effectiveFullscreen ? 8 : 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: speeds.map((speed) {
                  final isSelected = (speed - currentSpeed).abs() < 0.01;
                  return _SpeedMenuItem(
                    speed: speed,
                    isSelected: isSelected,
                    isFullscreen: effectiveFullscreen,
                    onTap: () {
                      widget.onSetSpeed(speed);
                      setState(() {
                        _showSpeedMenu = false;
                        _isHoveringSpeedMenu = false;
                      });
                      _startHideTimer();
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVolumeMenu() {
    final currentVolume = widget.player.state.volume;

    final RenderBox? renderBox =
        _volumeButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return const SizedBox.shrink();

    final buttonPosition = renderBox.localToGlobal(Offset.zero);
    final buttonSize = renderBox.size;

    final effectiveFullscreen = _isWebFullscreen || _isFullscreen;
    final menuWidth = effectiveFullscreen ? 42.0 : 36.0;
    final menuHeight = effectiveFullscreen ? 200.0 : 150.0;

    final menuLeft =
        buttonPosition.dx + (buttonSize.width / 2) - (menuWidth / 2);
    final menuTop = buttonPosition.dy - menuHeight - (_isFullscreen ? 2 : 36);

    return Positioned(
      left: menuLeft,
      top: menuTop,
      child: MouseRegion(
        onEnter: (_) {
          if (!mounted) return;
          setState(() {
            _isHoveringVolumeMenu = true;
          });
          _hideTimer?.cancel();
        },
        onExit: (_) {
          if (!mounted) return;
          setState(() {
            _isHoveringVolumeMenu = false;
          });
          Future<void>.delayed(const Duration(milliseconds: 100), () {
            if (!mounted) return;
            if (!_isHoveringVolumeButton && !_isHoveringVolumeMenu) {
              setState(() {
                _showVolumeMenu = false;
              });
              _startHideTimer();
            }
          });
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: menuWidth,
            height: menuHeight,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(effectiveFullscreen ? 8 : 6),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(effectiveFullscreen ? 8 : 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text(
                      '${currentVolume.round()}',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: effectiveFullscreen ? 14 : 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8.0,
                        horizontal: 12.0,
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onVerticalDragStart: (details) {
                              final localY = details.localPosition.dy;
                              final volume =
                                  ((1 - (localY / constraints.maxHeight)) * 100)
                                      .clamp(0.0, 100.0);
                              widget.player.setVolume(volume);
                              if (mounted) setState(() {});
                            },
                            onVerticalDragUpdate: (details) {
                              final localY = details.localPosition.dy;
                              final volume =
                                  ((1 - (localY / constraints.maxHeight)) * 100)
                                      .clamp(0.0, 100.0);
                              widget.player.setVolume(volume);
                              if (mounted) setState(() {});
                            },
                            onTapDown: (details) {
                              final localY = details.localPosition.dy;
                              final volume =
                                  ((1 - (localY / constraints.maxHeight)) * 100)
                                      .clamp(0.0, 100.0);
                              widget.player.setVolume(volume);
                              if (mounted) setState(() {});
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: effectiveFullscreen ? 5 : 4,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(
                                      effectiveFullscreen ? 2.5 : 2,
                                    ),
                                    color: Colors.white.withValues(alpha: 0.3),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: FractionallySizedBox(
                                    heightFactor: currentVolume / 100,
                                    child: Container(
                                      width: effectiveFullscreen ? 5 : 4,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(
                                          effectiveFullscreen ? 2.5 : 2,
                                        ),
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPositionIndicator() {
    final position = _dragPosition ?? widget.player.state.position;
    final duration = widget.player.state.duration;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Text(
        '${_formatDuration(position)} / ${_formatDuration(duration)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
      ),
    );
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
}

class _SpeedMenuItem extends StatefulWidget {
  final double speed;
  final bool isSelected;
  final bool isFullscreen;
  final VoidCallback onTap;

  const _SpeedMenuItem({
    required this.speed,
    required this.isSelected,
    required this.isFullscreen,
    required this.onTap,
  });

  @override
  State<_SpeedMenuItem> createState() => _SpeedMenuItemState();
}

class _SpeedMenuItemState extends State<_SpeedMenuItem> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          height: widget.isFullscreen ? 48.0 : 36.0,
          color: _isHovering
              ? Colors.white.withValues(alpha: 0.1)
              : Colors.transparent,
          alignment: Alignment.center,
          child: Text(
            '${widget.speed}x',
            style: TextStyle(
              color: widget.isSelected ? Colors.red : Colors.white,
              fontSize: widget.isFullscreen ? 14 : 12,
              fontWeight:
                  widget.isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}

class CustomVideoProgressBar extends StatefulWidget {
  final Player player;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;
  final VoidCallback? onDragUpdate;
  final void Function(Duration)? onPositionUpdate;
  final Duration? dragPosition;
  final bool isSeekingViaSwipe;
  final bool live;

  const CustomVideoProgressBar({
    super.key,
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
  State<CustomVideoProgressBar> createState() => _CustomVideoProgressBarState();
}

class _CustomVideoProgressBarState extends State<CustomVideoProgressBar> {
  bool _isDragging = false;
  double _dragValue = 0.0;
  bool _isHoveringThumb = false;
  bool _isSeeking = false;
  StreamSubscription<dynamic>? _positionSubscription;

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

    return MouseRegion(
      cursor: widget.live ? MouseCursor.defer : SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: widget.live
            ? null
            : (details) {
                _isDragging = true;
                widget.onDragStart?.call();
                _updateDragPosition(details.localPosition.dx, context);
              },
        onHorizontalDragUpdate: widget.live
            ? null
            : (details) {
                if (_isDragging) {
                  widget.onDragUpdate?.call();
                  _updateDragPosition(details.localPosition.dx, context);
                }
              },
        onHorizontalDragEnd: widget.live
            ? null
            : (details) async {
                if (_isDragging) {
                  final seekPosition = Duration(
                    milliseconds:
                        (_dragValue * duration.inMilliseconds).round(),
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
                _updateDragPosition(details.localPosition.dx, context);
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
                    Positioned(
                      left: thumbPosition - 8,
                      top: 4,
                      child: MouseRegion(
                        onEnter: (_) => setState(() => _isHoveringThumb = true),
                        onExit: (_) => setState(() => _isHoveringThumb = false),
                        child: AnimatedScale(
                          scale: (_isHoveringThumb ||
                                  _isDragging ||
                                  widget.isSeekingViaSwipe)
                              ? 1.25
                              : 1.0,
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
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _updateDragPosition(double dx, BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;

    final width = box.size.width;
    final value = (dx / width).clamp(0.0, 1.0);

    setState(() {
      _dragValue = value;
    });

    final duration = widget.player.state.duration;
    final position =
        Duration(milliseconds: (value * duration.inMilliseconds).round());

    widget.onPositionUpdate?.call(position);
  }
}

class _CenterPlayButton extends StatefulWidget {
  final bool isPlaying;
  final bool isFullscreen;
  final VoidCallback onTap;

  const _CenterPlayButton({
    required this.isPlaying,
    required this.isFullscreen,
    required this.onTap,
  });

  @override
  State<_CenterPlayButton> createState() => _CenterPlayButtonState();
}

class _CenterPlayButtonState extends State<_CenterPlayButton> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final showBackground = !widget.isPlaying || _isHovering;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedOpacity(
              opacity: showBackground ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey.withValues(alpha: 0.7),
                ),
                child: SizedBox(
                  width: widget.isFullscreen ? 64 : 48,
                  height: widget.isFullscreen ? 64 : 48,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Icon(
                widget.isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: widget.isFullscreen ? 64 : 48,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 下载进度指示器，悬停时显示取消图标
class _DownloadProgressWithCancel extends StatefulWidget {
  final double progress;
  final double size;

  const _DownloadProgressWithCancel({
    required this.progress,
    required this.size,
  });

  @override
  State<_DownloadProgressWithCancel> createState() =>
      _DownloadProgressWithCancelState();
}

class _DownloadProgressWithCancelState
    extends State<_DownloadProgressWithCancel> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _isHovering
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
