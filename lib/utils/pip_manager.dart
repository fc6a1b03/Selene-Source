import 'dart:async';
import 'dart:io';

import 'package:floating/floating.dart';
import 'package:flutter/material.dart';
import 'package:pip/pip.dart' as pip_ios;

/// 画中画管理器回调类型
typedef PipModeChangedCallback = void Function({required bool isPipMode});

/// 画中画管理器
///
/// 平台区分实现：
/// - Android: 使用 floating 包
/// - iOS: 使用 pip 包
class PipManager {
  static final PipManager _instance = PipManager._internal();
  factory PipManager() => _instance;
  PipManager._internal();

  // iOS 使用 pip 包
  pip_ios.Pip? _pipIOS;
  pip_ios.PipStateChangedObserver? _pipObserverIOS;

  // Android 使用 floating 包
  Floating? _floatingAndroid;
  Timer? _pipStatusTimer;

  // 状态回调
  PipModeChangedCallback? _onPipModeChanged;

  /// 是否正在画中画模式
  bool _isPipMode = false;
  bool get isPipMode => _isPipMode;

  /// 初始化 PiP
  Future<void> initialize() async {
    if (Platform.isAndroid) {
      await _initializeAndroid();
    } else if (Platform.isIOS) {
      await _initializeIOS();
    }
  }

  /// 初始化 Android PiP (floating)
  Future<void> _initializeAndroid() async {
    _floatingAndroid = Floating();

    // 轮询检查 PiP 状态（floating 包没有提供 Stream）
    _pipStatusTimer?.cancel();
    _pipStatusTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) async {
      final status = await _floatingAndroid?.pipStatus;
      final isPip = status?.name == 'enabled';
      if (_isPipMode != isPip) {
        _isPipMode = isPip;
        _onPipModeChanged?.call(isPipMode: isPip);
      }
    });
  }

  /// 初始化 iOS PiP (pip)
  Future<void> _initializeIOS() async {
    _pipIOS = pip_ios.Pip();

    _pipObserverIOS = pip_ios.PipStateChangedObserver(
      onPipStateChanged: (state, error) {
        switch (state) {
          case pip_ios.PipState.pipStateStarted:
            _isPipMode = true;
            _onPipModeChanged?.call(isPipMode: true);
            break;
          case pip_ios.PipState.pipStateStopped:
          case pip_ios.PipState.pipStateFailed:
            _isPipMode = false;
            _onPipModeChanged?.call(isPipMode: false);
            break;
        }
      },
    );

    try {
      await _pipIOS?.registerStateChangedObserver(_pipObserverIOS!);
    } catch (e) {
      debugPrint('Failed to register PiP observer: $e');
    }

    // 设置默认配置
    await _pipIOS?.setup(
      const pip_ios.PipOptions(
        autoEnterEnabled: true,
        aspectRatioX: 16,
        aspectRatioY: 9,
        preferredContentWidth: 480,
        preferredContentHeight: 270,
        controlStyle: 2,
      ),
    );
  }

  /// 设置 PiP 状态变化回调
  void setOnPipModeChanged(PipModeChangedCallback? callback) {
    _onPipModeChanged = callback;
  }

  /// 检查是否支持 PiP
  Future<bool> isSupported() async {
    // 确保已初始化
    if (Platform.isAndroid && _floatingAndroid == null) {
      await _initializeAndroid();
    } else if (Platform.isIOS && _pipIOS == null) {
      await _initializeIOS();
    }

    if (Platform.isAndroid) {
      return _floatingAndroid?.isPipAvailable ?? false;
    } else if (Platform.isIOS) {
      return await _pipIOS?.isSupported() ?? false;
    }
    return false;
  }

  /// 检查是否支持自动进入 PiP
  Future<bool> isAutoEnterSupported() async {
    if (Platform.isAndroid) {
      // Android floating 包自动支持
      return _floatingAndroid?.isPipAvailable ?? false;
    } else if (Platform.isIOS) {
      return await _pipIOS?.isAutoEnterSupported() ?? false;
    }
    return false;
  }

  /// 配置 PiP（通常在播放状态变化时调用）
  Future<void> configure({required bool playing}) async {
    if (Platform.isAndroid) {
      // Android: floating 包不需要配置，通过 enable 参数控制
    } else if (Platform.isIOS) {
      // iOS: 更新配置以启用/禁用自动进入 PiP
      await _pipIOS?.setup(
        pip_ios.PipOptions(
          autoEnterEnabled: playing,
          aspectRatioX: 16,
          aspectRatioY: 9,
          preferredContentWidth: 480,
          preferredContentHeight: 270,
          controlStyle: 2,
        ),
      );
    }
  }

  /// 进入 PiP 模式（手动调用）
  Future<bool> enterPipMode() async {
    // 确保已初始化
    if (Platform.isAndroid && _floatingAndroid == null) {
      await _initializeAndroid();
    } else if (Platform.isIOS && _pipIOS == null) {
      await _initializeIOS();
    }

    if (Platform.isAndroid) {
      // Android: 使用 ImmediatePiP 立即进入 PiP
      final status = await _floatingAndroid?.enable(
        const ImmediatePiP(),
      );
      final success = status?.name == 'enabled';
      if (success) {
        _isPipMode = true;
        _onPipModeChanged?.call(isPipMode: true);
      }
      return success;
    } else if (Platform.isIOS) {
      final success = await _pipIOS?.start() ?? false;
      if (success) {
        _isPipMode = true;
        _onPipModeChanged?.call(isPipMode: true);
      }
      return success;
    }
    return false;
  }

  /// 退出 PiP 模式
  ///
  /// 注意：Android floating 包不支持程序化退出 PiP，
  /// 用户需要通过系统 UI 手动关闭
  Future<void> exitPipMode() async {
    if (Platform.isIOS) {
      await _pipIOS?.stop();
      _isPipMode = false;
      _onPipModeChanged?.call(isPipMode: false);
    }
    // Android: floating 包不支持程序化退出
  }

  /// 释放资源
  Future<void> dispose() async {
    // 取消定时器
    _pipStatusTimer?.cancel();
    _pipStatusTimer = null;

    // 取消 iOS 观察者
    if (Platform.isIOS && _pipObserverIOS != null) {
      try {
        await _pipIOS?.unregisterStateChangedObserver();
      } catch (e) {
        debugPrint('Failed to unregister PiP observer: $e');
      }
      _pipObserverIOS = null;
    }

    // 释放资源
    await _pipIOS?.dispose();
    _pipIOS = null;
    _floatingAndroid = null;
    _onPipModeChanged = null;
    _isPipMode = false;
  }
}
