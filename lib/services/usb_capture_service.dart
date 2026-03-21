import 'dart:async';

import 'package:flutter/material.dart';
import 'package:selene/services/usb_capture_channel.dart';

/// USB 采集卡服务
///
/// 管理 USB 视频采集卡的检测和状态，支持手机通过 USB 采集卡查看服务器画面
class UsbCaptureService extends ChangeNotifier {
  UsbCaptureService._();

  static final UsbCaptureService _instance = UsbCaptureService._();
  static UsbCaptureService get instance => _instance;

  // 事件订阅
  StreamSubscription<UsbCaptureEvent>? _eventSubscription;

  // 状态
  bool _isCaptureCardConnected = false;
  UsbCaptureDevice? _connectedDevice;
  String? _devicePath;

  // Getters
  bool get isCaptureCardConnected => _isCaptureCardConnected;
  UsbCaptureDevice? get connectedDevice => _connectedDevice;
  String? get devicePath => _devicePath;

  /// 初始化并开始监听 USB 设备
  Future<void> initialize() async {
    debugPrint('UsbCaptureService: 初始化 USB 采集卡服务');

    // 先检查当前状态（设备可能已连接）
    await _checkCurrentStatus();

    // 再监听 USB 事件（热插拔）
    debugPrint('UsbCaptureService: 开始监听 USB 事件流...');
    _eventSubscription = UsbCaptureChannel.eventStream.listen(
      (event) {
        debugPrint('UsbCaptureService: 收到原始事件: $event');
        _handleEvent(event);
      },
      onError: (dynamic error) {
        debugPrint('UsbCaptureService: USB 事件监听错误: $error');
      },
      onDone: () {
        debugPrint('UsbCaptureService: USB 事件流已关闭');
      },
    );
  }

  /// 释放资源
  @override
  void dispose() {
    debugPrint('UsbCaptureService: 释放资源');
    _eventSubscription?.cancel();
    _connectedDevice = null;
    _isCaptureCardConnected = false;
    _devicePath = null;
    super.dispose();
  }

  /// 检查当前状态
  Future<void> _checkCurrentStatus() async {
    try {
      debugPrint('UsbCaptureService: 检查当前 USB 设备状态...');
      final isConnected = await UsbCaptureChannel.isCaptureCardConnected();
      debugPrint('UsbCaptureService: 原生层返回连接状态: $isConnected');

      if (isConnected) {
        final device = await UsbCaptureChannel.getConnectedDevice();
        final path = await UsbCaptureChannel.getVideoDevicePath();

        debugPrint('UsbCaptureService: 获取到设备信息: $device');
        debugPrint('UsbCaptureService: 获取到设备路径: $path');

        // 直接信任原生层检测结果，只要有设备就显示按钮
        if (device != null) {
          _connectedDevice = device;
          _isCaptureCardConnected = true;
          _devicePath = path ?? '/dev/video0';

          debugPrint(
            'UsbCaptureService: ✓ 发现已连接的采集卡: ${device.productName} (VID: 0x${device.vid.toRadixString(16)}, PID: 0x${device.pid.toRadixString(16)}), 路径: $_devicePath',
          );
          notifyListeners();
        } else {
          debugPrint('UsbCaptureService: 设备信息为空，重置状态');
          _resetState();
        }
      } else {
        debugPrint('UsbCaptureService: 未检测到 USB 采集卡连接');
        _resetState();
      }
    } catch (e, stackTrace) {
      debugPrint('UsbCaptureService: 检查当前状态失败: $e');
      debugPrint('UsbCaptureService: 堆栈: $stackTrace');
      _resetState();
    }
  }

  /// 重置状态为未连接
  void _resetState() {
    final hadDevice = _isCaptureCardConnected;
    _connectedDevice = null;
    _isCaptureCardConnected = false;
    _devicePath = null;

    // 只有之前连接过设备时才通知UI更新
    if (hadDevice) {
      debugPrint('UsbCaptureService: 状态变更 - 设备已断开');
      notifyListeners();
    }
  }

  /// 处理 USB 事件
  void _handleEvent(UsbCaptureEvent event) {
    debugPrint('UsbCaptureService: 收到事件 - ${event.type}');

    switch (event.type) {
      case UsbCaptureEventType.attached:
        // 直接信任原生层事件，只要有设备就处理
        if (event.device != null) {
          _handleDeviceAttached(event.device!);
        }
        break;

      case UsbCaptureEventType.detached:
        // 设备拔出，直接处理
        _handleDeviceDetached();
        break;

      case UsbCaptureEventType.permissionGranted:
        // 权限已授予，重新检查状态
        _checkCurrentStatus();
        break;

      case UsbCaptureEventType.permissionDenied:
        debugPrint('UsbCaptureService: 用户拒绝了 USB 权限');
        break;

      case UsbCaptureEventType.unknown:
        break;
    }
  }

  /// 处理设备插入
  Future<void> _handleDeviceAttached(UsbCaptureDevice device) async {
    debugPrint('UsbCaptureService: 采集卡插入: ${device.productName}');

    _connectedDevice = device;
    _isCaptureCardConnected = true;

    // 获取视频设备路径
    final path = await UsbCaptureChannel.getVideoDevicePath();
    _devicePath = path ?? '/dev/video0';

    debugPrint('UsbCaptureService: 采集卡已连接, 路径: $_devicePath');
    notifyListeners();
  }

  /// 处理设备拔出
  void _handleDeviceDetached() {
    debugPrint('UsbCaptureService: 采集卡拔出');

    _connectedDevice = null;
    _isCaptureCardConnected = false;
    _devicePath = null;

    debugPrint('UsbCaptureService: 采集卡已断开');
    notifyListeners();
  }

  // 注意：检测逻辑已简化，直接信任原生层结果

  /// 获取采集卡流 URL
  String? getCaptureStreamUrl() {
    if (!_isCaptureCardConnected || _devicePath == null) {
      return null;
    }
    return 'v4l2://$_devicePath';
  }

  /// 获取备用设备路径列表
  List<String> getAlternativeStreamUrls() {
    if (!_isCaptureCardConnected) {
      return [];
    }
    return [
      'v4l2:///dev/video0',
      'v4l2:///dev/video1',
      'v4l2:///dev/video2',
    ];
  }

  /// 手动刷新设备状态
  Future<void> refresh() async {
    await _checkCurrentStatus();
  }
}
