import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:selene/components/animations/video_loading_animation.dart';
import 'package:selene/models/download_task_persistent.dart';
import 'package:selene/models/video_download_info.dart';
import 'package:selene/services/advanced_download_manager.dart';
import 'package:selene/services/download_service.dart';
import 'package:selene/utils/pip_manager.dart';
import 'package:selene/widgets/mobile_player_controls.dart';
import 'package:selene/widgets/pc_player_controls.dart';
import 'package:selene/widgets/video_player_surface.dart';

class VideoPlayerWidget extends StatefulWidget {
  final VideoPlayerSurface surface;
  final String? url;
  final Map<String, String>? headers;
  final VoidCallback? onBackPressed;
  final void Function(VideoPlayerWidgetController)? onControllerCreated;
  final VoidCallback? onReady;
  final void Function(String error)? onError;
  final VoidCallback? onNextEpisode;
  final VoidCallback? onVideoCompleted;
  final VoidCallback? onPause;
  final bool isLastEpisode;
  final void Function(dynamic)? onCastStarted;
  final String? videoTitle;
  final int? currentEpisodeIndex;
  final int? totalEpisodes;
  final String? sourceName;

  // ignore: avoid_positional_boolean_parameters
  final void Function(bool isWebFullscreen)? onWebFullscreenChanged;
  final VoidCallback? onExitFullScreen;
  final bool live;

  // ignore: avoid_positional_boolean_parameters
  final void Function(bool isPipMode)? onPipModeChanged;

  const VideoPlayerWidget({
    super.key,
    this.surface = VideoPlayerSurface.mobile,
    this.url,
    this.headers,
    this.onBackPressed,
    this.onControllerCreated,
    this.onReady,
    this.onError,
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
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class VideoPlayerWidgetController {
  VideoPlayerWidgetController._(this._state);

  final _VideoPlayerWidgetState _state;

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

  /// 获取当前下载信息
  VideoDownloadInfo get downloadInfo => _state._downloadInfo;

  /// 开始下载当前视频
  Future<void> startDownload({String? fileName}) async {
    await _state._startDownload(fileName: fileName);
  }

  /// 暂停下载
  Future<void> pauseDownload() async {
    await _state._pauseDownload();
  }

  /// 恢复下载
  Future<void> resumeDownload() async {
    await _state._resumeDownload();
  }

  /// 取消下载
  Future<void> cancelDownload() async {
    await _state._cancelDownload();
  }

  /// 另存为
  Future<String?> saveAs() async {
    return _state._saveAs();
  }

  /// 添加下载状态监听
  void addDownloadListener(ValueChanged<VideoDownloadInfo> listener) {
    _state._addDownloadListener(listener);
  }

  /// 移除下载状态监听
  void removeDownloadListener(ValueChanged<VideoDownloadInfo> listener) {
    _state._removeDownloadListener(listener);
  }
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
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

  // 画中画管理器（平台区分实现）
  final PipManager _pipManager = PipManager();
  bool _isPipMode = false;

  // 视频宽高和全屏状态监听
  final ValueNotifier<BoxFit> _videoFit = ValueNotifier<BoxFit>(BoxFit.contain);
  double _videoWidth = 0;
  double _videoHeight = 0;
  Timer? _sizeCheckTimer;
  bool _isCurrentlyFullscreen = false;

  // ===== 下载相关 =====
  final DownloadService _downloadService = DownloadService();
  VideoDownloadInfo _downloadInfo = const VideoDownloadInfo();
  final List<ValueChanged<VideoDownloadInfo>> _downloadListeners =
      <ValueChanged<VideoDownloadInfo>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUrl = widget.url;
    _currentHeaders = widget.headers;
    _initializePlayer();
    _initializePip();
    widget.onControllerCreated?.call(VideoPlayerWidgetController._(this));
  }

  /// 初始化画中画功能
  Future<void> _initializePip() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return;
    }

    // 设置状态变化回调
    _pipManager.setOnPipModeChanged(({required isPipMode}) {
      if (!mounted) return;
      setState(() {
        _isPipMode = isPipMode;
      });
      widget.onPipModeChanged?.call(isPipMode);
    });

    // 初始化
    await _pipManager.initialize();
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.headers != oldWidget.headers && widget.headers != null) {
      _currentHeaders = widget.headers;
    }
    if (widget.url != oldWidget.url && widget.url != null) {
      unawaited(_updateDataSource(widget.url!));
    }
  }

  Future<void> _initializePlayer() async {
    if (_playerDisposed) {
      return;
    }
    try {
      // 使用 PlayerConfiguration 优化播放器配置
      // 根据官方文档建议配置参数
      _player = Player(
        configuration: const PlayerConfiguration(
          // 降低日志级别以减少性能开销
          logLevel: MPVLogLevel.warn,
        ),
      );

      // 配置 VideoController
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
    } catch (e) {
      debugPrint('VideoPlayerWidget: 初始化播放器失败: $e');
      _setLoadingState(false);
      widget.onError?.call(e.toString());
    }
  }

  Future<void> _openCurrentMedia({Duration? startAt}) async {
    if (_playerDisposed || _player == null || _currentUrl == null) {
      return;
    }

    // 检查 URL 有效性
    if (_currentUrl!.isEmpty || !_isValidUrl(_currentUrl!)) {
      debugPrint('VideoPlayerWidget: invalid URL $_currentUrl');
      _setLoadingState(false);
      return;
    }

    _setLoadingState(true);

    try {
      await _player!.open(
        Media(
          _currentUrl!,
          start: startAt,
          httpHeaders: _currentHeaders ?? const <String, String>{},
        ),
      );
      await _player!.setRate(_playbackSpeed.value);
      _setCompletedState(false);
    } catch (error) {
      debugPrint('VideoPlayerWidget: failed to open media $error');
      _setLoadingState(false);
      widget.onError?.call(error.toString());
    }
  }

  /// 检查 URL 是否有效
  bool _isValidUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https');
    } catch (e) {
      return false;
    }
  }

  /// 安全地设置加载状态
  void _setLoadingState(bool loading) {
    if (mounted && !_playerDisposed) {
      setState(() {
        _isLoadingVideo = loading;
      });
    }
  }

  /// 安全地设置完成状态
  void _setCompletedState(bool completed) {
    if (mounted && !_playerDisposed) {
      setState(() {
        _hasCompleted = completed;
      });
    }
  }

  // 用于节流位置更新的时间戳
  DateTime? _lastPositionUpdate;
  static const _positionUpdateInterval = Duration(milliseconds: 500);

  void _setupPlayerListeners() {
    if (_player == null) {
      return;
    }

    // 取消之前的订阅
    _cancelAllSubscriptions();

    // 使用 listen 的 onError 参数增强错误处理
    _positionSubscription = _player!.stream.position.listen(
      (_) {
        // 节流：每 500ms 最多通知一次监听器
        final now = DateTime.now();
        if (_lastPositionUpdate != null &&
            now.difference(_lastPositionUpdate!) < _positionUpdateInterval) {
          return;
        }
        _lastPositionUpdate = now;

        for (final listener in List<VoidCallback>.from(_progressListeners)) {
          try {
            listener();
          } catch (error) {
            debugPrint('VideoPlayerWidget: progress listener error $error');
          }
        }
      },
      onError: (Object error) {
        debugPrint('VideoPlayerWidget: position stream error: $error');
      },
      cancelOnError: false,
    );

    _playingSubscription = _player!.stream.playing.listen(
      (playing) {
        if (!mounted || _playerDisposed) return;
        if (!Platform.isAndroid && !Platform.isIOS) {
          return;
        }
        _updatePipConfiguration(playing);
      },
      onError: (Object error) {
        debugPrint('VideoPlayerWidget: playing stream error: $error');
      },
    );

    if (!widget.live) {
      _completedSubscription = _player!.stream.completed.listen(
        (completed) {
          if (!mounted || _playerDisposed) return;
          if (completed && !_hasCompleted) {
            _hasCompleted = true;
            widget.onVideoCompleted?.call();
          }
        },
        onError: (Object error) {
          debugPrint('VideoPlayerWidget: completed stream error: $error');
        },
      );
    }

    _durationSubscription = _player!.stream.duration.listen(
      (duration) {
        if (!mounted || _playerDisposed) return;
        if (duration != Duration.zero) {
          _setLoadingState(false);
          widget.onReady?.call();
        }
      },
      onError: (Object error) {
        debugPrint('VideoPlayerWidget: duration stream error: $error');
      },
    );

    // 监听视频尺寸变化并更新视频填充模式
    _setupSizeCheckTimer();
  }

  /// 取消所有 Stream 订阅
  void _cancelAllSubscriptions() {
    _positionSubscription?.cancel();
    _playingSubscription?.cancel();
    _completedSubscription?.cancel();
    _durationSubscription?.cancel();
  }

  /// 更新 PiP 配置
  Future<void> _updatePipConfiguration(bool playing) async {
    if (!mounted) return;

    setState(() {
      _hasCompleted = false;
    });

    await _pipManager.configure(playing: playing);
  }

  /// 设置尺寸检查定时器
  void _setupSizeCheckTimer() {
    _sizeCheckTimer?.cancel();
    _sizeCheckTimer = Timer.periodic(
      const Duration(milliseconds: 1000),
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
    if (_playerDisposed || !mounted) {
      return;
    }

    // 验证 URL
    if (url.isEmpty || !_isValidUrl(url)) {
      debugPrint('VideoPlayerWidget: 无效的 URL: $url');
      return;
    }

    _currentUrl = url;
    if (headers != null) {
      _currentHeaders = headers;
    }

    // 取消之前的下载
    await _cancelDownload();

    // 如果播放器未初始化，先初始化
    if (_player == null) {
      await _initializePlayer();
      return;
    }

    _setLoadingState(true);
    _setCompletedState(false);

    try {
      // 保存当前播放速度
      final currentSpeed = _player!.state.rate;

      // 打开新媒体（默认自动播放）
      await _player!.open(
        Media(
          url,
          start: startAt,
          httpHeaders: _currentHeaders ?? const <String, String>{},
        ),
      );

      // 恢复播放速度
      if (currentSpeed != 1.0) {
        await _player!.setRate(currentSpeed);
      }
      _playbackSpeed.value = currentSpeed;
    } catch (error) {
      debugPrint('VideoPlayerWidget: 切换视频源失败: $error');
      _setLoadingState(false);
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

  /// 更新视频贴合模式
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

  Future<void> _enterPipMode() async {
    debugPrint('_enterPipMode');
    try {
      final support = await _pipManager.isSupported();
      if (!support) {
        debugPrint('Device does not support PiP!');
        return;
      }
      // 不要强制播放，保持当前状态（如果原来是暂停的，进入 PiP 后仍保持暂停）
      await _pipManager.enterPipMode();
    } catch (e) {
      debugPrint('Failed to enter PiP mode: $e');
    }
  }

  Future<void> _exitPipMode() async {
    debugPrint('_exitPipMode');
    try {
      // Android 无法直接退出 PiP，只能通过返回按钮或系统手势
      // iOS 可以通过编程退出
      if (Platform.isIOS) {
        await _pipManager.exitPipMode();
      }
      // 恢复全屏状态
      if (mounted) {
        setState(() {
          _isPipMode = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to exit PiP mode: $e');
    }
  }

  Future<void> _externalDispose() async {
    if (_playerDisposed) {
      return;
    }
    // 取消下载
    await _cancelDownload();

    await _disposePlayer();
  }

  Future<void> _disposePlayer() async {
    if (_playerDisposed) {
      return;
    }
    _playerDisposed = true;

    // 先暂停播放，确保音频/视频立即停止
    try {
      await _player?.pause();
    } catch (e) {
      debugPrint('VideoPlayerWidget: 暂停播放器时出错: $e');
    }

    // 取消定时器
    _sizeCheckTimer?.cancel();
    _sizeCheckTimer = null;

    // 取消所有 Stream 订阅
    _cancelAllSubscriptions();
    _positionSubscription = null;
    _playingSubscription = null;
    _completedSubscription = null;
    _durationSubscription = null;

    // 清空监听器
    _progressListeners.clear();

    // 释放播放器资源
    try {
      await _player?.dispose();
    } catch (e) {
      debugPrint('VideoPlayerWidget: 释放播放器时出错: $e');
    }

    _player = null;
    _videoController = null;
  }

  // ===== 下载功能实现 =====

  void _addDownloadListener(ValueChanged<VideoDownloadInfo> listener) {
    if (!_downloadListeners.contains(listener)) {
      _downloadListeners.add(listener);
    }
  }

  void _removeDownloadListener(ValueChanged<VideoDownloadInfo> listener) {
    _downloadListeners.remove(listener);
  }

  void _notifyDownloadListeners() {
    for (final listener in List<ValueChanged<VideoDownloadInfo>>.of(
      _downloadListeners,
    )) {
      try {
        listener(_downloadInfo);
      } catch (e) {
        debugPrint('Download listener error: $e');
      }
    }
  }

  void _updateDownloadInfo(VideoDownloadInfo info) {
    if (mounted) {
      setState(() {
        _downloadInfo = info;
      });
    } else {
      _downloadInfo = info;
    }
    _notifyDownloadListeners();
  }

  Future<void> _startDownload({String? fileName}) async {
    if (_currentUrl == null) return;

    // 使用高级下载管理器
    final downloadManager = AdvancedDownloadManager();
    await downloadManager.initialization;

    // 检查是否已有下载任务
    final existingTask = downloadManager
        .getAllTasks()
        .cast<DownloadTaskPersistent?>()
        .firstWhere(
          (task) => task?.url == _currentUrl,
          orElse: () => null,
        );

    if (existingTask != null &&
        (existingTask.isDownloading || existingTask.isFinished)) {
      return;
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

    // 确定下载类型（直播或普通视频）
    final isLiveStream = widget.live || _currentUrl!.contains('live');

    // 使用高级下载管理器添加下载任务
    final task = await downloadManager.addDownload(
      url: _currentUrl!,
      fileName: finalFileName,
      videoTitle: widget.videoTitle,
      episodeInfo: widget.currentEpisodeIndex != null
          ? 'EP${widget.currentEpisodeIndex}'
          : null,
      headers: _currentHeaders,
      type: isLiveStream ? DownloadTaskType.liveStream : DownloadTaskType.video,
    );

    if (task != null) {
      _updateDownloadInfo(
        VideoDownloadInfo(
          taskId: task.id,
          state: VideoDownloadState.downloading,
        ),
      );

      // 添加监听器
      downloadManager.getTaskProgressStream(task.id)?.listen(
            (event) => _onAdvancedDownloadProgress(event),
          );
    }
  }

  /// 处理高级下载管理器的进度更新
  void _onAdvancedDownloadProgress(DownloadTaskProgressEvent event) {
    if (!mounted) return;

    VideoDownloadState state;
    switch (event.status) {
      case DownloadTaskPersistentStatus.waiting:
        state = VideoDownloadState.idle;
      case DownloadTaskPersistentStatus.downloading:
        state = VideoDownloadState.downloading;
      case DownloadTaskPersistentStatus.paused:
        state = VideoDownloadState.paused;
      case DownloadTaskPersistentStatus.completed:
      case DownloadTaskPersistentStatus.saved:
        state = VideoDownloadState.completed;
      case DownloadTaskPersistentStatus.failed:
        state = VideoDownloadState.failed;
      case DownloadTaskPersistentStatus.cancelled:
        state = VideoDownloadState.idle;
    }

    _updateDownloadInfo(
      _downloadInfo.copyWith(
        state: state,
        progress: event.progress,
      ),
    );
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

    // 使用高级下载管理器取消下载
    final downloadManager = AdvancedDownloadManager();
    await downloadManager.cancelDownload(_downloadInfo.taskId!);

    _updateDownloadInfo(const VideoDownloadInfo());
  }

  /// 在 dispose 时清理下载资源（不调用 setState）
  void _disposeDownload() {
    if (_downloadInfo.taskId == null) return;

    // 取消下载（会删除临时文件）- 不等待完成，避免阻塞 dispose
    final downloadManager = AdvancedDownloadManager();
    unawaited(downloadManager.cancelDownload(_downloadInfo.taskId!));
  }

  Future<String?> _saveAs() async {
    if (_downloadInfo.taskId == null) return null;

    // 使用高级下载管理器保存
    final downloadManager = AdvancedDownloadManager();
    final task = downloadManager.getTask(_downloadInfo.taskId!);
    if (task == null) return null;

    _updateDownloadInfo(
      _downloadInfo.copyWith(filePath: task.filePath),
    );

    // 保存完成后重置下载状态，允许重新下载
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _updateDownloadInfo(const VideoDownloadInfo());
      }
    });

    return task.filePath;
  }

  // 记录应用进入后台前的播放状态
  bool _wasPlayingBeforePause = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_player == null || _playerDisposed) {
      return;
    }

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // 应用进入后台时记录播放状态
        _wasPlayingBeforePause = _player!.state.playing;
        break;
      case AppLifecycleState.hidden:
        // Android 10+ 可能触发，但通常不需要特殊处理
        break;
      case AppLifecycleState.resumed:
        // 应用回到前台时，如果需要可以恢复播放
        // 注意：是否恢复播放取决于业务需求
        break;
      case AppLifecycleState.detached:
        // 应用被销毁时确保释放资源
        // 注意：实际释放应在 dispose 中处理
        break;
    }
  }

  /// 获取应用进入后台前的播放状态
  bool get wasPlayingBeforePause => _wasPlayingBeforePause;

  @override
  void dispose() {
    // 标记为已销毁，防止后续操作
    _playerDisposed = true;

    // 移除应用生命周期监听
    WidgetsBinding.instance.removeObserver(this);

    // 取消下载并清理临时文件（不调用 setState）
    _disposeDownload();

    // 释放 PiP 资源
    if (Platform.isAndroid || Platform.isIOS) {
      unawaited(_pipManager.dispose());
    }

    // 释放播放器资源（启动异步操作但不等待）
    unawaited(_disposePlayer());

    // 释放 ValueNotifier
    _playbackSpeed.dispose();
    _videoFit.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 使用 RepaintBoundary 隔离视频播放器的重绘
    return RepaintBoundary(
      child: ColoredBox(
        color: Colors.black,
        child: _isInitialized && _videoController != null
            ? ValueListenableBuilder<BoxFit>(
                valueListenable: _videoFit,
                builder: (context, videoFit, _) {
                  final needsPadding = !_isCurrentlyFullscreen &&
                      (videoFit == BoxFit.cover ||
                          videoFit == BoxFit.scaleDown);
                  final videoWidget = Video(
                    controller: _videoController!,
                    fit: videoFit,
                    // 自定义全屏回调，覆盖默认的横屏强制设置
                    onEnterFullscreen: () async {
                      // 仅隐藏系统UI，不设置方向（方向由 MobilePlayerControls 控制）
                      await SystemChrome.setEnabledSystemUIMode(
                        SystemUiMode.immersiveSticky,
                        overlays: [],
                      );
                    },
                    onExitFullscreen: () async {
                      // 恢复系统UI
                      await SystemChrome.setEnabledSystemUIMode(
                        SystemUiMode.manual,
                        overlays: SystemUiOverlay.values,
                      );
                    },
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
                                  widget.onWebFullscreenChanged,
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
                              onExitPip: _exitPipMode,
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
      ),
    );
  }
}
