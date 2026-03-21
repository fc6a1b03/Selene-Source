import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// USB 采集卡设备信息
class UsbCaptureDevice {
  final int vid;
  final int pid;
  final String? productName;
  final String? manufacturerName;
  final String? serialNumber;

  const UsbCaptureDevice({
    required this.vid,
    required this.pid,
    this.productName,
    this.manufacturerName,
    this.serialNumber,
  });

  factory UsbCaptureDevice.fromMap(Map<dynamic, dynamic> map) {
    return UsbCaptureDevice(
      vid: map['vid'] as int,
      pid: map['pid'] as int,
      productName: map['productName'] as String?,
      manufacturerName: map['manufacturerName'] as String?,
      serialNumber: map['serialNumber'] as String?,
    );
  }

  @override
  String toString() {
    return 'UsbCaptureDevice(vid: 0x${vid.toRadixString(16).padLeft(4, '0')}, '
        'pid: 0x${pid.toRadixString(16).padLeft(4, '0')}, '
        'productName: $productName)';
  }
}

/// USB 采集卡平台通道
///
/// 与 Android 原生层通信，实现 USB 设备检测功能
class UsbCaptureChannel {
  static const MethodChannel _channel = MethodChannel(
    'selene.usb_capture/channel',
  );
  static const EventChannel _eventChannel = EventChannel(
    'selene.usb_capture/events',
  );

  static Stream<UsbCaptureEvent>? _eventStream;

  /// 获取 USB 采集卡事件流
  static Stream<UsbCaptureEvent> get eventStream {
    if (_eventStream == null) {
      debugPrint('UsbCaptureChannel: 初始化事件流...');
      _eventStream = _eventChannel.receiveBroadcastStream().map(
        (dynamic event) {
          debugPrint('UsbCaptureChannel: 收到原生事件: $event');
          final map = event as Map<dynamic, dynamic>;
          return UsbCaptureEvent.fromMap(map);
        },
      );
    }
    return _eventStream!;
  }

  /// 检查当前是否连接了采集卡
  static Future<bool> isCaptureCardConnected() async {
    try {
      final result = await _channel.invokeMethod<bool>(
        'isCaptureCardConnected',
      );
      return result ?? false;
    } catch (e) {
      debugPrint('UsbCaptureChannel: 检查连接状态失败: $e');
      return false;
    }
  }

  /// 获取当前连接的采集卡设备信息
  static Future<UsbCaptureDevice?> getConnectedDevice() async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getConnectedDevice',
      );
      if (result != null) {
        return UsbCaptureDevice.fromMap(result);
      }
      return null;
    } catch (e) {
      debugPrint('UsbCaptureChannel: 获取设备信息失败: $e');
      return null;
    }
  }

  /// 获取视频设备路径
  static Future<String?> getVideoDevicePath() async {
    try {
      final result = await _channel.invokeMethod<String>(
        'getVideoDevicePath',
      );
      return result;
    } catch (e) {
      debugPrint('UsbCaptureChannel: 获取视频路径失败: $e');
      return null;
    }
  }

  /// 获取所有 USB 设备（用于调试）
  static Future<List<Map<dynamic, dynamic>>> getAllUsbDevices() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getAllUsbDevices',
      );
      return result?.cast<Map<dynamic, dynamic>>() ?? [];
    } catch (e) {
      debugPrint('UsbCaptureChannel: 获取所有设备失败: $e');
      return [];
    }
  }
}

/// USB 采集卡事件
class UsbCaptureEvent {
  final UsbCaptureEventType type;
  final UsbCaptureDevice? device;

  const UsbCaptureEvent({
    required this.type,
    this.device,
  });

  factory UsbCaptureEvent.fromMap(Map<dynamic, dynamic> map) {
    final typeString = map['type'] as String;
    final deviceMap = map['device'] as Map<dynamic, dynamic>?;

    return UsbCaptureEvent(
      type: UsbCaptureEventType.values.firstWhere(
        (e) => e.name == typeString,
        orElse: () => UsbCaptureEventType.unknown,
      ),
      device: deviceMap != null ? UsbCaptureDevice.fromMap(deviceMap) : null,
    );
  }

  @override
  String toString() {
    return 'UsbCaptureEvent(type: $type, device: $device)';
  }
}

/// USB 采集卡事件类型
enum UsbCaptureEventType {
  attached, // 设备插入
  detached, // 设备拔出
  permissionGranted, // 权限已授予
  permissionDenied, // 权限被拒绝
  unknown, // 未知
}
