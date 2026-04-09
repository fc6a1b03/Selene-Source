import 'package:hive/hive.dart';
import 'package:selene/models/download_task_persistent.dart';

/// 下载任务持久化模型 Hive Adapter
class DownloadTaskPersistentAdapter
    extends TypeAdapter<DownloadTaskPersistent> {
  @override
  final int typeId = 10;

  @override
  DownloadTaskPersistent read(BinaryReader reader) {
    final id = reader.readString();
    final url = reader.readString();
    final fileName = reader.readString();
    final filePath = reader.readString();
    final tempFilePath = reader.readString();
    final videoTitle = reader.readString();
    final videoCover = reader.readString();
    final episodeInfo = reader.readString();
    final totalBytes = reader.readInt();
    final downloadedBytes = reader.readInt();
    final progress = reader.readDouble();
    final statusIndex = reader.readInt();
    final typeIndex = reader.readInt();
    final errorMessage = reader.readString();
    final createdAtMillis = reader.readInt();
    final updatedAtMillis = reader.readInt();
    final downloadSpeed = reader.readInt();
    final remainingSeconds = reader.readInt();
    final supportsResume = reader.readBool();

    // 读取 headers Map
    final headersLength = reader.readInt();
    Map<String, String>? headers;
    if (headersLength >= 0) {
      headers = {};
      for (var i = 0; i < headersLength; i++) {
        final key = reader.readString();
        final value = reader.readString();
        headers[key] = value;
      }
    }

    return DownloadTaskPersistent(
      id: id,
      url: url,
      fileName: fileName,
      filePath: filePath,
      tempFilePath: tempFilePath,
      videoTitle: videoTitle.isEmpty ? null : videoTitle,
      videoCover: videoCover.isEmpty ? null : videoCover,
      episodeInfo: episodeInfo.isEmpty ? null : episodeInfo,
      totalBytes: totalBytes,
      downloadedBytes: downloadedBytes,
      progress: progress,
      status: DownloadTaskPersistentStatus.values[statusIndex],
      type: DownloadTaskType.values[typeIndex],
      errorMessage: errorMessage.isEmpty ? null : errorMessage,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMillis),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMillis),
      downloadSpeed: downloadSpeed,
      remainingSeconds: remainingSeconds,
      supportsResume: supportsResume,
      headers: headers,
    );
  }

  @override
  void write(BinaryWriter writer, DownloadTaskPersistent obj) {
    writer.writeString(obj.id);
    writer.writeString(obj.url);
    writer.writeString(obj.fileName);
    writer.writeString(obj.filePath);
    writer.writeString(obj.tempFilePath);
    writer.writeString(obj.videoTitle ?? '');
    writer.writeString(obj.videoCover ?? '');
    writer.writeString(obj.episodeInfo ?? '');
    writer.writeInt(obj.totalBytes);
    writer.writeInt(obj.downloadedBytes);
    writer.writeDouble(obj.progress);
    writer.writeInt(obj.status.index);
    writer.writeInt(obj.type.index);
    writer.writeString(obj.errorMessage ?? '');
    writer.writeInt(obj.createdAt.millisecondsSinceEpoch);
    writer.writeInt(obj.updatedAt.millisecondsSinceEpoch);
    writer.writeInt(obj.downloadSpeed);
    writer.writeInt(obj.remainingSeconds);
    writer.writeBool(obj.supportsResume);

    // 写入 headers Map
    if (obj.headers == null || obj.headers!.isEmpty) {
      writer.writeInt(-1);
    } else {
      writer.writeInt(obj.headers!.length);
      obj.headers!.forEach((key, value) {
        writer.writeString(key);
        writer.writeString(value);
      });
    }
  }
}
