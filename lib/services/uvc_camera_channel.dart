import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// UVCCamera 平台通道
///
/// 与 Android 原生层通信，控制 USB 摄像头
class UVCCameraChannel {
  static const MethodChannel _channel = MethodChannel(
    'selene.uvc_camera/channel',
  );
  static const EventChannel _eventChannel = EventChannel(
    'selene.uvc_camera/events',
  );

  static Stream<UVCCameraEvent>? _eventStream;

  /// 获取 UVCCamera 事件流
  static Stream<UVCCameraEvent> get eventStream {
    _eventStream ??= _eventChannel.receiveBroadcastStream().map(
      (dynamic event) {
        final map = event as Map<dynamic, dynamic>;
        return UVCCameraEvent.fromMap(map);
      },
    );
    return _eventStream!;
  }

  /// 获取设备列表
  static Future<List<UVCCameraDevice>> getDeviceList() async {
    try {
      final result = await _channel.invokeMethod<List<dynamic>>(
        'getDeviceList',
      );
      return result?.map((d) => UVCCameraDevice.fromMap(d)).toList() ?? [];
    } catch (e) {
      debugPrint('UVCCameraChannel: 获取设备列表失败: $e');
      return [];
    }
  }

  /// 请求权限
  static Future<bool> requestPermission(String deviceName) async {
    try {
      return await _channel.invokeMethod<bool>(
            'requestPermission',
            {'deviceName': deviceName},
          ) ??
          false;
    } catch (e) {
      debugPrint('UVCCameraChannel: 请求权限失败: $e');
      return false;
    }
  }

  /// 检查是否有权限
  static Future<bool> hasPermission(String deviceName) async {
    try {
      return await _channel.invokeMethod<bool>(
            'hasPermission',
            {'deviceName': deviceName},
          ) ??
          false;
    } catch (e) {
      debugPrint('UVCCameraChannel: 检查权限失败: $e');
      return false;
    }
  }

  /// 打开摄像头
  static Future<bool> openCamera(String deviceName) async {
    try {
      return await _channel.invokeMethod<bool>(
            'openCamera',
            {'deviceName': deviceName},
          ) ??
          false;
    } catch (e) {
      debugPrint('UVCCameraChannel: 打开摄像头失败: $e');
      return false;
    }
  }

  /// 关闭摄像头
  static Future<bool> closeCamera() async {
    try {
      return await _channel.invokeMethod<bool>('closeCamera') ?? false;
    } catch (e) {
      debugPrint('UVCCameraChannel: 关闭摄像头失败: $e');
      return false;
    }
  }

  /// 检查摄像头是否打开
  static Future<bool> isCameraOpened() async {
    try {
      return await _channel.invokeMethod<bool>('isCameraOpened') ?? false;
    } catch (e) {
      debugPrint('UVCCameraChannel: 检查摄像头状态失败: $e');
      return false;
    }
  }
}

/// UVCCamera 设备信息
class UVCCameraDevice {
  final String deviceName;
  final int vendorId;
  final int productId;
  final String manufacturerName;
  final String productName;

  const UVCCameraDevice({
    required this.deviceName,
    required this.vendorId,
    required this.productId,
    required this.manufacturerName,
    required this.productName,
  });

  factory UVCCameraDevice.fromMap(Map<dynamic, dynamic> map) {
    return UVCCameraDevice(
      deviceName: map['deviceName'] as String? ?? '',
      vendorId: map['vendorId'] as int? ?? 0,
      productId: map['productId'] as int? ?? 0,
      manufacturerName: map['manufacturerName'] as String? ?? '',
      productName: map['productName'] as String? ?? '',
    );
  }

  @override
  String toString() {
    return 'UVCCameraDevice($productName, VID: 0x${vendorId.toRadixString(16)}, PID: 0x${productId.toRadixString(16)})';
  }
}

/// UVCCamera 事件
class UVCCameraEvent {
  final String event;
  final String deviceName;
  final bool? success;
  final int? vendorId;
  final int? productId;

  const UVCCameraEvent({
    required this.event,
    required this.deviceName,
    this.success,
    this.vendorId,
    this.productId,
  });

  factory UVCCameraEvent.fromMap(Map<dynamic, dynamic> map) {
    return UVCCameraEvent(
      event: map['event'] as String? ?? '',
      deviceName: map['deviceName'] as String? ?? '',
      success: map['success'] as bool?,
      vendorId: map['vendorId'] as int?,
      productId: map['productId'] as int?,
    );
  }

  @override
  String toString() {
    return 'UVCCameraEvent($event: $deviceName)';
  }
}

/// UVCCamera 平台视图 Widget
class UVCCameraView extends StatelessWidget {
  final Map<String, dynamic>? creationParams;

  const UVCCameraView({
    super.key,
    this.creationParams,
  });

  @override
  Widget build(BuildContext context) {
    // 使用 AndroidView 嵌入原生 UVCCamera 预览
    return const AndroidView(
      viewType: 'selene.uvc_camera/view',
      creationParamsCodec: StandardMessageCodec(),
    );
  }
}
