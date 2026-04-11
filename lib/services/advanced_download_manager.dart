import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:hive/hive.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:selene/models/download_task_persistent.dart';
import 'package:selene/services/high_performance_download_service.dart';

/// 下载任务进度事件
class DownloadTaskProgressEvent {
  final String taskId;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final int speed;
  final int remainingSeconds;
  final DownloadTaskPersistentStatus status;

  const DownloadTaskProgressEvent({
    required this.taskId,
    required this.progress,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.speed,
    required this.remainingSeconds,
    required this.status,
  });
}

/// 高级下载管理器
///
/// 功能特性：
/// 1. 断点续传支持
/// 2. 直播流无限下载
/// 3. Hive 持久化存储
/// 4. 多任务并行下载
/// 5. 后台下载保持
/// 6. 下载统计信息
///
/// 性能优化：
/// 1. 进度更新节流 - 每100ms最多更新一次
/// 2. Hive 批量写入 - 减少磁盘操作
/// 3. 内存缓存 - 避免重复计算
/// 4. Isolate 下载 - 不阻塞 UI

/// 判断 URL 是否为 M3U8 格式
bool _isM3u8Url(String url) {
  final lowerUrl = url.toLowerCase();
  return lowerUrl.contains('.m3u8') || lowerUrl.contains('mpegurl');
}

class AdvancedDownloadManager extends ChangeNotifier {
  static final AdvancedDownloadManager _instance =
      AdvancedDownloadManager._internal();

  factory AdvancedDownloadManager() => _instance;

  AdvancedDownloadManager._internal();

  /// Hive 存储盒子
  Box<DownloadTaskPersistent>? _taskBox;

  /// 高性能下载服务（使用 Isolate）
  final HighPerformanceDownloadService _downloadService =
      HighPerformanceDownloadService();

  /// 内存中的任务列表
  final Map<String, DownloadTaskPersistent> _tasks = {};

  /// 任务进度流控制器
  final Map<String, StreamController<DownloadTaskProgressEvent>>
      _progressControllers = {};

  /// 全局进度流控制器
  final StreamController<DownloadStatistics> _statisticsController =
      StreamController<DownloadStatistics>.broadcast();

  /// 是否已初始化
  bool _isInitialized = false;

  /// 初始化完成后的 completer
  final Completer<void> _initCompleter = Completer<void>();

  /// 速度计算用的历史记录（限制大小防止内存泄漏）
  final Map<String, List<(DateTime, int)>> _speedHistory = {};

  /// 直播流下载控制器
  final Map<String, LiveStreamDownloadController> _liveStreamControllers = {};

  /// 统计信息定时器
  Timer? _statisticsTimer;

  /// 进度更新节流定时器
  final Map<String, Timer> _throttleTimers = {};

  /// 待更新的任务缓存（批量写入）
  final Map<String, DownloadTaskPersistent> _pendingUpdates = {};

  /// 批量写入定时器
  Timer? _batchWriteTimer;

  /// 上次通知时间（节流用）
  DateTime _lastNotifyTime = DateTime.now();

  /// 获取初始化 Future
  Future<void> get initialization => _initCompleter.future;

  /// 获取统计信息流
  Stream<DownloadStatistics> get statisticsStream =>
      _statisticsController.stream;

  /// 初始化管理器
  Future<void> initialize() async {
    if (_isInitialized) return;
    if (_initCompleter.isCompleted) return _initCompleter.future;

    try {
      // 打开 Hive 盒子
      _taskBox = await Hive.openBox<DownloadTaskPersistent>('download_tasks');

      // 加载所有已保存的任务
      _loadTasksFromStorage();

      // 恢复未完成的下载
      await _resumeIncompleteTasks();

      // 启动统计信息更新
      _startStatisticsUpdate();

      _isInitialized = true;
      _initCompleter.complete();
    } catch (e, stack) {
      debugPrint('AdvancedDownloadManager 初始化失败: $e\n$stack');
      _initCompleter.completeError(e);
      rethrow;
    }
  }

  /// 从存储加载任务
  void _loadTasksFromStorage() {
    if (_taskBox == null) return;

    for (final entry in _taskBox!.toMap().entries) {
      final task = entry.value;
      _tasks[task.id] = task;
    }

    debugPrint('从存储加载了 ${_tasks.length} 个下载任务');
  }

  /// 恢复未完成的下载
  ///
  /// 注意：此方法只在应用启动时调用一次，用于恢复之前暂停/失败的任务
  /// 正在下载的任务会被标记为暂停（因为应用重启后下载连接已中断）
  Future<void> _resumeIncompleteTasks() async {
    final incompleteTasks = _tasks.values.where((task) {
      return task.status == DownloadTaskPersistentStatus.downloading ||
          (task.status == DownloadTaskPersistentStatus.paused &&
              task.supportsResume);
    }).toList();

    for (final task in incompleteTasks) {
      // 应用启动时，之前的下载连接已经中断
      // 将正在下载的任务也标记为暂停，用户可以手动恢复
      final updatedTask = task.copyWith(
        status: DownloadTaskPersistentStatus.paused,
      );
      await _updateTask(updatedTask);
    }

    debugPrint('恢复了 ${incompleteTasks.length} 个未完成任务到暂停状态');
  }

  /// 应用从后台恢复时调用
  ///
  /// 与初始化不同，这里不修改任务状态，只检查连接状态
  Future<void> onAppResumed() async {
    await initialization;

    // 只通知监听器刷新UI，不修改任何任务状态
    // 下载任务会在后台继续（如果Isolate还在运行）
    notifyListeners();

    // 应用恢复
  }

  /// 启动统计信息更新
  void _startStatisticsUpdate() {
    _statisticsTimer?.cancel();
    _statisticsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateStatistics();
    });
  }

  /// 更新统计信息
  void _updateStatistics() {
    if (_tasks.isEmpty) {
      _statisticsController.add(const DownloadStatistics());
      return;
    }

    var downloadingCount = 0;
    var completedCount = 0;
    var failedCount = 0;
    var totalDownloaded = 0;
    var currentSpeed = 0;

    for (final task in _tasks.values) {
      switch (task.status) {
        case DownloadTaskPersistentStatus.downloading:
          downloadingCount++;
          currentSpeed += task.downloadSpeed;
        case DownloadTaskPersistentStatus.completed:
        case DownloadTaskPersistentStatus.saved:
          completedCount++;
        case DownloadTaskPersistentStatus.failed:
          failedCount++;
        default:
          break;
      }
      totalDownloaded += task.downloadedBytes;
    }

    final stats = DownloadStatistics(
      totalTasks: _tasks.length,
      downloadingTasks: downloadingCount,
      completedTasks: completedCount,
      failedTasks: failedCount,
      totalDownloadedBytes: totalDownloaded,
      currentSpeed: currentSpeed,
    );

    _statisticsController.add(stats);
  }

  /// 添加新下载任务
  Future<DownloadTaskPersistent?> addDownload({
    required String url,
    required String fileName,
    String? videoTitle,
    String? videoCover,
    String? episodeInfo,
    Map<String, String>? headers,
    DownloadTaskType type = DownloadTaskType.video,
  }) async {
    await initialization;

    // 检查是否已存在相同URL的任务
    final existingTask = _findTaskByUrl(url);
    if (existingTask != null) {
      if (existingTask.status == DownloadTaskPersistentStatus.completed ||
          existingTask.status == DownloadTaskPersistentStatus.saved) {
        // 已完成任务，返回已存在
        // 任务已完成
        return existingTask;
      }
      if (existingTask.status == DownloadTaskPersistentStatus.downloading) {
        // 正在下载中
        // 任务正在下载
        return existingTask;
      }
      if (existingTask.status == DownloadTaskPersistentStatus.paused ||
          existingTask.status == DownloadTaskPersistentStatus.failed) {
        // 暂停/失败的任务，恢复下载
        // 恢复已存在任务
        await startDownload(existingTask.id);
        return existingTask;
      }
      if (existingTask.status == DownloadTaskPersistentStatus.cancelled) {
        // 已取消的任务，立即从内存和存储中移除，然后创建新任务
        // 删除已取消任务
        // 直接清理，不调用 deleteTask 避免异步等待
        await _taskBox?.delete(existingTask.id);
        _tasks.remove(existingTask.id);
        _speedHistory.remove(existingTask.id);
        _pendingUpdates.remove(existingTask.id);
      }
    }

    try {
      final taskId = _generateTaskId(url);
      final dir = await _getDownloadDirectory();
      final tempDir = await _getTempDirectory();

      // 构建最终文件名
      final String finalName = _buildFileName(fileName, episodeInfo);

      // 处理文件名冲突
      var targetPath = path.join(dir.path, finalName);
      var counter = 1;
      final ext = path.extension(finalName);
      final baseName = path.basenameWithoutExtension(finalName);
      while (File(targetPath).existsSync()) {
        targetPath = path.join(dir.path, '${baseName}_$counter$ext');
        counter++;
      }

      final tempFilePath = path.join(tempDir.path, '${taskId}_$finalName');

      final task = DownloadTaskPersistent(
        id: taskId,
        url: url,
        fileName: path.basename(targetPath),
        filePath: targetPath,
        tempFilePath: tempFilePath,
        videoTitle: videoTitle,
        videoCover: videoCover,
        episodeInfo: episodeInfo,
        type: type,
        headers: headers,
      );

      // 保存到内存和存储（立即通知UI刷新，显示新任务）
      await _updateTask(task, immediate: true);

      // 如果是普通视频，立即开始下载
      if (type == DownloadTaskType.video) {
        await startDownload(taskId);
      }

      return task;
    } catch (e, stack) {
      debugPrint('添加下载任务失败: $e\n$stack');
      return null;
    }
  }

  /// 开始下载
  Future<void> startDownload(String taskId) async {
    await initialization;

    final task = _tasks[taskId];
    if (task == null) {
      // 任务不存在
      return;
    }

    // 防止重复启动
    if (task.status == DownloadTaskPersistentStatus.downloading) {
      // 任务已在下载中
      return;
    }

    // 只有等待中、暂停、失败的任务才能开始下载
    if (task.status != DownloadTaskPersistentStatus.waiting &&
        task.status != DownloadTaskPersistentStatus.paused &&
        task.status != DownloadTaskPersistentStatus.failed) {
      debugPrint(
          '[下载管理] startDownload: 任务 ${task.fileName} 状态 ${task.status} 不允许开始下载');
      return;
    }

    // 开始下载

    if (task.type == DownloadTaskType.liveStream) {
      await _startLiveStreamDownload(task);
    } else {
      await _startVideoDownload(task);
    }
  }

  /// 开始视频下载（普通文件）
  Future<void> _startVideoDownload(DownloadTaskPersistent task) async {
    try {
      // 更新状态为下载中（立即通知UI刷新）
      final downloadingTask = task.copyWith(
        status: DownloadTaskPersistentStatus.downloading,
      );
      await _updateTask(downloadingTask, immediate: true);

      // 检查是否需要断点续传
      final resumeByte = task.supportsResume && task.downloadedBytes > 0
          ? task.downloadedBytes
          : null;

      // 使用高性能下载服务（传入相同的 taskId 确保状态同步）
      final downloadTask = await _downloadService.startDownload(
        url: task.url,
        fileName: task.fileName,
        headers: _buildHeaders(task.headers, resumeByte),
        episodeInfo: task.episodeInfo,
        externalTaskId: task.id, // 使用相同的 taskId
      );

      if (downloadTask == null) {
        throw Exception('启动下载失败');
      }

      // 监听下载进度
      _downloadService.getProgressStream(downloadTask.id)?.listen(
            (event) => _handleDownloadProgress(task.id, event),
            onError: (Object error) =>
                _handleDownloadError(task.id, error.toString()),
            onDone: () => _handleDownloadComplete(task.id),
          );
    } catch (e) {
      await _handleDownloadError(task.id, e.toString());
    }
  }

  /// 开始直播流下载
  Future<void> _startLiveStreamDownload(DownloadTaskPersistent task) async {
    // 创建直播流下载控制器
    final controller = LiveStreamDownloadController(
      task: task,
      onProgress: (progress) => _handleLiveStreamProgress(task.id, progress),
      onError: (error) => _handleDownloadError(task.id, error),
      onSaved: () => _handleLiveStreamSaved(task.id),
    );

    _liveStreamControllers[task.id] = controller;

    // 更新状态（立即通知UI刷新）
    final downloadingTask = task.copyWith(
      status: DownloadTaskPersistentStatus.downloading,
    );
    await _updateTask(downloadingTask, immediate: true);

    // 开始下载
    await controller.start();
  }

  /// 暂停下载
  Future<void> pauseDownload(String taskId) async {
    await initialization;

    final task = _tasks[taskId];
    if (task == null) return;

    if (task.type == DownloadTaskType.liveStream) {
      // 直播流暂停即保存
      await _saveLiveStream(taskId);
    } else {
      await _downloadService.pauseDownload(taskId);

      final pausedTask = task.copyWith(
        status: DownloadTaskPersistentStatus.paused,
      );
      await _updateTask(pausedTask, immediate: true);
    }
  }

  /// 恢复下载
  Future<void> resumeDownload(String taskId) async {
    await initialization;

    final task = _tasks[taskId];
    if (task == null) {
      // 任务不存在
      return;
    }

    if (!task.canResume) {
      debugPrint(
          '[下载管理] resumeDownload: 任务 ${task.fileName} 不允许恢复 (状态: ${task.status})');
      return;
    }

    // 恢复下载

    // 使用高性能下载服务的恢复功能
    if (task.type == DownloadTaskType.video) {
      // 先更新状态为下载中（立即刷新UI）
      final downloadingTask = task.copyWith(
        status: DownloadTaskPersistentStatus.downloading,
      );
      await _updateTask(downloadingTask, immediate: true);

      await _downloadService.resumeDownload(
        taskId: taskId,
        url: task.url,
        tempFilePath: task.tempFilePath,
        isM3u8: _isM3u8Url(task.url),
        headers: task.headers,
      );

      // 建立进度监听（恢复下载后需要重新监听）
      _downloadService.getProgressStream(taskId)?.listen(
            (event) => _handleDownloadProgress(task.id, event),
            onError: (Object error) =>
                _handleDownloadError(task.id, error.toString()),
            onDone: () => _handleDownloadComplete(task.id),
          );
    } else {
      // 直播流不支持恢复
      await startDownload(taskId);
    }
  }

  /// 取消下载
  Future<void> cancelDownload(String taskId) async {
    await initialization;

    final task = _tasks[taskId];
    if (task == null) {
      // 任务不存在
      return;
    }

    // 取消任务

    if (task.type == DownloadTaskType.liveStream) {
      _liveStreamControllers[taskId]?.stop();
      _liveStreamControllers.remove(taskId);
    } else {
      await _downloadService.cancelDownload(taskId);
    }

    // 删除临时文件
    await _cleanupTempFile(task.tempFilePath);

    final cancelledTask = task.copyWith(
      status: DownloadTaskPersistentStatus.cancelled,
    );
    await _updateTask(cancelledTask, immediate: true);

    // 任务已取消
  }

  /// 终止并保存直播流
  Future<void> saveLiveStream(String taskId) async {
    await _saveLiveStream(taskId);
  }

  /// 保存直播流
  Future<void> _saveLiveStream(String taskId) async {
    final controller = _liveStreamControllers[taskId];
    if (controller == null) return;

    await controller.save();
    _liveStreamControllers.remove(taskId);
  }

  /// 删除任务记录
  ///
  /// 注意：此方法只执行删除操作，不会启动其他任务
  /// 责任单一：删除 = 停止（如需要）+ 清理资源 + 移除记录
  Future<void> deleteTask(String taskId) async {
    await initialization;

    final task = _tasks[taskId];
    if (task == null) {
      // 任务不存在
      return;
    }

    // 删除任务

    // 如果正在下载，先取消（不触发其他操作）
    if (task.status == DownloadTaskPersistentStatus.downloading) {
      // 先取消任务
      // 直接调用底层取消，避免触发额外逻辑
      await _downloadService.cancelDownload(taskId);
      _liveStreamControllers[taskId]?.stop();
      _liveStreamControllers.remove(taskId);
    }

    // 删除临时文件
    await _cleanupTempFile(task.tempFilePath);

    // 如果是已完成或已保存的任务，删除最终文件
    if (task.isFinished && File(task.filePath).existsSync()) {
      try {
        await File(task.filePath).delete();
      } catch (e) {
        // 删除文件失败
      }
    }

    // 清理进度控制器
    final progressController = _progressControllers[taskId];
    if (progressController != null && !progressController.isClosed) {
      await progressController.close();
      // 关闭进度流
    }
    _progressControllers.remove(taskId);

    // 从存储和内存中移除
    await _taskBox?.delete(taskId);
    _tasks.remove(taskId);
    _speedHistory.remove(taskId);
    _pendingUpdates.remove(taskId);

    // 立即刷新并通知
    await _forceRefresh();

    debugPrint(
        '[下载管理] deleteTask: 任务 ${task.fileName} 已删除，剩余任务数: ${_tasks.length}');
  }

  /// 清理所有已完成任务
  Future<int> clearCompletedTasks() async {
    await initialization;

    final completedTasks =
        _tasks.values.where((task) => task.isFinished).toList();

    for (final task in completedTasks) {
      // 删除文件
      if (File(task.filePath).existsSync()) {
        try {
          await File(task.filePath).delete();
        } catch (e) {
          debugPrint('删除文件失败: $e');
        }
      }

      // 从存储中移除
      await _taskBox?.delete(task.id);
      _tasks.remove(task.id);
      _pendingUpdates.remove(task.id);
    }

    if (completedTasks.isNotEmpty) {
      await _forceRefresh();
    }

    return completedTasks.length;
  }

  /// 重试失败任务
  Future<void> retryTask(String taskId) async {
    await initialization;

    final task = _tasks[taskId];
    if (task == null) return;

    if (task.status != DownloadTaskPersistentStatus.failed) return;

    // 重置状态
    final resetTask = task.copyWith(
      status: DownloadTaskPersistentStatus.waiting,
      // ignore: avoid_redundant_argument_values
      errorMessage: null,
      downloadedBytes: task.supportsResume ? task.downloadedBytes : 0,
      progress: task.supportsResume ? task.progress : 0.0,
    );
    await _updateTask(resetTask, immediate: true);

    // 重新开始下载
    await startDownload(taskId);
  }

  /// 获取任务
  DownloadTaskPersistent? getTask(String taskId) => _tasks[taskId];

  /// 获取所有任务
  List<DownloadTaskPersistent> getAllTasks() => _tasks.values.toList();

  /// 获取活动（正在下载）的任务
  List<DownloadTaskPersistent> get activeTasks => _tasks.values
      .where((task) => task.status == DownloadTaskPersistentStatus.downloading)
      .toList();

  /// 获取任务流
  Stream<DownloadTaskProgressEvent>? getTaskProgressStream(String taskId) {
    if (!_progressControllers.containsKey(taskId)) {
      _progressControllers[taskId] =
          StreamController<DownloadTaskProgressEvent>.broadcast();
    }
    return _progressControllers[taskId]?.stream;
  }

  /// 处理下载进度（带节流）
  void _handleDownloadProgress(String taskId, DownloadProgressEvent event) {
    // 处理进度

    final task = _tasks[taskId];
    if (task == null) {
      // 错误: 任务不存在
      return;
    }

    // 取消之前的节流定时器
    _throttleTimers[taskId]?.cancel();

    // 计算速度
    final speed = _calculateSpeed(taskId, event.downloadedBytes);
    final remainingSeconds = event.totalBytes > 0 && speed > 0
        ? (event.totalBytes - event.downloadedBytes) ~/ speed
        : 0;

    final status = event.status == DownloadStatus.completed
        ? DownloadTaskPersistentStatus.completed
        : DownloadTaskPersistentStatus.downloading;

    final updatedTask = task.copyWith(
      progress: event.progress,
      downloadedBytes: event.downloadedBytes,
      totalBytes: event.totalBytes,
      downloadSpeed: speed,
      remainingSeconds: remainingSeconds,
      status: status,
    );

    // 更新任务并通知UI（使用节流）
    _updateTask(updatedTask);

    // 通知进度流（使用节流，每100ms最多一次）
    _throttleTimers[taskId] = Timer(const Duration(milliseconds: 100), () {
      _progressControllers[taskId]?.add(DownloadTaskProgressEvent(
        taskId: taskId,
        progress: event.progress,
        downloadedBytes: event.downloadedBytes,
        totalBytes: event.totalBytes,
        speed: speed,
        remainingSeconds: remainingSeconds,
        status: status,
      ));
      _throttleTimers.remove(taskId);
    });
  }

  /// 处理直播流进度
  void _handleLiveStreamProgress(
    String taskId,
    LiveStreamProgress progress,
  ) {
    final task = _tasks[taskId];
    if (task == null) return;

    // 计算速度
    final speed = _calculateSpeed(taskId, progress.downloadedBytes);

    final updatedTask = task.copyWith(
      downloadedBytes: progress.downloadedBytes,
      totalBytes: progress.downloadedBytes, // 直播流总大小等于已下载
      downloadSpeed: speed,
      status: DownloadTaskPersistentStatus.downloading,
    );

    _updateTaskWithoutNotify(updatedTask);

    // 通知进度流
    _progressControllers[taskId]?.add(DownloadTaskProgressEvent(
      taskId: taskId,
      progress: -1, // 直播流无进度百分比
      downloadedBytes: progress.downloadedBytes,
      totalBytes: progress.downloadedBytes,
      speed: speed,
      remainingSeconds: -1,
      status: DownloadTaskPersistentStatus.downloading,
    ));
  }

  /// 处理下载完成
  Future<void> _handleDownloadComplete(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;

    // 移动临时文件到最终位置
    final tempFile = File(task.tempFilePath);
    if (tempFile.existsSync()) {
      try {
        await tempFile.copy(task.filePath);
        await tempFile.delete();
      } catch (e) {
        debugPrint('移动文件失败: $e');
      }
    }

    final completedTask = task.copyWith(
      status: DownloadTaskPersistentStatus.completed,
      progress: 1.0,
      downloadSpeed: 0,
      remainingSeconds: 0,
    );
    await _updateTask(completedTask, immediate: true);

    // 扫描媒体文件，使其出现在相册中
    await _scanMediaFile(task.filePath);

    _progressControllers[taskId]?.add(DownloadTaskProgressEvent(
      taskId: taskId,
      progress: 1.0,
      downloadedBytes: task.totalBytes,
      totalBytes: task.totalBytes,
      speed: 0,
      remainingSeconds: 0,
      status: DownloadTaskPersistentStatus.completed,
    ));
  }

  /// 处理直播流保存完成
  Future<void> _handleLiveStreamSaved(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return;

    final savedTask = task.copyWith(
      status: DownloadTaskPersistentStatus.saved,
      downloadSpeed: 0,
    );
    await _updateTask(savedTask, immediate: true);

    // 扫描媒体文件，使其出现在相册中
    await _scanMediaFile(task.filePath);

    _progressControllers[taskId]?.add(DownloadTaskProgressEvent(
      taskId: taskId,
      progress: 1.0,
      downloadedBytes: task.downloadedBytes,
      totalBytes: task.downloadedBytes,
      speed: 0,
      remainingSeconds: 0,
      status: DownloadTaskPersistentStatus.saved,
    ));
  }

  /// 处理下载错误
  Future<void> _handleDownloadError(String taskId, String error) async {
    final task = _tasks[taskId];
    if (task == null) return;

    final failedTask = task.copyWith(
      status: DownloadTaskPersistentStatus.failed,
      errorMessage: error,
      downloadSpeed: 0,
    );
    await _updateTask(failedTask, immediate: true);

    _progressControllers[taskId]?.add(DownloadTaskProgressEvent(
      taskId: taskId,
      progress: task.progress,
      downloadedBytes: task.downloadedBytes,
      totalBytes: task.totalBytes,
      speed: 0,
      remainingSeconds: 0,
      status: DownloadTaskPersistentStatus.failed,
    ));
  }

  /// 计算下载速度（使用滑动窗口，限制内存使用）
  int _calculateSpeed(String taskId, int downloadedBytes) {
    final now = DateTime.now();
    final history = _speedHistory.putIfAbsent(taskId, () => []);

    // 添加新记录
    history.add((now, downloadedBytes));

    // 限制历史记录大小（最多20条，约5秒的数据）
    while (history.length > 20) {
      history.removeAt(0);
    }

    // 清理超过5秒的记录
    history.removeWhere((record) => now.difference(record.$1).inSeconds > 5);

    // 计算速度
    if (history.length < 2) return 0;

    final first = history.first;
    final last = history.last;
    final timeDiff = last.$1.difference(first.$1).inSeconds;
    final byteDiff = last.$2 - first.$2;

    if (timeDiff <= 0) return 0;
    return byteDiff ~/ timeDiff;
  }

  /// 更新任务（通知监听器）
  ///
  /// 状态变化时立即通知，进度更新时节流
  Future<void> _updateTask(
    DownloadTaskPersistent task, {
    bool immediate = false,
  }) async {
    _tasks[task.id] = task;
    _pendingUpdates[task.id] = task;
    _startBatchWriteTimer();

    // 状态变化时立即通知，进度更新时节流
    final now = DateTime.now();
    final timeSinceLastNotify = now.difference(_lastNotifyTime).inMilliseconds;

    // 立即通知条件：
    // 1. immediate 参数为 true
    // 2. 状态变化（非下载中状态）
    // 3. 距离上次通知超过 100ms
    if (immediate ||
        task.status != DownloadTaskPersistentStatus.downloading ||
        timeSinceLastNotify >= 100) {
      _lastNotifyTime = now;
      notifyListeners();
    }
  }

  /// 更新任务（不通知监听器）
  Future<void> _updateTaskWithoutNotify(DownloadTaskPersistent task) async {
    _tasks[task.id] = task;
    _pendingUpdates[task.id] = task;
    _startBatchWriteTimer();
  }

  /// 强制刷新 - 立即写入并通知
  ///
  /// 在关键操作（如暂停、恢复、删除）后调用，确保UI立即更新
  Future<void> _forceRefresh() async {
    // 立即刷新待更新任务
    await _flushPendingUpdates();

    // 立即通知
    _lastNotifyTime = DateTime.now();
    notifyListeners();
  }

  /// 启动批量写入定时器
  void _startBatchWriteTimer() {
    if (_batchWriteTimer?.isActive ?? false) return;

    _batchWriteTimer = Timer(const Duration(milliseconds: 500), () {
      _flushPendingUpdates();
    });
  }

  /// 刷新待更新任务到 Hive
  Future<void> _flushPendingUpdates() async {
    if (_pendingUpdates.isEmpty) return;

    final updates = Map<String, DownloadTaskPersistent>.from(_pendingUpdates);
    _pendingUpdates.clear();

    // 批量写入
    await _taskBox?.putAll(updates);
  }

  /// 保存视频到系统相册
  ///
  /// 使用 gal 包自动处理各平台的媒体保存
  /// - Android: 保存到 Pictures/Movies 并触发 MediaScanner
  /// - iOS: 保存到 Photos 相册
  Future<void> _scanMediaFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        // 文件不存在
        return;
      }

      // 使用 gal 包保存到相册
      await Gal.putVideo(filePath);
      // 已保存到相册
    } catch (e) {
      // gal 包可能会抛出权限异常等，捕获但不影响下载流程
      // 保存到相册失败
    }
  }

  /// 通过URL查找任务
  DownloadTaskPersistent? _findTaskByUrl(String url) {
    for (final task in _tasks.values) {
      if (task.url == url) return task;
    }
    return null;
  }

  /// 生成任务ID
  String _generateTaskId(String url) {
    final hash = url.hashCode.abs().toRadixString(36);
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${hash}_$timestamp';
  }

  /// 构建文件名
  String _buildFileName(String fileName, String? episodeInfo) {
    if (episodeInfo == null || episodeInfo.isEmpty) return fileName;

    final ext = fileName.contains('.')
        ? fileName.substring(fileName.lastIndexOf('.'))
        : '.mp4';
    final base = fileName.substring(
      0,
      fileName.lastIndexOf('.') > 0
          ? fileName.lastIndexOf('.')
          : fileName.length,
    );
    return '${base.trim()}-$episodeInfo$ext';
  }

  /// 构建请求头
  Map<String, String>? _buildHeaders(
    Map<String, String>? baseHeaders,
    int? resumeByte,
  ) {
    final headers = Map<String, String>.from(baseHeaders ?? {});

    if (resumeByte != null && resumeByte > 0) {
      headers['Range'] = 'bytes=$resumeByte-';
    }

    return headers.isEmpty ? null : headers;
  }

  /// 获取下载目录
  Future<Directory> _getDownloadDirectory() async {
    Directory? dir;
    try {
      if (Platform.isAndroid) {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final match =
              RegExp(r'^(/storage/emulated/\d+)').firstMatch(externalDir.path);
          if (match != null) {
            final storageRoot = match.group(1)!;
            dir = Directory('$storageRoot/Download');
          }
        }
        dir ??= await getDownloadsDirectory();
      } else if (Platform.isIOS) {
        dir = await getApplicationDocumentsDirectory();
      } else {
        dir = await getDownloadsDirectory();
      }
    } catch (e) {
      debugPrint('获取下载目录失败: $e');
    }

    dir ??= await getApplicationDocumentsDirectory();

    final moonTVDir = Directory(path.join(dir.path, 'MoonTV'));
    if (!moonTVDir.existsSync()) {
      await moonTVDir.create(recursive: true);
    }
    return moonTVDir;
  }

  /// 获取临时目录
  Future<Directory> _getTempDirectory() async {
    final tempDir = await getTemporaryDirectory();
    final downloadTempDir =
        Directory(path.join(tempDir.path, 'selene_downloads'));
    if (!downloadTempDir.existsSync()) {
      await downloadTempDir.create(recursive: true);
    }
    return downloadTempDir;
  }

  /// 清理临时文件
  Future<void> _cleanupTempFile(String tempPath) async {
    final file = File(tempPath);
    if (file.existsSync()) {
      try {
        await file.delete();
      } catch (e) {
        debugPrint('删除临时文件失败: $e');
      }
    }
  }

  /// 释放资源
  @override
  void dispose() {
    _statisticsTimer?.cancel();
    _batchWriteTimer?.cancel();

    // 取消所有节流定时器
    for (final timer in _throttleTimers.values) {
      timer.cancel();
    }
    _throttleTimers.clear();

    // 刷新待更新任务
    _flushPendingUpdates();

    _statisticsController.close();

    for (final controller in _progressControllers.values) {
      controller.close();
    }
    _progressControllers.clear();

    _taskBox?.close();
    _downloadService.dispose();

    for (final controller in _liveStreamControllers.values) {
      controller.dispose();
    }
    _liveStreamControllers.clear();

    _speedHistory.clear();
    _pendingUpdates.clear();

    super.dispose();
  }
}

/// 直播流下载进度
class LiveStreamProgress {
  final int downloadedBytes;
  final Duration duration;

  LiveStreamProgress({
    required this.downloadedBytes,
    required this.duration,
  });
}

/// 直播流下载控制器
class LiveStreamDownloadController {
  final DownloadTaskPersistent task;
  final void Function(LiveStreamProgress) onProgress;
  final void Function(String) onError;
  final VoidCallback onSaved;

  LiveStreamDownloadController({
    required this.task,
    required this.onProgress,
    required this.onError,
    required this.onSaved,
  });

  bool _isRunning = false;
  bool _shouldSave = false;
  int _totalBytes = 0;
  Duration _duration = Duration.zero;
  Timer? _progressTimer;

  bool get isRunning => _isRunning;

  Future<void> start() async {
    if (_isRunning) return;

    _isRunning = true;
    _shouldSave = false;

    // 模拟直播流下载（实际实现需要使用 media_kit 或其他方式录制）
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isRunning) return;

      if (_shouldSave) {
        _saveAndStop();
        return;
      }

      // 模拟下载进度（实际应从录制流获取）
      _totalBytes += 1024 * 1024; // 假设每秒 1MB
      _duration += const Duration(seconds: 1);

      onProgress(LiveStreamProgress(
        downloadedBytes: _totalBytes,
        duration: _duration,
      ));
    });
  }

  Future<void> save() async {
    _shouldSave = true;
  }

  void stop() {
    _isRunning = false;
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  Future<void> _saveAndStop() async {
    stop();
    onSaved();
  }

  void dispose() {
    stop();
  }
}
