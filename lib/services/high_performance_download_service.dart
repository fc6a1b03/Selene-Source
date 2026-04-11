import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:selene/utils/isolate_decryptor.dart';

/// 下载任务状态枚举
enum DownloadStatus {
  waiting,
  downloading,
  paused,
  completed,
  failed,
}

/// 下载任务信息
class DownloadTask {
  final String id;
  final String url;
  final String fileName;
  final String filePath;
  final String tempFilePath;
  int totalBytes;
  int downloadedBytes;
  double progress;
  DownloadStatus status;
  String? errorMessage;
  final DateTime createdAt;
  DateTime updatedAt;
  bool isM3u8;

  DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.filePath,
    required this.tempFilePath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.progress = 0.0,
    this.status = DownloadStatus.waiting,
    this.errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.isM3u8 = false,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory DownloadTask.fromJson(Map<String, dynamic> json) => DownloadTask(
        id: json['id'] as String,
        url: json['url'] as String,
        fileName: json['fileName'] as String,
        filePath: json['filePath'] as String,
        tempFilePath: json['tempFilePath'] as String? ?? '',
        totalBytes: json['totalBytes'] as int? ?? 0,
        downloadedBytes: json['downloadedBytes'] as int? ?? 0,
        progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
        status: DownloadStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => DownloadStatus.waiting,
        ),
        errorMessage: json['errorMessage'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
        updatedAt: DateTime.parse(json['updatedAt'] as String),
        isM3u8: json['isM3u8'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'filePath': filePath,
        'tempFilePath': tempFilePath,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        'progress': progress,
        'status': status.name,
        'errorMessage': errorMessage,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'isM3u8': isM3u8,
      };

  DownloadTask copyWith({
    String? id,
    String? url,
    String? fileName,
    String? filePath,
    String? tempFilePath,
    int? totalBytes,
    int? downloadedBytes,
    double? progress,
    DownloadStatus? status,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isM3u8,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      tempFilePath: tempFilePath ?? this.tempFilePath,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      isM3u8: isM3u8 ?? this.isM3u8,
    );
  }
}

/// 下载进度事件
class DownloadProgressEvent {
  final String taskId;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final DownloadStatus status;
  final String? errorMessage;

  const DownloadProgressEvent({
    required this.taskId,
    required this.progress,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.status,
    this.errorMessage,
  });
}

/// Isolate 下载指令
class _DownloadCommand {
  final String type; // 'start', 'pause', 'cancel', 'shutdown'
  final String taskId;
  final Map<String, dynamic>? data;

  _DownloadCommand({
    required this.type,
    required this.taskId,
    this.data,
  });
}

/// Isolate 下载消息
class _DownloadMessage {
  final String taskId;
  final double progress;
  final int downloadedBytes;
  final int totalBytes;
  final String status; // 'downloading', 'completed', 'failed', 'paused'
  final String? errorMessage;

  _DownloadMessage({
    required this.taskId,
    required this.progress,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.status,
    this.errorMessage,
  });

  factory _DownloadMessage.fromMap(Map<String, dynamic> map) {
    try {
      return _DownloadMessage(
        taskId: (map['taskId'] as String?) ?? '',
        progress: ((map['progress'] as num?) ?? 0.0).toDouble(),
        downloadedBytes: (map['downloadedBytes'] as int?) ?? 0,
        totalBytes: (map['totalBytes'] as int?) ?? 0,
        status: (map['status'] as String?) ?? 'failed',
        errorMessage: map['errorMessage'] as String?,
      );
    } catch (e) {
      debugPrint('Failed to parse _DownloadMessage: $e, map: $map');
      rethrow;
    }
  }

  Map<String, dynamic> toMap() => {
        'taskId': taskId,
        'progress': progress,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        'status': status,
        'errorMessage': errorMessage,
      };
}

/// 高性能视频下载服务
///
/// 特性：
/// 1. 下载任务在独立 Isolate 中执行，不阻塞 UI
/// 2. M3U8 流支持并发 TS 片段下载（默认并发数：4）
/// 3. 使用流式写入减少内存占用
/// 4. 独立的 Dio 实例，与播放器网络资源隔离
class HighPerformanceDownloadService {
  static final HighPerformanceDownloadService _instance =
      HighPerformanceDownloadService._internal();

  factory HighPerformanceDownloadService() => _instance;

  HighPerformanceDownloadService._internal();

  // 任务管理
  final Map<String, DownloadTask> _tasks = {};
  final Map<String, StreamController<DownloadProgressEvent>>
      _progressControllers = {};

  // Isolate 相关
  Isolate? _isolate;
  SendPort? _isolateSendPort;
  final ReceivePort _mainReceivePort = ReceivePort();
  final StreamController<_DownloadMessage> _isolateMessageController =
      StreamController<_DownloadMessage>.broadcast();

  bool _isInitialized = false;
  bool _isInitializing = false;
  bool _receivePortHasListener = false;
  final _initCompleter = Completer<void>();

  /// 初始化服务（自动在第一次使用时调用）
  Future<void> _initialize() async {
    if (_isInitialized) return;
    if (_isInitializing) return _initCompleter.future;

    _isInitializing = true;
    // 初始化 Isolate（日志仅在错误时输出）

    try {
      // 监听来自 Isolate 的消息（只监听一次）
      if (!_receivePortHasListener) {
        _mainReceivePort.listen(_handleIsolateMessage);
        _receivePortHasListener = true;
      }

      // 启动下载 Isolate（如果还没启动）
      if (_isolate == null) {
        // 启动 Isolate
        _isolate = await Isolate.spawn(
          _downloadIsolateEntry,
          _mainReceivePort.sendPort,
          debugName: 'DownloadIsolate',
        );
      }

      // 等待 Isolate 初始化完成
      // 等待 Isolate 就绪
      await _initCompleter.future;
      _isInitialized = true;
      _isInitializing = false;
      // Isolate 初始化完成
    } catch (e) {
      debugPrint('[下载] Isolate 初始化失败');
      if (!_initCompleter.isCompleted) {
        _initCompleter.completeError(e);
      }
      // 重置状态，允许重试
      _isInitializing = false;
    }
  }

  /// 处理来自 Isolate 的消息
  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      // Isolate 初始化完成，获取 SendPort
      _isolateSendPort = message;
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
    } else if (message is Map) {
      // 处理下载进度消息（使用 try-catch 防止解析错误）
      try {
        final messageMap = Map<String, dynamic>.from(message);
        final downloadMsg = _DownloadMessage.fromMap(messageMap);
        _isolateMessageController.add(downloadMsg);
        _updateTaskFromMessage(downloadMsg);
      } catch (e) {
        debugPrint('Failed to handle isolate message: $e, message: $message');
      }
    } else {
      debugPrint('Unknown message type from isolate: ${message.runtimeType}');
    }
  }

  /// 根据消息更新任务状态
  void _updateTaskFromMessage(_DownloadMessage message) {
    final task = _tasks[message.taskId];
    if (task == null) return;

    final status = DownloadStatus.values.firstWhere(
      (e) => e.name == message.status,
      orElse: () => DownloadStatus.failed,
    );

    final updatedTask = task.copyWith(
      progress: message.progress,
      downloadedBytes: message.downloadedBytes,
      totalBytes: message.totalBytes,
      status: status,
      errorMessage: message.errorMessage,
    );

    _tasks[message.taskId] = updatedTask;

    // 通知进度监听器（控制器生命周期由服务管理）
    // ignore: close_sinks
    final controller = _progressControllers[message.taskId];
    if (controller == null) {
      // 无进度控制器
      return;
    }
    if (controller.isClosed) {
      // 控制器已关闭
      return;
    }

    // 发送进度到 UI
    controller.add(DownloadProgressEvent(
      taskId: message.taskId,
      progress: message.progress,
      downloadedBytes: message.downloadedBytes,
      totalBytes: message.totalBytes,
      status: status,
      errorMessage: message.errorMessage,
    ));
  }

  /// 生成任务 ID
  String _generateTaskId(String url) {
    final hash = url.hashCode.abs().toRadixString(36);
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return '${hash}_$timestamp';
  }

  /// 判断 URL 是否为 M3U8 格式
  bool _isM3u8Url(String url) {
    final lowerUrl = url.toLowerCase();
    // 检查是否包含 .m3u8（包括带查询参数的情况）
    return lowerUrl.contains('.m3u8') ||
        // 或者内容类型为 application/vnd.apple.mpegurl
        lowerUrl.contains('mpegurl');
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

  /// 开始下载
  ///
  /// [externalTaskId] 外部传入的任务ID，用于与 AdvancedDownloadManager 保持一致
  Future<DownloadTask?> startDownload({
    required String url,
    required String fileName,
    Map<String, String>? headers,
    String? episodeInfo,
    String? externalTaskId, // 外部任务ID
  }) async {
    await _initialize();

    // 检查是否已有相同 URL 的任务
    final existingTask = _findTaskByUrl(url);
    if (existingTask != null) {
      if (existingTask.status == DownloadStatus.downloading ||
          existingTask.status == DownloadStatus.completed) {
        return existingTask;
      }
      // 如果任务已存在但不是下载中/已完成，先清理旧任务
      await _cleanupTask(existingTask.id);
    }

    try {
      // 确保 Isolate 完全初始化（带超时）
      await _initCompleter.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw Exception('Isolate 初始化超时'),
      );

      if (_isolateSendPort == null) {
        debugPrint('错误: Isolate 未初始化');
        return null;
      }

      // 使用外部传入的 taskId（如果有），否则生成新的
      final taskId = externalTaskId ?? _generateTaskId(url);
      final dir = await _getDownloadDirectory();
      final tempDir = await _getTempDirectory();

      // 构建最终文件名
      String finalName = fileName;
      if (episodeInfo != null && episodeInfo.isNotEmpty) {
        final ext = fileName.contains('.')
            ? fileName.substring(fileName.lastIndexOf('.'))
            : '.mp4';
        final base = fileName.substring(
          0,
          fileName.lastIndexOf('.') > 0
              ? fileName.lastIndexOf('.')
              : fileName.length,
        );
        finalName = '${base.trim()}-$episodeInfo$ext';
      }

      final filePath = path.join(dir.path, finalName);
      final tempFilePath = path.join(tempDir.path, '${taskId}_$finalName');
      final isM3u8 = _isM3u8Url(url);

      final task = DownloadTask(
        id: taskId,
        url: url,
        fileName: finalName,
        filePath: filePath,
        tempFilePath: tempFilePath,
        isM3u8: isM3u8,
      );

      _tasks[taskId] = task;

      // 创建进度流控制器（生命周期由服务管理，在 dispose 时统一关闭）
      // ignore: close_sinks
      final progressController =
          StreamController<DownloadProgressEvent>.broadcast();
      _progressControllers[taskId] = progressController;

      // 发送下载命令到 Isolate
      _isolateSendPort!.send(_DownloadCommand(
        type: 'start',
        taskId: taskId,
        data: {
          'url': url,
          'tempFilePath': tempFilePath,
          'headers': headers,
          'isM3u8': isM3u8,
        },
      ).toMap());

      return task;
    } catch (e, st) {
      debugPrint('启动下载失败: $e\n$st');
      return null;
    }
  }

  /// 通过 URL 查找任务
  DownloadTask? _findTaskByUrl(String url) {
    for (final task in _tasks.values) {
      if (task.url == url) return task;
    }
    return null;
  }

  /// 获取任务
  DownloadTask? getTask(String taskId) => _tasks[taskId];

  /// 通过 URL 获取任务
  DownloadTask? getTaskByUrl(String url) => _findTaskByUrl(url);

  /// 获取所有任务
  List<DownloadTask> getAllTasks() => _tasks.values.toList();

  /// 获取任务进度流
  Stream<DownloadProgressEvent>? getProgressStream(String taskId) {
    return _progressControllers[taskId]?.stream;
  }

  /// 暂停下载
  Future<void> pauseDownload(String taskId) async {
    if (!_tasks.containsKey(taskId)) return;

    // 确保 Isolate 已初始化
    if (_isolateSendPort == null) return;

    _isolateSendPort!.send(_DownloadCommand(
      type: 'pause',
      taskId: taskId,
    ).toMap());
  }

  /// 恢复下载（新 API，需要完整参数）
  ///
  /// 注意：恢复下载需要传入完整的任务信息，因为 Isolate 中的任务可能已被清理
  Future<void> resumeDownload({
    required String taskId,
    required String url,
    required String tempFilePath,
    required bool isM3u8,
    Map<String, String>? headers,
  }) async {
    // 恢复下载

    // 先启动 Isolate（如果还没启动）- 不等待，只触发启动
    unawaited(_initialize());

    // 等待 Isolate 完全初始化（带超时）
    try {
      await _initCompleter.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('[下载] 错误: Isolate 初始化超时');
          return;
        },
      );
    } catch (e) {
      debugPrint('[下载] 错误: Isolate 初始化失败');
      return;
    }

    if (_isolateSendPort == null) {
      debugPrint('[下载] 错误: Isolate 未初始化');
      return;
    }

    // 如果任务已存在且正在下载，直接返回
    final existingTask = _tasks[taskId];
    if (existingTask != null &&
        existingTask.status == DownloadStatus.downloading) {
      // 任务已在下载中
      return;
    }

    // 如果任务不存在，创建一个（用于应用重启后的恢复）
    if (existingTask == null) {
      // 创建新任务

      // 正确处理 Windows 路径，提取文件名
      // path.basename 对 Windows 反斜杠路径处理不正确，需要手动处理
      final fileName = tempFilePath.contains('\\')
          ? tempFilePath.split('\\').last
          : tempFilePath.split('/').last;

      if (fileName.isEmpty) {
        debugPrint('[下载] 错误: 无法从路径提取文件名');
        return;
      }

      final dir = await _getDownloadDirectory();
      // 使用平台特定的路径分隔符
      final separator = Platform.pathSeparator;
      final filePath = '${dir.path}$separator$fileName';

      // 文件名提取成功

      final task = DownloadTask(
        id: taskId,
        url: url,
        fileName: fileName,
        filePath: filePath,
        tempFilePath: tempFilePath,
        isM3u8: isM3u8,
      );
      _tasks[taskId] = task;
    }

    // 确保进度控制器存在（任务恢复时需要重新创建）
    // ignore: close_sinks
    var controller = _progressControllers[taskId];
    if (controller == null || controller.isClosed) {
      // 创建/重建进度控制器
      // ignore: close_sinks
      controller = StreamController<DownloadProgressEvent>.broadcast();
      _progressControllers[taskId] = controller;
    }

    // 发送 resume 命令到 Isolate
    _isolateSendPort!.send(_DownloadCommand(
      type: 'resume',
      taskId: taskId,
      data: {
        'url': url,
        'tempFilePath': tempFilePath,
        'headers': headers,
        'isM3u8': isM3u8,
      },
    ).toMap());
  }

  /// 恢复下载（旧 API，仅用于兼容，需要任务已存在）
  @Deprecated('使用新 API resumeDownload({taskId, url, tempFilePath, isM3u8})')
  Future<void> resumeDownloadLegacy(String taskId) async {
    if (!_tasks.containsKey(taskId)) return;

    final task = _tasks[taskId];
    if (task == null) return;

    _isolateSendPort?.send(_DownloadCommand(
      type: 'resume',
      taskId: taskId,
      data: {
        'url': task.url,
        'tempFilePath': task.tempFilePath,
        'isM3u8': task.isM3u8,
      },
    ).toMap());
  }

  /// 取消下载
  Future<void> cancelDownload(String taskId) async {
    if (!_tasks.containsKey(taskId)) return;

    // 确保 Isolate 已初始化
    if (_isolateSendPort == null) {
      // Isolate 未初始化，直接清理资源
      await _cleanupTask(taskId);
      return;
    }

    _isolateSendPort!.send(_DownloadCommand(
      type: 'cancel',
      taskId: taskId,
    ).toMap());

    // 清理资源
    await _cleanupTask(taskId);
  }

  /// 清理任务资源
  Future<void> _cleanupTask(String taskId) async {
    final task = _tasks[taskId];
    if (task != null) {
      // 删除临时文件
      final tempFile = File(task.tempFilePath);
      if (tempFile.existsSync()) {
        try {
          await tempFile.delete();
        } catch (e) {
          debugPrint('删除临时文件失败: $e');
        }
      }
    }

    _tasks.remove(taskId);

    final controller = _progressControllers[taskId];
    if (controller != null && !controller.isClosed) {
      await controller.close();
    }
    _progressControllers.remove(taskId);
  }

  /// 另存为
  Future<String?> saveAs(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return null;

    final tempFile = File(task.tempFilePath);
    if (!tempFile.existsSync()) return null;

    try {
      final dir = await _getDownloadDirectory();

      // 处理文件名冲突
      var targetPath = path.join(dir.path, task.fileName);
      var counter = 1;
      final ext = path.extension(task.fileName);
      final baseName = path.basenameWithoutExtension(task.fileName);

      while (File(targetPath).existsSync()) {
        targetPath = path.join(dir.path, '${baseName}_$counter$ext');
        counter++;
      }

      // 复制文件
      await tempFile.copy(targetPath);

      // 更新任务路径
      _tasks[taskId] = task.copyWith(filePath: targetPath);

      debugPrint('文件已保存到: $targetPath');
      return targetPath;
    } catch (e) {
      debugPrint('保存文件失败: $e');
      return null;
    }
  }

  /// 自动保存（移动临时文件到目标位置）
  Future<String?> autoSave(String taskId) async {
    final task = _tasks[taskId];
    if (task == null) return null;

    final tempFile = File(task.tempFilePath);
    if (!tempFile.existsSync()) return null;

    try {
      final dir = await _getDownloadDirectory();

      // 处理文件名冲突
      var targetPath = path.join(dir.path, task.fileName);
      var counter = 1;
      final ext = path.extension(task.fileName);
      final baseName = path.basenameWithoutExtension(task.fileName);

      while (File(targetPath).existsSync()) {
        targetPath = path.join(dir.path, '${baseName}_$counter$ext');
        counter++;
      }

      // 移动文件（使用 copy + delete 支持跨磁盘）
      await tempFile.copy(targetPath);
      await tempFile.delete();

      // 更新任务路径
      _tasks[taskId] = task.copyWith(filePath: targetPath);

      debugPrint('文件已自动保存到: $targetPath');
      return targetPath;
    } catch (e) {
      debugPrint('自动保存失败: $e');
      return null;
    }
  }

  /// 释放资源
  Future<void> dispose() async {
    // 发送关闭命令到 Isolate
    _isolateSendPort?.send(_DownloadCommand(
      type: 'shutdown',
      taskId: '',
    ).toMap());

    // 关闭所有流控制器
    for (final controller in _progressControllers.values) {
      if (!controller.isClosed) {
        await controller.close();
      }
    }
    _progressControllers.clear();

    // 关闭消息控制器
    await _isolateMessageController.close();

    // 关闭接收端口
    _mainReceivePort.close();

    // 终止 Isolate
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _isolateSendPort = null;
    _isInitialized = false;
  }
}

/// 扩展方法，将命令转换为 Map
extension on _DownloadCommand {
  Map<String, dynamic> toMap() => {
        'type': type,
        'taskId': taskId,
        'data': data,
      };
}

/// Isolate 入口函数
///
/// 在独立线程中执行，不阻塞 UI
void _downloadIsolateEntry(SendPort mainSendPort) {
  print('[Isolate] 启动...');

  final receivePort = ReceivePort();
  print('[Isolate] 发送 SendPort 到主线程');
  mainSendPort.send(receivePort.sendPort);

  // 下载任务管理
  final Map<String, _IsolateDownloadTask> tasks = {};

  print('[Isolate] 创建 Dio 实例...');
  // 创建独立的 Dio 实例
  final dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'User-Agent': 'Mozilla/5.0'},
  ));
  print('[Isolate] Dio 实例创建完成，开始监听消息');

  receivePort.listen((message) async {
    if (message is Map) {
      _DownloadCommand? command;
      try {
        final messageMap = Map<String, dynamic>.from(message);
        command = _DownloadCommand(
          type: (messageMap['type'] as String?) ?? '',
          taskId: (messageMap['taskId'] as String?) ?? '',
          data: messageMap['data'] as Map<String, dynamic>?,
        );

        if (command.type.isEmpty || command.taskId.isEmpty) {
          print(
              '[Isolate] Invalid command: type=${command.type}, taskId=${command.taskId}');
          return;
        }

        switch (command.type) {
          case 'start':
            await _handleStartDownload(
              command: command,
              dio: dio,
              tasks: tasks,
              mainSendPort: mainSendPort,
            );
            break;
          case 'pause':
            await _handlePauseDownload(
              command: command,
              tasks: tasks,
              mainSendPort: mainSendPort,
            );
            break;
          case 'resume':
            await _handleResumeDownload(
              command: command,
              dio: dio,
              tasks: tasks,
              mainSendPort: mainSendPort,
            );
            break;
          case 'cancel':
            await _handleCancelDownload(
              command: command,
              tasks: tasks,
              mainSendPort: mainSendPort,
            );
            break;
          case 'shutdown':
            await _handleShutdown(
              dio: dio,
              tasks: tasks,
              receivePort: receivePort,
            );
            break;
          default:
            print('[Isolate] Unknown command type: ${command.type}');
        }
      } catch (e) {
        final taskId = command?.taskId ?? 'unknown';
        print(
            '[Isolate] Error handling command ${command?.type ?? "unknown"}: $e');
        // 发送错误消息回主 Isolate
        mainSendPort.send(_DownloadMessage(
          taskId: taskId,
          progress: 0.0,
          downloadedBytes: 0,
          totalBytes: 0,
          status: 'failed',
          errorMessage: 'Command execution failed: $e',
        ).toMap());
      }
    }
  });
}

/// Isolate 中的下载任务
class _IsolateDownloadTask {
  final String taskId;
  final String url;
  final String tempFilePath;
  final Map<String, dynamic>? headers;
  final bool isM3u8;
  final CancelToken cancelToken;
  bool isPaused = false;
  bool isCancelled = false;

  _IsolateDownloadTask({
    required this.taskId,
    required this.url,
    required this.tempFilePath,
    this.headers,
    required this.isM3u8,
    required this.cancelToken,
  });
}

/// 处理开始下载
Future<void> _handleStartDownload({
  required _DownloadCommand command,
  required Dio dio,
  required Map<String, _IsolateDownloadTask> tasks,
  required SendPort mainSendPort,
}) async {
  final data = command.data!;
  final url = data['url'] as String? ?? '';
  final tempFilePath = data['tempFilePath'] as String? ?? '';
  final headers = data['headers'] as Map<String, dynamic>?;
  final isM3u8 = data['isM3u8'] as bool? ?? false;

  if (url.isEmpty || tempFilePath.isEmpty) {
    print('[Isolate] 开始下载失败: url或tempFilePath为空');
    return;
  }

  final cancelToken = CancelToken();
  final task = _IsolateDownloadTask(
    taskId: command.taskId,
    url: url,
    tempFilePath: tempFilePath,
    headers: headers,
    isM3u8: isM3u8,
    cancelToken: cancelToken,
  );

  tasks[command.taskId] = task;

  try {
    if (isM3u8) {
      await _downloadM3u8(
        task: task,
        dio: dio,
        mainSendPort: mainSendPort,
      );
    } else {
      await _downloadRegularFile(
        task: task,
        dio: dio,
        mainSendPort: mainSendPort,
      );
    }
  } catch (e) {
    print('[Isolate] 下载错误: $e');
    if (!task.isCancelled && !task.isPaused) {
      mainSendPort.send(_DownloadMessage(
        taskId: command.taskId,
        progress: 0.0,
        downloadedBytes: 0,
        totalBytes: 0,
        status: 'failed',
        errorMessage: e.toString(),
      ).toMap());
    }
  } finally {
    tasks.remove(command.taskId);
  }
}

/// 处理暂停下载
Future<void> _handlePauseDownload({
  required _DownloadCommand command,
  required Map<String, _IsolateDownloadTask> tasks,
  required SendPort mainSendPort,
}) async {
  final task = tasks[command.taskId];
  if (task != null) {
    task.isPaused = true;

    // 安全地取消令牌
    try {
      if (!task.cancelToken.isCancelled) {
        task.cancelToken.cancel();
      }
    } catch (_) {}

    mainSendPort.send(_DownloadMessage(
      taskId: command.taskId,
      progress: 0.0,
      downloadedBytes: 0,
      totalBytes: 0,
      status: 'paused',
    ).toMap());
  }
}

/// 处理恢复下载（支持断点续传）
Future<void> _handleResumeDownload({
  required _DownloadCommand command,
  required Dio dio,
  required Map<String, _IsolateDownloadTask> tasks,
  required SendPort mainSendPort,
}) async {
  final data = command.data!;
  final url = data['url'] as String? ?? '';
  final tempFilePath = data['tempFilePath'] as String? ?? '';
  final headers = data['headers'] as Map<String, dynamic>?;
  final isM3u8 = data['isM3u8'] as bool? ?? false;

  if (url.isEmpty || tempFilePath.isEmpty) {
    print('[Isolate] 恢复下载失败: url或tempFilePath为空');
    return;
  }

  print(
      '[Isolate] _handleResumeDownload: url=$url, tempFilePath=$tempFilePath');

  // 检查临时文件大小，用于断点续传
  var resumeByte = 0;
  final tempFile = File(tempFilePath);
  if (tempFile.existsSync()) {
    resumeByte = await tempFile.length();
    print('[Isolate] 临时文件存在，大小: $resumeByte bytes');
  } else {
    print('[Isolate] 临时文件不存在，从头开始下载');
  }

  final cancelToken = CancelToken();
  final task = _IsolateDownloadTask(
    taskId: command.taskId,
    url: url,
    tempFilePath: tempFilePath,
    headers: headers,
    isM3u8: isM3u8,
    cancelToken: cancelToken,
  );

  tasks[command.taskId] = task;

  try {
    print('[Isolate] 开始下载，isM3u8=$isM3u8');

    // 添加 Range header 用于断点续传
    final resumeHeaders = Map<String, dynamic>.from(headers ?? {});
    if (resumeByte > 0) {
      resumeHeaders['Range'] = 'bytes=$resumeByte-';
      print('[Isolate] 添加 Range header: bytes=$resumeByte-');
    }

    if (isM3u8) {
      await _downloadM3u8(
        task: task,
        dio: dio,
        mainSendPort: mainSendPort,
      );
    } else {
      await _downloadRegularFileWithResume(
        task: task,
        dio: dio,
        mainSendPort: mainSendPort,
        resumeByte: resumeByte,
        headers: resumeHeaders,
      );
    }
  } catch (e) {
    if (!task.isCancelled && !task.isPaused) {
      mainSendPort.send(_DownloadMessage(
        taskId: command.taskId,
        progress: 0.0,
        downloadedBytes: 0,
        totalBytes: 0,
        status: 'failed',
        errorMessage: e.toString(),
      ).toMap());
    }
  } finally {
    tasks.remove(command.taskId);
  }
}

/// 下载普通文件（支持断点续传）
Future<void> _downloadRegularFileWithResume({
  required _IsolateDownloadTask task,
  required Dio dio,
  required SendPort mainSendPort,
  required int resumeByte,
  required Map<String, dynamic> headers,
}) async {
  print('[Isolate] _downloadRegularFileWithResume: url=${task.url}');

  // 确保临时目录存在
  final tempFile = File(task.tempFilePath);
  final parentDir = tempFile.parent;
  if (!parentDir.existsSync()) {
    print('[Isolate] 创建临时目录: ${parentDir.path}');
    await parentDir.create(recursive: true);
  }

  // 转换 headers 类型
  final stringHeaders = <String, String>{};
  headers.forEach((key, value) {
    stringHeaders[key] = value?.toString() ?? '';
  });

  print('[Isolate] 发送 HEAD 请求获取文件大小...');

  // 获取文件大小
  final headRes = await dio.head<dynamic>(
    task.url,
    options: Options(headers: stringHeaders),
    cancelToken: task.cancelToken,
  );

  final totalBytes = int.tryParse(
        headRes.headers.value('content-length') ?? '0',
      ) ??
      0;

  print('[Isolate] 文件大小: $totalBytes bytes');

  var downloadedBytes = resumeByte;
  final actualTotal =
      totalBytes > 0 ? resumeByte + totalBytes : downloadedBytes;

  // 发送初始进度
  mainSendPort.send(_DownloadMessage(
    taskId: task.taskId,
    progress: actualTotal > 0 ? downloadedBytes / actualTotal : 0.0,
    downloadedBytes: downloadedBytes,
    totalBytes: actualTotal,
    status: 'downloading',
  ).toMap());

  try {
    // 使用 dio.download 下载文件
    await dio.download(
      task.url,
      task.tempFilePath,
      options: Options(
        headers: stringHeaders,
        receiveTimeout: const Duration(minutes: 30),
      ),
      cancelToken: task.cancelToken,
      onReceiveProgress: (received, total) {
        if (task.isPaused || task.isCancelled) return;

        downloadedBytes = resumeByte + received;
        final currentTotal = total > 0 ? resumeByte + total : downloadedBytes;
        final progress =
            currentTotal > 0 ? downloadedBytes / currentTotal : 0.0;

        mainSendPort.send(_DownloadMessage(
          taskId: task.taskId,
          progress: progress,
          downloadedBytes: downloadedBytes,
          totalBytes: currentTotal,
          status: 'downloading',
        ).toMap());
      },
    );

    if (!task.isPaused && !task.isCancelled) {
      print('[Isolate] 下载完成');
      mainSendPort.send(_DownloadMessage(
        taskId: task.taskId,
        progress: 1.0,
        downloadedBytes: downloadedBytes,
        totalBytes: totalBytes > 0 ? resumeByte + totalBytes : downloadedBytes,
        status: 'completed',
      ).toMap());
    }
  } on DioException catch (e) {
    // 取消操作是预期的，不发送错误
    if (e.type == DioExceptionType.cancel) {
      print('[Isolate] 下载被取消');
      return;
    }
    print('[Isolate] DioException: ${e.type} - ${e.message}');
    rethrow;
  }
}

/// 处理取消下载
Future<void> _handleCancelDownload({
  required _DownloadCommand command,
  required Map<String, _IsolateDownloadTask> tasks,
  required SendPort mainSendPort,
}) async {
  final task = tasks[command.taskId];
  if (task != null) {
    task.isCancelled = true;

    // 安全地取消令牌
    try {
      if (!task.cancelToken.isCancelled) {
        task.cancelToken.cancel();
      }
    } catch (_) {}

    // 删除临时文件
    final tempFile = File(task.tempFilePath);
    if (tempFile.existsSync()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }

    tasks.remove(command.taskId);
  }
}

/// 处理关闭 Isolate
Future<void> _handleShutdown({
  required Dio dio,
  required Map<String, _IsolateDownloadTask> tasks,
  required ReceivePort receivePort,
}) async {
  // 取消所有任务
  for (final task in tasks.values) {
    task.isCancelled = true;

    // 安全地取消令牌
    try {
      if (!task.cancelToken.isCancelled) {
        task.cancelToken.cancel();
      }
    } catch (_) {}

    // 删除临时文件
    final tempFile = File(task.tempFilePath);
    if (tempFile.existsSync()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }
  tasks.clear();

  // 关闭 Dio
  dio.close();

  // 关闭接收端口
  receivePort.close();

  // 退出 Isolate
  Isolate.exit();
}

/// 下载普通文件
Future<void> _downloadRegularFile({
  required _IsolateDownloadTask task,
  required Dio dio,
  required SendPort mainSendPort,
}) async {
  // 确保临时目录存在
  final tempFile = File(task.tempFilePath);
  final parentDir = tempFile.parent;
  if (!parentDir.existsSync()) {
    await parentDir.create(recursive: true);
  }

  // 转换 headers 类型
  final stringHeaders = <String, String>{};
  task.headers?.forEach((key, value) {
    stringHeaders[key] = value?.toString() ?? '';
  });

  // 获取文件大小
  final headRes = await dio.head<dynamic>(
    task.url,
    options: Options(headers: stringHeaders),
    cancelToken: task.cancelToken,
  );

  final totalBytes = int.tryParse(
        headRes.headers.value('content-length') ?? '0',
      ) ??
      0;

  int downloadedBytes = 0;

  try {
    await dio.download(
      task.url,
      task.tempFilePath,
      options: Options(
        headers: stringHeaders,
        receiveTimeout: const Duration(minutes: 30),
      ),
      cancelToken: task.cancelToken,
      onReceiveProgress: (received, total) {
        if (task.isPaused || task.isCancelled) return;

        downloadedBytes = received;
        final progress = total > 0 ? received / total : 0.0;

        mainSendPort.send(_DownloadMessage(
          taskId: task.taskId,
          progress: progress,
          downloadedBytes: received,
          totalBytes: total > 0 ? total : received,
          status: 'downloading',
        ).toMap());
      },
    );
  } on DioException catch (e) {
    // 取消操作是预期的，不发送错误
    if (e.type == DioExceptionType.cancel) {
      return;
    }
    rethrow;
  }

  if (!task.isPaused && !task.isCancelled) {
    mainSendPort.send(_DownloadMessage(
      taskId: task.taskId,
      progress: 1.0,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes > 0 ? totalBytes : downloadedBytes,
      status: 'completed',
    ).toMap());
  }
}

/// M3U8 片段信息
class _HlsSegment {
  final String url;
  final int durationMs;
  final int? byteRangeLength;
  final int? byteRangeOffset;
  final String? keyUri;
  final List<int>? iv;
  final int sequenceNumber;

  _HlsSegment({
    required this.url,
    required this.durationMs,
    this.byteRangeLength,
    this.byteRangeOffset,
    this.keyUri,
    this.iv,
    required this.sequenceNumber,
  });
}

/// 并发下载结果
class _SegmentDownloadResult {
  final int index;
  final List<int> data;
  final bool success;
  final String? error;

  _SegmentDownloadResult({
    required this.index,
    required this.data,
    this.success = true,
    this.error,
  });
}

/// 下载 M3U8 视频流
Future<void> _downloadM3u8({
  required _IsolateDownloadTask task,
  required Dio dio,
  required SendPort mainSendPort,
}) async {
  print('[Isolate] _downloadM3u8: url=${task.url}');

  // 解析 M3U8 播放列表
  final (segments, baseUrl) = await _resolveM3u8Playlist(
    task.url,
    dio,
    task.headers?.cast<String, String>(),
    task.cancelToken,
  );

  print('[Isolate] M3U8 解析完成: ${segments.length} 个片段');

  if (segments.isEmpty) {
    throw Exception('No TS segments found');
  }

  // 确保临时目录存在
  final outputFile = File(task.tempFilePath);
  final parentDir = outputFile.parent;
  if (!parentDir.existsSync()) {
    await parentDir.create(recursive: true);
  }

  // 创建输出文件
  if (outputFile.existsSync()) {
    await outputFile.delete();
  }

  // 并发下载配置
  const maxConcurrency = 4; // 最大并发数
  final keyCache = <String, List<int>>{};
  var totalDownloadedBytes = 0;

  // 创建进度跟踪
  final downloadedSegments = List<bool>.filled(segments.length, false);

  print('[Isolate] 开始下载 ${segments.length} 个片段...');

  // 分段并发下载
  for (var i = 0; i < segments.length; i += maxConcurrency) {
    if (task.isPaused || task.isCancelled) break;

    final endIndex = (i + maxConcurrency < segments.length)
        ? i + maxConcurrency
        : segments.length;

    print('[Isolate] 下载批次 $i-${endIndex - 1} / ${segments.length}');

    // 并发下载当前批次的片段
    final futures = <Future<_SegmentDownloadResult>>[];
    for (var j = i; j < endIndex; j++) {
      futures.add(_downloadSegment(
        index: j,
        segment: segments[j],
        baseUrl: baseUrl,
        dio: dio,
        headers: task.headers?.cast<String, String>(),
        cancelToken: task.cancelToken,
        keyCache: keyCache,
      ));
    }

    // 等待当前批次完成
    final results = await Future.wait(futures);
    print(
        '[Isolate] 批次 $i-${endIndex - 1} 完成，成功 ${results.where((r) => r.success).length}/${results.length}');

    // 按顺序写入文件
    final sink = outputFile.openWrite(mode: FileMode.append);
    try {
      for (var k = 0; k < results.length; k++) {
        final result = results[k];
        final segmentIndex = i + k;

        if (!result.success) {
          throw Exception(
              'Failed to download segment $segmentIndex: ${result.error}');
        }

        sink.add(result.data);
        totalDownloadedBytes += result.data.length;
        downloadedSegments[segmentIndex] = true;
      }
    } finally {
      await sink.close();
    }

    // 发送进度更新
    final progress = endIndex / segments.length;
    print(
        '[Isolate] 发送进度: ${(progress * 100).toStringAsFixed(1)}%, 已下载: ${totalDownloadedBytes ~/ 1024} KB');
    mainSendPort.send(_DownloadMessage(
      taskId: task.taskId,
      progress: progress,
      downloadedBytes: totalDownloadedBytes,
      totalBytes: totalDownloadedBytes ~/ progress,
      status: 'downloading',
    ).toMap());
  }

  if (!task.isPaused && !task.isCancelled) {
    mainSendPort.send(_DownloadMessage(
      taskId: task.taskId,
      progress: 1.0,
      downloadedBytes: totalDownloadedBytes,
      totalBytes: totalDownloadedBytes,
      status: 'completed',
    ).toMap());
  }
}

/// 下载单个 TS 片段
Future<_SegmentDownloadResult> _downloadSegment({
  required int index,
  required _HlsSegment segment,
  required String baseUrl,
  required Dio dio,
  required Map<String, String>? headers,
  required CancelToken cancelToken,
  required Map<String, List<int>> keyCache,
}) async {
  try {
    // 每 100 个片段打印一次日志，避免日志过多
    if (index % 100 == 0) {
      print(
          '[Isolate] 下载片段 $index: ${segment.url.substring(0, segment.url.length > 50 ? 50 : segment.url.length)}...');
    }

    // 下载密钥（如果需要）
    List<int>? keyBytes;
    if (segment.keyUri != null) {
      if (!keyCache.containsKey(segment.keyUri!)) {
        final keyUrl = _resolveUrl(baseUrl, segment.keyUri!);
        final keyRes = await dio.get<List<int>>(
          keyUrl,
          options: Options(
            responseType: ResponseType.bytes,
            headers: headers,
          ),
          cancelToken: cancelToken,
        );
        keyCache[segment.keyUri!] = keyRes.data!;
      }
      keyBytes = keyCache[segment.keyUri!];
    }

    // 构建 TS 请求
    final tsUrl = _resolveUrl(baseUrl, segment.url);
    final opts = Options(headers: Map<String, String>.from(headers ?? {}));

    if (segment.byteRangeLength != null) {
      final start = segment.byteRangeOffset ?? 0;
      final end = start + segment.byteRangeLength! - 1;
      opts.headers?['Range'] = 'bytes=$start-$end';
    }

    // 下载 TS 片段
    final tsRes = await dio.get<List<int>>(
      tsUrl,
      options: opts..responseType = ResponseType.bytes,
      cancelToken: cancelToken,
    );

    var segmentData = tsRes.data!;

    // 解密（如果需要）
    if (keyBytes != null) {
      segmentData = _decryptAes128Cbc(
        segmentData,
        keyBytes,
        segment.iv ?? _generateIvFromSequence(segment.sequenceNumber),
      );
    }

    return _SegmentDownloadResult(
      index: index,
      data: segmentData,
    );
  } catch (e) {
    return _SegmentDownloadResult(
      index: index,
      data: const [],
      success: false,
      error: e.toString(),
    );
  }
}

/// 解析 M3U8 播放列表
Future<(List<_HlsSegment>, String)> _resolveM3u8Playlist(
  String url,
  Dio dio,
  Map<String, String>? headers,
  CancelToken cancelToken,
) async {
  print('[Isolate] 解析 M3U8: $url');

  final res = await dio.get<String>(
    url,
    options: Options(
      responseType: ResponseType.plain,
      headers: headers,
      receiveTimeout: const Duration(seconds: 30),
    ),
    cancelToken: cancelToken,
  );

  print('[Isolate] M3U8 内容长度: ${res.data?.length ?? 0}');

  final content = res.data!;
  final baseUrl = _getBaseUrl(url);

  // 检查是否为主列表
  if (content.contains('#EXT-X-STREAM-INF:')) {
    final subUrl = _selectHighestBitrateStream(content, baseUrl);
    if (subUrl.isEmpty) {
      throw Exception('No valid stream found in master playlist');
    }
    return _resolveM3u8Playlist(subUrl, dio, headers, cancelToken);
  }

  return (_parseMediaPlaylist(content, baseUrl), baseUrl);
}

/// 选择最高码率流
String _selectHighestBitrateStream(String content, String baseUrl) {
  var bestUrl = '';
  var maxBandwidth = 0;
  final lines = content.split('\n');

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      final bwMatch = RegExp(r'BANDWIDTH=(\d+)').firstMatch(line);
      if (bwMatch != null) {
        final bw = int.parse(bwMatch.group(1)!);
        var j = i + 1;
        while (j < lines.length &&
            (lines[j].trim().isEmpty || lines[j].trim().startsWith('#'))) {
          j++;
        }
        if (j < lines.length && bw > maxBandwidth) {
          maxBandwidth = bw;
          bestUrl = _resolveUrl(baseUrl, lines[j].trim());
        }
      }
    }
  }

  return bestUrl;
}

/// 解析媒体列表
List<_HlsSegment> _parseMediaPlaylist(String content, String baseUrl) {
  final segments = <_HlsSegment>[];
  String? currentKeyUri;
  List<int>? currentIv;
  var currentDuration = 0;
  int? currentByteRangeLength;
  int? currentByteRangeOffset;
  var mediaSequence = 0;
  var segmentIndex = 0;

  final seqMatch = RegExp(r'#EXT-X-MEDIA-SEQUENCE:(\d+)').firstMatch(content);
  if (seqMatch != null) {
    mediaSequence = int.parse(seqMatch.group(1)!);
  }

  for (final line in content.split('\n')) {
    final trimmed = line.trim();

    if (trimmed.isEmpty || trimmed.startsWith('#EXT-X-')) {
      // 处理加密标签
      if (trimmed.startsWith('#EXT-X-KEY:')) {
        if (trimmed.contains('METHOD=AES-128')) {
          final uriMatch = RegExp(r'URI="([^"]+)"').firstMatch(trimmed);
          final ivMatch = RegExp(r'IV=0x([0-9a-fA-F]+)').firstMatch(trimmed);
          currentKeyUri = uriMatch?.group(1);

          if (ivMatch != null) {
            final hex = ivMatch.group(1)!;
            if (hex.length == 32) {
              currentIv = List<int>.generate(
                16,
                (i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16),
              );
            } else {
              currentIv = null;
            }
          } else {
            currentIv = null;
          }
        } else {
          currentKeyUri = null;
          currentIv = null;
        }
        continue;
      }

      // 处理字节范围
      if (trimmed.startsWith('#EXT-X-BYTERANGE:')) {
        final match = RegExp(r'(\d+)(?:@(\d+))?').firstMatch(trimmed);
        if (match != null) {
          currentByteRangeLength = int.parse(match.group(1)!);
          currentByteRangeOffset =
              match.group(2) != null ? int.parse(match.group(2)!) : null;
        }
        continue;
      }

      // 提取片段时长
      if (trimmed.startsWith('#EXTINF:')) {
        currentDuration =
            (double.parse(trimmed.split(':')[1].split(',').first) * 1000)
                .toInt();
        continue;
      }
    }

    // 提取 TS URL
    if (trimmed.isNotEmpty && !trimmed.startsWith('#')) {
      final absUrl = _resolveUrl(baseUrl, trimmed);
      segments.add(_HlsSegment(
        url: absUrl,
        durationMs: currentDuration,
        byteRangeLength: currentByteRangeLength,
        byteRangeOffset: currentByteRangeOffset,
        keyUri: currentKeyUri,
        iv: currentIv,
        sequenceNumber: mediaSequence + segmentIndex,
      ));
      segmentIndex++;
      currentByteRangeLength = null;
      currentByteRangeOffset = null;
    }
  }

  return segments;
}

/// 获取基础 URL
String _getBaseUrl(String url) {
  final uri = Uri.parse(url);
  final pathEnd = uri.path.lastIndexOf('/') + 1;
  return '${uri.scheme}://${uri.host}${uri.path.substring(0, pathEnd)}';
}

/// 解析相对 URL
String _resolveUrl(String baseUrl, String relative) {
  final trimmed = relative.trim();
  if (trimmed.startsWith('http')) return trimmed;
  if (trimmed.startsWith('//')) {
    final scheme = Uri.parse(baseUrl).scheme;
    return '$scheme:$trimmed';
  }
  if (trimmed.startsWith('/')) {
    final baseUri = Uri.parse(baseUrl);
    return '${baseUri.scheme}://${baseUri.host}$trimmed';
  }
  return '$baseUrl$trimmed';
}

/// 生成 IV
List<int> _generateIvFromSequence(int sequence) {
  final iv = List<int>.filled(16, 0);
  iv[12] = (sequence >> 24) & 0xFF;
  iv[13] = (sequence >> 16) & 0xFF;
  iv[14] = (sequence >> 8) & 0xFF;
  iv[15] = sequence & 0xFF;
  return iv;
}

/// AES-128 CBC 解密
///
/// 使用纯 Dart 实现的 AES 解密，可在 Isolate 中运行
Uint8List _decryptAes128Cbc(
  List<int> encrypted,
  List<int> key,
  List<int> iv,
) {
  return IsolateDecryptor.decryptAes128Cbc(encrypted, key, iv);
}
