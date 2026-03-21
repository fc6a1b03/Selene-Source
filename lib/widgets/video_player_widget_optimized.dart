import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:pip/pip.dart';
import 'package:selene/components/animations/video_loading_animation.dart';
import 'package:selene/models/video_download_info.dart';
import 'package:selene/services/high_performance_download_service.dart';
import 'package:selene/widgets/mobile_player_controls.dart';
import 'package:selene/widgets/pc_player_controls.dart';
import 'package:selene/widgets/video_player_surface.dart';

/// 高性能视频播放器组件
///
/// 优化特性：
/// 1. 下载在独立 Isolate 中执行，不影响视频播放
/// 2. 使用 Stream 替代回调，减少不必要的 Widget 重建
/// 3. 智能资源管理，播放时优先保证播放流畅
class VideoPlayerWidgetOptimized extends StatefulWidget {
  final VideoPlayerSurface surface;
  final String? url;
  final Map<String, String>? headers;
  final VoidCallback? onBackPressed;
  final void Function(VideoPlayerWidgetController)? onControllerCreated;
  final VoidCallback? onReady;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onVideoCompleted;
  final VoidCallback? onPause;
  final bool isLastEpisode;
  final void Function(dynamic)? onCastStarted;
  final String? videoTitle;
  final int? currentEpisodeIndex;
  final int? totalEpisodes;
  final String? sourceName;
  final void Function({required bool isWebFullscreen})? onWebFullscreenChanged;
  final VoidCallback? onExitFullScreen;
  final bool live;
  final void Function({required bool isPipMode})? onPipModeChanged;

  const VideoPlayerWidgetOptimized({
    super.key,
    this.surface = VideoPlayerSurface.mobile,
    this.url,
    this.headers,
    this.onBackPressed,
    this.onControllerCreated,
    this.onReady,
    this.onNextEpisode,
    this.onVideoCompleted,
    this.onPause,
    this.isLastEpisode = false,
    this.onCastStarted,
    this.videoTitle,
    this.currentEpisodeIndex,
    this.totalEpisodes,
    this.sourceName,
    this.onWebFullscreenChanged,
    this.onExitFullScreen,
    this.live = false,
    this.onPipModeChanged,
  });

  @override
  State<VideoPlayerWidgetOptimized> createState() =>
      _VideoPlayerWidgetOptimizedState();
}

/// 播放器控制器
class VideoPlayerWidgetController {
  VideoPlayerWidgetController._(this._state);

  final _VideoPlayerWidgetOptimizedState _state;

  Future<void> updateDataSource(
    String url, {
    Duration? startAt,
    Map<String, String>? headers,
  }) async {
    await _state._updateDataSource(
      url,
      startAt: startAt,
      headers: headers,
    );
  }

  Future<void> seekTo(Duration position) async {
    await _state._player?.seek(position);
  }

  Duration? get currentPosition => _state._player?.state.position;

  Duration? get duration => _state._player?.state.duration;

  bool get isPlaying => _state._player?.state.playing ?? false;

  Future<void> pause() async {
    await _state._player?.pause();
  }

  Future<void> play() async {
    await _state._player?.play();
  }

  void addProgressListener(VoidCallback listener) {
    _state._addProgressListener(listener);
  }

  void removeProgressListener(VoidCallback listener) {
    _state._removeProgressListener(listener);
  }

  Future<void> setSpeed(double speed) async {
    await _state._setPlaybackSpeed(speed);
  }

  double get playbackSpeed => _state._playbackSpeed.value;

  Future<void> setVolume(double volume) async {
    await _state._player?.setVolume(volume);
  }

  double? get volume => _state._player?.state.volume;

  void exitWebFullscreen() {
    _state._exitWebFullscreen();
  }

  Future<void> dispose() async {
    await _state._externalDispose();
  }

  bool get isPipMode => _state._isPipMode;

  // ===== 下载控制接口 =====

  VideoDownloadInfo get downloadInfo => _state._downloadInfo;

  Future<void> startDownload({String? fileName}) async {
    await _state._startDownload(fileName: fileName);
  }

  Future<void> pauseDownload() async {
    await _state._pauseDownload();
  }

  Future<void> resumeDownload() async {
    await _state._resumeDownload();
  }

  Future<void> cancelDownload() async {
    await _state._cancelDownload();
  }

  Future<String?> saveAs() async {
    return _state._saveAs();
  }
}

class _VideoPlayerWidgetOptimizedState extends State<VideoPlayerWidgetOptimized>
    with WidgetsBindingObserver {
  Player? _player;
  VideoController? _videoController;
  bool _isInitialized = false;
  bool _hasCompleted = false;
  bool _isLoadingVideo = false;
  String? _currentUrl;
  Map<String, String>? _currentHeaders;
  final List<VoidCallback> _progressListeners = <VoidCallback>[];
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  final ValueNotifier<double> _playbackSpeed = ValueNotifier<double>(1.0);
  bool _playerDisposed = false;
  VoidCallback? _exitWebFullscreenCallback;
  final Pip _pip = Pip();
  bool _isPipMode = false;
  PipStateChangedObserver? _pipObserver;

  // 视频宽高和全屏状态监听
  final ValueNotifier<BoxFit> _videoFit = ValueNotifier<BoxFit>(BoxFit.contain);
  double _videoWidth = 0;
  double _videoHeight = 0;
  Timer? _sizeCheckTimer;
  bool _isCurrentlyFullscreen = false;

  // ===== 下载相关（高性能优化）=====
  final HighPerformanceDownloadService _downloadService =
      HighPerformanceDownloadService();
  VideoDownloadInfo _downloadInfo = const VideoDownloadInfo();
  StreamSubscription<DownloadProgressEvent>? _downloadSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUrl = widget.url;
    _currentHeaders = widget.headers;
    _initializePlayer();
    _setupPip();
    _registerPipObserver();
    widget.onControllerCreated?.call(VideoPlayerWidgetController._(this));
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidgetOptimized oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.headers != oldWidget.headers && widget.headers != null) {
      _currentHeaders = widget.headers;
    }
    if (widget.url != oldWidget.url && widget.url != null) {
      unawaited(_updateDataSource(widget.url!));
    }
  }

  Future<void> _initializePlayer() async {
    if (_playerDisposed) return;

    _player = Player();
    _videoController = VideoController(_player!);
    _setupPlayerListeners();

    if (_currentUrl != null) {
      await _openCurrentMedia();
    }

    if (mounted) {
      setState(() {
        _isInitialized = true;
      });
    }
  }

  Future<void> _openCurrentMedia({Duration? startAt}) async {
    if (_playerDisposed || _player == null || _currentUrl == null) return;

    if (mounted) {
      setState(() {
        _isLoadingVideo = true;
      });
    }

    try {
      await _player!.open(
        Media(
          _currentUrl!,
          start: startAt,
          httpHeaders: _currentHeaders ?? const <String, String>{},
        ),
      );
      await _player!.setRate(_playbackSpeed.value);

      if (mounted) {
        setState(() {
          _hasCompleted = false;
        });
      }
    } catch (error) {
      debugPrint('VideoPlayerWidget: failed to open media $error');
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
    }
  }

  void _setupPlayerListeners() {
    if (_player == null) return;

    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _durationSubscription?.cancel();

    // 播放位置监听 - 用于触发进度保存
    _positionSubscription = _player!.stream.position.listen((_) {
      for (final listener in List<VoidCallback>.from(_progressListeners)) {
        try {
          listener();
        } catch (error) {
          debugPrint('VideoPlayerWidget: progress listener error $error');
        }
      }
    });

    // 播放状态监听 - 用于 PiP 设置
    _playingSubscription = _player!.stream.playing.listen((playing) {
      if (!mounted) return;
      if (!Platform.isAndroid && !Platform.isIOS) return;

      _pip.setup(
        PipOptions(
          autoEnterEnabled: playing,
          aspectRatioX: 16,
          aspectRatioY: 9,
          preferredContentWidth: 480,
          preferredContentHeight: 270,
          controlStyle: 2,
        ),
      );
    });

    // 播放完成监听
    if (!widget.live) {
      _completedSubscription = _player!.stream.completed.listen((completed) {
        if (!mounted) return;
        if (completed && !_hasCompleted) {
          _hasCompleted = true;
          widget.onVideoCompleted?.call();
        }
      });
    }

    // 时长监听 - 用于检测视频加载完成
    _durationSubscription = _player!.stream.duration.listen((duration) {
      if (!mounted) return;
      if (duration != Duration.zero) {
        if (_isLoadingVideo) {
          setState(() {
            _isLoadingVideo = false;
          });
        }
        widget.onReady?.call();
      }
    });

    // 视频尺寸监听
    _sizeCheckTimer?.cancel();
    _sizeCheckTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (timer) {
        if (!mounted || _playerDisposed) {
          timer.cancel();
          return;
        }
        final width = _player?.state.width ?? 0;
        final height = _player?.state.height ?? 0;
        if (width > 0 && height > 0) {
          if (_videoWidth != width || _videoHeight != height) {
            _videoWidth = width.toDouble();
            _videoHeight = height.toDouble();
            _updateVideoFitMode();
          }
        }
      },
    );
  }

  Future<void> _updateDataSource(
    String url, {
    Duration? startAt,
    Map<String, String>? headers,
  }) async {
    if (_playerDisposed) return;

    _currentUrl = url;
    if (headers != null) {
      _currentHeaders = headers;
    }

    // 取消之前的下载
    await _cancelDownload();

    // 重置下载状态
    _updateDownloadInfo(const VideoDownloadInfo());

    if (_player == null) {
      await _initializePlayer();
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingVideo = true;
      });
    }

    try {
      final currentSpeed = _player!.state.rate;
      await _player!.open(
        Media(
          url,
          start: startAt,
          httpHeaders: _currentHeaders ?? const <String, String>{},
        ),
      );
      _playbackSpeed.value = currentSpeed;
      await _player!.setRate(currentSpeed);

      if (mounted) {
        setState(() {
          _hasCompleted = false;
        });
      }
    } catch (error) {
      debugPrint('VideoPlayerWidget: error while changing source $error');
      if (mounted) {
        setState(() {
          _isLoadingVideo = false;
        });
      }
    }
  }

  void _addProgressListener(VoidCallback listener) {
    if (!_progressListeners.contains(listener)) {
      _progressListeners.add(listener);
    }
  }

  void _removeProgressListener(VoidCallback listener) {
    _progressListeners.remove(listener);
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    _playbackSpeed.value = speed;
    await _player?.setRate(speed);
  }

  void _updateVideoFitMode() {
    if (_videoWidth == 0 || _videoHeight == 0) return;

    final BoxFit newFit;
    if (!_isCurrentlyFullscreen) {
      newFit = BoxFit.contain;
    } else {
      newFit = _videoWidth > _videoHeight ? BoxFit.contain : BoxFit.scaleDown;
    }

    if (_videoFit.value != newFit) {
      _videoFit.value = newFit;
    }
  }

  void _exitWebFullscreen() {
    _exitWebFullscreenCallback?.call();
  }

  void _setupPip() {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    _pip.setup(
      const PipOptions(
        autoEnterEnabled: true,
        aspectRatioX: 16,
        aspectRatioY: 9,
        preferredContentWidth: 480,
        preferredContentHeight: 270,
        controlStyle: 2,
      ),
    );
  }

  void _registerPipObserver() {
    if (!Platform.isAndroid && !Platform.isIOS) return;

    _pipObserver = PipStateChangedObserver(
      onPipStateChanged: (state, error) {
        if (!mounted) return;

        switch (state) {
          case PipState.pipStateStarted:
            debugPrint('PiP started successfully');
            if (mounted) {
              setState(() => _isPipMode = true);
              widget.onPipModeChanged?.call(isPipMode: true);
            }
            break;
          case PipState.pipStateStopped:
            debugPrint('PiP stopped');
            if (mounted) {
              setState(() => _isPipMode = false);
              widget.onPipModeChanged?.call(isPipMode: false);
            }
            break;
          case PipState.pipStateFailed:
            debugPrint('PiP failed: $error');
            if (mounted) {
              setState(() => _isPipMode = false);
              widget.onPipModeChanged?.call(isPipMode: false);
            }
            break;
        }
      },
    );

    try {
      _pip.registerStateChangedObserver(_pipObserver!);
    } catch (e) {
      debugPrint('Failed to register PiP observer: $e');
    }
  }

  Future<void> _enterPipMode() async {
    try {
      final support = await _pip.isSupported();
      if (!support) {
        debugPrint('Device does not support PiP!');
        return;
      }
      await _player?.play();
      await _pip.start();
    } catch (e) {
      debugPrint('Failed to enter PiP mode: $e');
      _setupPip();
    }
  }

  Future<void> _externalDispose() async {
    if (!mounted || _playerDisposed) return;

    // 取消下载
    await _cancelDownload();

    if ((Platform.isAndroid || Platform.isIOS) && _pipObserver != null) {
      try {
        await _pip.unregisterStateChangedObserver();
      } catch (e) {
        debugPrint('Failed to unregister PiP observer: $e');
      }
      _pipObserver = null;
    }

    await _disposePlayer();
  }

  Future<void> _disposePlayer() async {
    if (_playerDisposed) return;

    _playerDisposed = true;
    _sizeCheckTimer?.cancel();

    await _positionSubscription?.cancel();
    await _playingSubscription?.cancel();
    await _completedSubscription?.cancel();
    await _durationSubscription?.cancel();

    _progressListeners.clear();
    await _player?.dispose();

    _player = null;
    _videoController = null;
  }

  // ===== 下载功能实现（高性能优化版）=====

  void _updateDownloadInfo(VideoDownloadInfo info) {
    if (mounted) {
      setState(() {
        _downloadInfo = info;
      });
    } else {
      _downloadInfo = info;
    }
  }

  Future<void> _startDownload({String? fileName}) async {
    if (_currentUrl == null) return;

    // 检查是否已有下载任务
    if (_downloadInfo.taskId != null) {
      final existingTask = _downloadService.getTask(_downloadInfo.taskId!);
      if (existingTask != null &&
          (existingTask.status == DownloadStatus.downloading ||
              existingTask.status == DownloadStatus.completed)) {
        return;
      }
    }

    // 生成文件名
    final targetFileName = fileName ??
        widget.videoTitle ??
        'video_${DateTime.now().millisecondsSinceEpoch}.mp4';

    // 确保有正确的扩展名
    var finalFileName = targetFileName;
    if (!finalFileName.contains('.')) {
      finalFileName = '$finalFileName.mp4';
    }

    // 开始下载 - 在 Isolate 中执行，不阻塞 UI
    final task = await _downloadService.startDownload(
      url: _currentUrl!,
      fileName: finalFileName,
      headers: _currentHeaders,
      episodeInfo: widget.currentEpisodeIndex != null
          ? 'EP${widget.currentEpisodeIndex}'
          : null,
    );

    if (task != null) {
      _updateDownloadInfo(
        VideoDownloadInfo(
          taskId: task.id,
          state: VideoDownloadState.downloading,
        ),
      );

      // 订阅下载进度流 - 使用节流减少 UI 更新频率
      await _downloadSubscription?.cancel();

      _downloadSubscription = _downloadService
          .getProgressStream(task.id)
          ?.throttle(const Duration(milliseconds: 200))
          .listen((event) {
        if (!mounted) return;

        final state = _convertDownloadStatus(event.status);

        _updateDownloadInfo(
          VideoDownloadInfo(
            taskId: event.taskId,
            state: state,
            progress: event.progress,
            errorMessage: event.errorMessage,
          ),
        );

        // 下载完成后自动清理订阅
        if (state == VideoDownloadState.completed ||
            state == VideoDownloadState.failed) {
          _downloadSubscription?.cancel();
          _downloadSubscription = null;
        }
      });
    }
  }

  VideoDownloadState _convertDownloadStatus(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.waiting:
        return VideoDownloadState.idle;
      case DownloadStatus.downloading:
        return VideoDownloadState.downloading;
      case DownloadStatus.paused:
        return VideoDownloadState.paused;
      case DownloadStatus.completed:
        return VideoDownloadState.completed;
      case DownloadStatus.failed:
        return VideoDownloadState.failed;
    }
  }

  Future<void> _pauseDownload() async {
    if (_downloadInfo.taskId == null) return;
    await _downloadService.pauseDownload(_downloadInfo.taskId!);
  }

  Future<void> _resumeDownload() async {
    if (_downloadInfo.taskId == null) return;
    await _downloadService.resumeDownload(_downloadInfo.taskId!);
  }

  Future<void> _cancelDownload() async {
    if (_downloadInfo.taskId == null) {
      _updateDownloadInfo(const VideoDownloadInfo());
      return;
    }

    // 取消订阅
    await _downloadSubscription?.cancel();
    _downloadSubscription = null;

    // 取消下载
    await _downloadService.cancelDownload(_downloadInfo.taskId!);

    _updateDownloadInfo(const VideoDownloadInfo());
  }

  void _disposeDownload() {
    // 取消订阅
    _downloadSubscription?.cancel();
    _downloadSubscription = null;

    // 取消下载（不等待完成，避免阻塞 dispose）
    if (_downloadInfo.taskId != null) {
      unawaited(_downloadService.cancelDownload(_downloadInfo.taskId!));
    }
  }

  Future<String?> _saveAs() async {
    if (_downloadInfo.taskId == null) return null;

    // 先自动保存到默认位置
    final autoPath = await _downloadService.autoSave(_downloadInfo.taskId!);
    if (autoPath == null) return null;

    _updateDownloadInfo(
      _downloadInfo.copyWith(filePath: autoPath),
    );

    // 然后让用户选择另存为位置（桌面端）或保存到相册（移动端）
    final userPath = await _downloadService.saveAs(_downloadInfo.taskId!);
    if (userPath != null) {
      _updateDownloadInfo(
        _downloadInfo.copyWith(filePath: userPath),
      );
    }

    // 保存完成后重置下载状态，允许重新下载
    _updateDownloadInfo(const VideoDownloadInfo());

    return userPath ?? autoPath;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    // 取消下载并清理资源（不调用 setState）
    _disposeDownload();

    if (Platform.isAndroid || Platform.isIOS) {
      if (_pipObserver != null) {
        try {
          _pip.unregisterStateChangedObserver();
        } catch (e) {
          debugPrint('Failed to unregister PiP observer during dispose: $e');
        }
        _pipObserver = null;
      }
      _pip.dispose();
    }

    _disposePlayer();
    _playbackSpeed.dispose();
    _videoFit.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: _isInitialized && _videoController != null
          ? ValueListenableBuilder<BoxFit>(
              valueListenable: _videoFit,
              builder: (context, videoFit, _) {
                final needsPadding = !_isCurrentlyFullscreen &&
                    (videoFit == BoxFit.cover || videoFit == BoxFit.scaleDown);

                final videoWidget = Video(
                  controller: _videoController!,
                  fit: videoFit,
                  controls: (state) {
                    return widget.surface == VideoPlayerSurface.desktop
                        ? PCPlayerControls(
                            state: state,
                            player: _player!,
                            onBackPressed: widget.onBackPressed,
                            onNextEpisode: widget.onNextEpisode,
                            onPause: widget.onPause,
                            videoUrl: _currentUrl ?? '',
                            isLastEpisode: widget.isLastEpisode,
                            isLoadingVideo: _isLoadingVideo,
                            onCastStarted: widget.onCastStarted,
                            videoTitle: widget.videoTitle,
                            currentEpisodeIndex: widget.currentEpisodeIndex,
                            totalEpisodes: widget.totalEpisodes,
                            sourceName: widget.sourceName,
                            onWebFullscreenChanged:
                                widget.onWebFullscreenChanged != null
                                    ? (isFullscreen) =>
                                        widget.onWebFullscreenChanged!(
                                          isWebFullscreen: isFullscreen,
                                        )
                                    : null,
                            onExitWebFullscreenCallbackReady: (callback) {
                              _exitWebFullscreenCallback = callback;
                            },
                            onExitFullScreen: widget.onExitFullScreen,
                            live: widget.live,
                            playbackSpeedListenable: _playbackSpeed,
                            onSetSpeed: _setPlaybackSpeed,
                            downloadInfo: _downloadInfo,
                            onStartDownload: _startDownload,
                            onCancelDownload: _cancelDownload,
                            onSaveAs: _saveAs,
                          )
                        : MobilePlayerControls(
                            player: _player!,
                            state: state,
                            onControlsVisibilityChanged: (_) {},
                            onBackPressed: widget.onBackPressed,
                            onFullscreenChange: (isFullscreen) {
                              _isCurrentlyFullscreen = isFullscreen;
                              _updateVideoFitMode();
                            },
                            onNextEpisode: widget.onNextEpisode,
                            onPause: widget.onPause,
                            videoUrl: _currentUrl ?? '',
                            isLastEpisode: widget.isLastEpisode,
                            isLoadingVideo: _isLoadingVideo,
                            onCastStarted: widget.onCastStarted,
                            videoTitle: widget.videoTitle,
                            currentEpisodeIndex: widget.currentEpisodeIndex,
                            totalEpisodes: widget.totalEpisodes,
                            sourceName: widget.sourceName,
                            onExitFullScreen: widget.onExitFullScreen,
                            live: widget.live,
                            playbackSpeedListenable: _playbackSpeed,
                            onSetSpeed: _setPlaybackSpeed,
                            onEnterPipMode: _enterPipMode,
                            isPipMode: _isPipMode,
                            downloadInfo: _downloadInfo,
                            onStartDownload: _startDownload,
                            onCancelDownload: _cancelDownload,
                            onSaveAs: _saveAs,
                          );
                  },
                );

                return needsPadding
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: videoWidget,
                      )
                    : videoWidget;
              },
            )
          : const Center(
              child: VideoLoadingIndicator(
                size: 48,
                color: Colors.white,
              ),
            ),
    );
  }
}

/// Stream 节流扩展
extension _StreamThrottle<T> on Stream<T> {
  Stream<T> throttle(Duration duration) {
    Timer? timer;
    T? lastEvent;
    var hasPendingEvent = false;

    return transform(
      StreamTransformer<T, T>.fromHandlers(
        handleData: (data, sink) {
          if (timer == null || !timer!.isActive) {
            sink.add(data);
            timer = Timer(duration, () {
              if (hasPendingEvent) {
                sink.add(lastEvent as T);
                hasPendingEvent = false;
              }
            });
          } else {
            lastEvent = data;
            hasPendingEvent = true;
          }
        },
      ),
    );
  }
}
