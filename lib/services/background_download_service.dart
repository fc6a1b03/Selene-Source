import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:selene/models/download_task_persistent.dart';
import 'package:selene/services/advanced_download_manager.dart';

/// 后台下载服务
///
/// 负责在应用后台时保持下载并进行通知
class BackgroundDownloadService {
  static final BackgroundDownloadService _instance =
      BackgroundDownloadService._internal();

  factory BackgroundDownloadService() => _instance;

  BackgroundDownloadService._internal();

  /// 通知插件
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  /// 是否已初始化
  bool _isInitialized = false;

  /// 通知ID计数器
  int _notificationId = 1000;

  /// 任务ID到通知ID的映射
  final Map<String, int> _taskNotificationIds = {};

  /// 全局下载通知ID
  static const int _globalNotificationId = 999;

  /// 统计信息流订阅
  StreamSubscription<DownloadStatistics>? _statsSubscription;

  /// 当前统计信息
  DownloadStatistics _currentStats = const DownloadStatistics();

  /// 是否在显示全局通知
  bool _showingGlobalNotification = false;

  /// 初始化服务
  Future<void> initialize() async {
    if (_isInitialized) return;

    // Windows/Linux 平台不支持 flutter_local_notifications
    // 只初始化 Android 和 iOS/macOS
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      debugPrint('BackgroundDownloadService: 当前平台不支持本地通知');
      _isInitialized = true; // 标记为已初始化，避免重复尝试
      return;
    }

    try {
      // 初始化通知插件
      const initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const initializationSettingsDarwin = DarwinInitializationSettings();
      const initializationSettings = InitializationSettings(
        android: initializationSettingsAndroid,
        iOS: initializationSettingsDarwin,
        macOS: initializationSettingsDarwin,
      );

      await _notificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationResponse,
      );

      // 创建通知渠道（Android）
      if (Platform.isAndroid) {
        await _createNotificationChannels();
      }

      // 监听下载统计信息
      _statsSubscription =
          AdvancedDownloadManager().statisticsStream.listen(_onStatsUpdate);

      _isInitialized = true;
      debugPrint('BackgroundDownloadService 初始化完成');
    } catch (e) {
      debugPrint('BackgroundDownloadService 初始化失败: $e');
      // 即使失败也标记为已初始化，避免重复错误
      _isInitialized = true;
    }
  }

  /// 创建通知渠道
  Future<void> _createNotificationChannels() async {
    final androidPlugin =
        _notificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin == null) return;

    // 下载进度渠道
    const downloadChannel = AndroidNotificationChannel(
      'download_progress',
      '下载进度',
      description: '显示当前下载任务的进度',
      importance: Importance.low,
    );

    // 下载完成渠道
    const completeChannel = AndroidNotificationChannel(
      'download_complete',
      '下载完成',
      description: '下载任务完成时的通知',
    );

    // 后台服务渠道
    const serviceChannel = AndroidNotificationChannel(
      'download_service',
      '后台下载服务',
      description: '保持应用在后台进行下载',
      importance: Importance.low,
    );

    await androidPlugin.createNotificationChannel(downloadChannel);
    await androidPlugin.createNotificationChannel(completeChannel);
    await androidPlugin.createNotificationChannel(serviceChannel);
  }

  /// 显示下载进度通知
  Future<void> showDownloadProgress(DownloadTaskPersistent task) async {
    if (!_isInitialized) return;

    // Windows/Linux 平台不支持
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      return;
    }

    final notificationId = _taskNotificationIds.putIfAbsent(
      task.id,
      () => _notificationId++,
    );

    final progress = (task.progress * 100).toInt();
    final progressText = task.isLiveStream
        ? task.formattedDownloadedSize
        : '${task.formattedDownloadedSize} / ${task.formattedTotalSize}';

    final androidDetails = AndroidNotificationDetails(
      'download_progress',
      '下载进度',
      channelDescription: '显示当前下载任务的进度',
      importance: Importance.low,
      priority: Priority.low,
      showProgress: !task.isLiveStream,
      maxProgress: 100,
      progress: progress,
      onlyAlertOnce: true,
      ongoing: task.isDownloading,
      autoCancel: !task.isDownloading,
      category: AndroidNotificationCategory.progress,
      actions: task.canPause
          ? [
              const AndroidNotificationAction(
                'pause',
                '暂停',
                showsUserInterface: true,
              ),
              const AndroidNotificationAction(
                'cancel',
                '取消',
                showsUserInterface: true,
              ),
            ]
          : task.canResume
              ? [
                  const AndroidNotificationAction(
                    'resume',
                    '继续',
                    showsUserInterface: true,
                  ),
                  const AndroidNotificationAction(
                    'cancel',
                    '取消',
                    showsUserInterface: true,
                  ),
                ]
              : null,
    );

    final darwinDetails = DarwinNotificationDetails(
      presentAlert: false,
      presentBadge: false,
      presentBanner: false,
      presentSound: false,
      attachments: task.videoCover != null
          ? [
              DarwinNotificationAttachment(
                task.videoCover!,
              ),
            ]
          : null,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    final title = task.videoTitle ?? task.fileName;
    final body = task.isLiveStream
        ? '直播录制中: $progressText • ${task.formattedSpeed}'
        : task.isDownloading
            ? '$progressText (${task.formattedSpeed}) • ${task.formattedRemainingTime}'
            : task.statusText;

    await _notificationsPlugin.show(
      notificationId,
      title,
      body,
      details,
      payload: task.id,
    );

    // 如果是直播流或正在下载，更新全局通知
    if (task.isDownloading || task.isLiveStream) {
      await _updateGlobalNotification();
    }
  }

  /// 显示下载完成通知
  Future<void> showDownloadComplete(DownloadTaskPersistent task) async {
    if (!_isInitialized) return;

    // Windows/Linux 平台不支持
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      return;
    }

    // 取消进度通知
    final notificationId = _taskNotificationIds[task.id];
    if (notificationId != null) {
      await _notificationsPlugin.cancel(notificationId);
    }

    final androidDetails = AndroidNotificationDetails(
      'download_complete',
      '下载完成',
      channelDescription: '下载任务完成时的通知',
    );

    const darwinDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    final title = task.videoTitle ?? task.fileName;
    final body = task.isLiveStream
        ? '直播录制已保存: ${task.formattedDownloadedSize}'
        : '下载完成: ${task.formattedTotalSize}';

    await _notificationsPlugin.show(
      notificationId ?? _notificationId++,
      title,
      body,
      details,
      payload: task.id,
    );

    await _updateGlobalNotification();
  }

  /// 显示下载失败通知
  Future<void> showDownloadFailed(
    DownloadTaskPersistent task,
    String error,
  ) async {
    if (!_isInitialized) return;

    // Windows/Linux 平台不支持
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      return;
    }

    final notificationId = _taskNotificationIds[task.id];

    final androidDetails = AndroidNotificationDetails(
      'download_complete',
      '下载失败',
      channelDescription: '下载任务失败时的通知',
      actions: [
        const AndroidNotificationAction(
          'retry',
          '重试',
        ),
        const AndroidNotificationAction(
          'dismiss',
          '忽略',
        ),
      ],
    );

    const darwinDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    final title = task.videoTitle ?? task.fileName;
    final body =
        '下载失败: ${error.length > 50 ? '${error.substring(0, 50)}...' : error}';

    await _notificationsPlugin.show(
      notificationId ?? _notificationId++,
      title,
      body,
      details,
      payload: task.id,
    );

    await _updateGlobalNotification();
  }

  /// 取消任务通知
  Future<void> cancelTaskNotification(String taskId) async {
    final notificationId = _taskNotificationIds[taskId];
    if (notificationId != null) {
      await _notificationsPlugin.cancel(notificationId);
      _taskNotificationIds.remove(taskId);
    }
    await _updateGlobalNotification();
  }

  /// 更新全局下载通知（显示在通知栏的常驻通知）
  Future<void> _updateGlobalNotification() async {
    if (!_isInitialized) return;

    // Windows/Linux 平台不支持
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      return;
    }

    final downloadingCount = _currentStats.downloadingTasks;

    if (downloadingCount == 0) {
      if (_showingGlobalNotification) {
        await _notificationsPlugin.cancel(_globalNotificationId);
        _showingGlobalNotification = false;
      }
      return;
    }

    _showingGlobalNotification = true;

    final androidDetails = AndroidNotificationDetails(
      'download_service',
      '后台下载服务',
      channelDescription: '保持应用在后台进行下载',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      showProgress: true,
      maxProgress: 100,
      progress: _calculateOverallProgress(),
      onlyAlertOnce: true,
    );

    const darwinDetails = DarwinNotificationDetails();

    final details = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );

    final title =
        downloadingCount == 1 ? '正在下载 1 个文件' : '正在下载 $downloadingCount 个文件';
    final body =
        '总速度: ${_currentStats.formattedCurrentSpeed} • 已下载: ${_currentStats.formattedTotalDownloaded}';

    await _notificationsPlugin.show(
      _globalNotificationId,
      title,
      body,
      details,
      payload: 'global',
    );
  }

  /// 计算总体进度
  int _calculateOverallProgress() {
    final tasks = AdvancedDownloadManager().getAllTasks();
    if (tasks.isEmpty) return 0;

    final downloadingTasks = tasks.where((t) => t.isDownloading).toList();
    if (downloadingTasks.isEmpty) return 0;

    var totalProgress = 0.0;
    for (final task in downloadingTasks) {
      totalProgress += task.progress;
    }

    return ((totalProgress / downloadingTasks.length) * 100).toInt();
  }

  /// 统计信息更新回调
  void _onStatsUpdate(DownloadStatistics stats) {
    _currentStats = stats;
    unawaited(_updateGlobalNotification());
  }

  /// 通知响应回调
  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    final actionId = response.actionId;
    if (actionId == null) return;

    final manager = AdvancedDownloadManager();

    switch (actionId) {
      case 'pause':
        manager.pauseDownload(payload);
      case 'resume':
        manager.resumeDownload(payload);
      case 'cancel':
        manager.cancelDownload(payload);
      case 'retry':
        manager.retryTask(payload);
      case 'dismiss':
        cancelTaskNotification(payload);
    }
  }

  /// 释放资源
  void dispose() {
    _statsSubscription?.cancel();
    _notificationsPlugin.cancelAll();
  }
}
