/// 下载任务类型枚举
enum DownloadTaskType {
  /// 普通视频下载
  video,

  /// 直播流下载（无限下载）
  liveStream,
}

/// 下载任务状态枚举
enum DownloadTaskPersistentStatus {
  /// 等待中
  waiting,

  /// 下载中
  downloading,

  /// 已暂停
  paused,

  /// 已完成
  completed,

  /// 已失败
  failed,

  /// 已取消
  cancelled,

  /// 已保存（直播流终止后保存）
  saved,
}

/// 持久化下载任务模型
///
/// 用于在 Hive 中存储下载任务的完整信息
class DownloadTaskPersistent {
  /// 任务唯一ID
  final String id;

  /// 下载URL
  final String url;

  /// 文件名
  final String fileName;

  /// 最终文件保存路径
  final String filePath;

  /// 临时文件路径
  final String tempFilePath;

  /// 视频标题
  final String? videoTitle;

  /// 视频封面
  final String? videoCover;

  /// 集数信息
  final String? episodeInfo;

  /// 文件总大小（字节）
  final int totalBytes;

  /// 已下载大小（字节）
  final int downloadedBytes;

  /// 下载进度（0.0 - 1.0）
  final double progress;

  /// 任务状态
  final DownloadTaskPersistentStatus status;

  /// 任务类型
  final DownloadTaskType type;

  /// 错误信息
  final String? errorMessage;

  /// 创建时间
  final DateTime createdAt;

  /// 更新时间
  final DateTime updatedAt;

  /// 下载速度（字节/秒）
  final int downloadSpeed;

  /// 预计剩余时间（秒）
  final int remainingSeconds;

  /// 是否支持断点续传
  final bool supportsResume;

  /// 额外请求头
  final Map<String, String>? headers;

  /// 构造函数
  DownloadTaskPersistent({
    required this.id,
    required this.url,
    required this.fileName,
    required this.filePath,
    required this.tempFilePath,
    this.videoTitle,
    this.videoCover,
    this.episodeInfo,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.progress = 0.0,
    this.status = DownloadTaskPersistentStatus.waiting,
    this.type = DownloadTaskType.video,
    this.errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.downloadSpeed = 0,
    this.remainingSeconds = 0,
    this.supportsResume = true,
    this.headers,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// 从JSON创建实例
  factory DownloadTaskPersistent.fromJson(Map<String, dynamic> json) {
    return DownloadTaskPersistent(
      id: json['id'] as String,
      url: json['url'] as String,
      fileName: json['fileName'] as String,
      filePath: json['filePath'] as String,
      tempFilePath: json['tempFilePath'] as String,
      videoTitle: json['videoTitle'] as String?,
      videoCover: json['videoCover'] as String?,
      episodeInfo: json['episodeInfo'] as String?,
      totalBytes: json['totalBytes'] as int? ?? 0,
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      status: DownloadTaskPersistentStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => DownloadTaskPersistentStatus.waiting,
      ),
      type: DownloadTaskType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => DownloadTaskType.video,
      ),
      errorMessage: json['errorMessage'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      downloadSpeed: json['downloadSpeed'] as int? ?? 0,
      remainingSeconds: json['remainingSeconds'] as int? ?? 0,
      supportsResume: json['supportsResume'] as bool? ?? true,
      headers: (json['headers'] as Map<String, dynamic>?)
          ?.map((key, value) => MapEntry(key, value as String)),
    );
  }

  /// 转换为JSON
  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'fileName': fileName,
        'filePath': filePath,
        'tempFilePath': tempFilePath,
        'videoTitle': videoTitle,
        'videoCover': videoCover,
        'episodeInfo': episodeInfo,
        'totalBytes': totalBytes,
        'downloadedBytes': downloadedBytes,
        'progress': progress,
        'status': status.name,
        'type': type.name,
        'errorMessage': errorMessage,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'downloadSpeed': downloadSpeed,
        'remainingSeconds': remainingSeconds,
        'supportsResume': supportsResume,
        'headers': headers,
      };

  /// 复制并更新实例
  DownloadTaskPersistent copyWith({
    String? id,
    String? url,
    String? fileName,
    String? filePath,
    String? tempFilePath,
    String? videoTitle,
    String? videoCover,
    String? episodeInfo,
    int? totalBytes,
    int? downloadedBytes,
    double? progress,
    DownloadTaskPersistentStatus? status,
    DownloadTaskType? type,
    String? errorMessage,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? downloadSpeed,
    int? remainingSeconds,
    bool? supportsResume,
    Map<String, String>? headers,
  }) {
    return DownloadTaskPersistent(
      id: id ?? this.id,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      filePath: filePath ?? this.filePath,
      tempFilePath: tempFilePath ?? this.tempFilePath,
      videoTitle: videoTitle ?? this.videoTitle,
      videoCover: videoCover ?? this.videoCover,
      episodeInfo: episodeInfo ?? this.episodeInfo,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      progress: progress ?? this.progress,
      status: status ?? this.status,
      type: type ?? this.type,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
      downloadSpeed: downloadSpeed ?? this.downloadSpeed,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      supportsResume: supportsResume ?? this.supportsResume,
      headers: headers ?? this.headers,
    );
  }

  /// 获取格式化的文件大小
  String get formattedTotalSize => formatBytes(totalBytes);

  /// 获取格式化的已下载大小
  String get formattedDownloadedSize => formatBytes(downloadedBytes);

  /// 获取格式化的下载速度
  String get formattedSpeed => formatSpeed(downloadSpeed);

  /// 获取格式化的剩余时间
  String get formattedRemainingTime => formatDuration(remainingSeconds);

  /// 格式化字节大小
  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    var i = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(2)} ${suffixes[i]}';
  }

  /// 格式化速度
  static String formatSpeed(int bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 B/s';
    return '${formatBytes(bytesPerSecond)}/s';
  }

  /// 格式化时长
  static String formatDuration(int seconds) {
    if (seconds <= 0) return '--:--';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  /// 获取状态显示文本
  String get statusText {
    switch (status) {
      case DownloadTaskPersistentStatus.waiting:
        return '等待中';
      case DownloadTaskPersistentStatus.downloading:
        return '下载中';
      case DownloadTaskPersistentStatus.paused:
        return '已暂停';
      case DownloadTaskPersistentStatus.completed:
        return '已完成';
      case DownloadTaskPersistentStatus.failed:
        return '失败';
      case DownloadTaskPersistentStatus.cancelled:
        return '已取消';
      case DownloadTaskPersistentStatus.saved:
        return '已保存';
    }
  }

  /// 获取状态颜色
  int get statusColor {
    switch (status) {
      case DownloadTaskPersistentStatus.waiting:
        return 0xFF9CA3AF; // gray
      case DownloadTaskPersistentStatus.downloading:
        return 0xFF3B82F6; // blue
      case DownloadTaskPersistentStatus.paused:
        return 0xFFF59E0B; // orange
      case DownloadTaskPersistentStatus.completed:
        return 0xFF10B981; // green
      case DownloadTaskPersistentStatus.failed:
        return 0xFFEF4444; // red
      case DownloadTaskPersistentStatus.cancelled:
        return 0xFF6B7280; // dark gray
      case DownloadTaskPersistentStatus.saved:
        return 0xFF8B5CF6; // purple
    }
  }

  /// 是否可以暂停
  bool get canPause => status == DownloadTaskPersistentStatus.downloading;

  /// 是否可以恢复
  bool get canResume =>
      status == DownloadTaskPersistentStatus.paused ||
      (status == DownloadTaskPersistentStatus.failed && supportsResume);

  /// 是否可以删除
  bool get canDelete =>
      status == DownloadTaskPersistentStatus.completed ||
      status == DownloadTaskPersistentStatus.failed ||
      status == DownloadTaskPersistentStatus.cancelled ||
      status == DownloadTaskPersistentStatus.saved;

  /// 是否正在下载
  bool get isDownloading => status == DownloadTaskPersistentStatus.downloading;

  /// 是否是直播流
  bool get isLiveStream => type == DownloadTaskType.liveStream;

  /// 是否已完成或保存
  bool get isFinished =>
      status == DownloadTaskPersistentStatus.completed ||
      status == DownloadTaskPersistentStatus.saved;

  @override
  String toString() {
    return 'DownloadTaskPersistent(id: $id, fileName: $fileName, status: $status, progress: ${(progress * 100).toStringAsFixed(1)}%)';
  }
}

/// 下载统计信息
class DownloadStatistics {
  /// 总任务数
  final int totalTasks;

  /// 下载中任务数
  final int downloadingTasks;

  /// 已完成任务数
  final int completedTasks;

  /// 失败任务数
  final int failedTasks;

  /// 总下载大小（字节）
  final int totalDownloadedBytes;

  /// 当前下载速度（字节/秒）
  final int currentSpeed;

  const DownloadStatistics({
    this.totalTasks = 0,
    this.downloadingTasks = 0,
    this.completedTasks = 0,
    this.failedTasks = 0,
    this.totalDownloadedBytes = 0,
    this.currentSpeed = 0,
  });

  /// 获取格式化的总下载大小
  String get formattedTotalDownloaded =>
      DownloadTaskPersistent.formatBytes(totalDownloadedBytes);

  /// 获取格式化的当前速度
  String get formattedCurrentSpeed =>
      DownloadTaskPersistent.formatSpeed(currentSpeed);

  /// 是否有活动任务
  bool get hasActiveTasks => downloadingTasks > 0;

  /// 复制并更新
  DownloadStatistics copyWith({
    int? totalTasks,
    int? downloadingTasks,
    int? completedTasks,
    int? failedTasks,
    int? totalDownloadedBytes,
    int? currentSpeed,
  }) {
    return DownloadStatistics(
      totalTasks: totalTasks ?? this.totalTasks,
      downloadingTasks: downloadingTasks ?? this.downloadingTasks,
      completedTasks: completedTasks ?? this.completedTasks,
      failedTasks: failedTasks ?? this.failedTasks,
      totalDownloadedBytes: totalDownloadedBytes ?? this.totalDownloadedBytes,
      currentSpeed: currentSpeed ?? this.currentSpeed,
    );
  }
}
