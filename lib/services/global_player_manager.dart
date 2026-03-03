import 'dart:async';
import 'package:flutter/material.dart';

/// 全局播放器管理器
///
/// 确保应用程序中同时只有一个播放器实例在运行。
/// 当打开新播放器时，自动停止并释放之前的播放器。
class GlobalPlayerManager {
  GlobalPlayerManager._();

  static final GlobalPlayerManager _instance = GlobalPlayerManager._();
  static GlobalPlayerManager get instance => _instance;

  /// 当前活动的播放器回调
  VoidCallback? _activePlayerDisposer;

  /// 当前播放器类型标识
  String? _activePlayerId;

  /// 播放器状态流控制器
  final _playerStateController = StreamController<PlayerStateEvent>.broadcast();
  Stream<PlayerStateEvent> get playerStateStream =>
      _playerStateController.stream;

  /// 注册新的播放器实例
  ///
  /// [disposer] - 释放播放器资源的回调函数
  /// [playerId] - 播放器唯一标识（用于调试）
  ///
  /// 返回 true 表示成功注册，false 表示有冲突（如相同播放器重复注册）
  bool registerPlayer(VoidCallback disposer, {String? playerId}) {
    // 如果有已激活的播放器，先释放它
    if (_activePlayerDisposer != null) {
      // 如果是同一个播放器，不重复处理
      if (_activePlayerId == playerId && playerId != null) {
        debugPrint('GlobalPlayerManager: 相同播放器重复注册，忽略: $playerId');
        return false;
      }

      debugPrint('GlobalPlayerManager: 释放之前的播放器: $_activePlayerId');
      _notifyPlayerStateChange(PlayerState.disposing, _activePlayerId);

      try {
        _activePlayerDisposer!();
      } catch (e) {
        debugPrint('GlobalPlayerManager: 释放播放器时出错: $e');
      }

      _activePlayerDisposer = null;
      _activePlayerId = null;
    }

    // 注册新播放器
    _activePlayerDisposer = disposer;
    _activePlayerId = playerId;

    debugPrint('GlobalPlayerManager: 注册新播放器: $playerId');
    _notifyPlayerStateChange(PlayerState.playing, playerId);

    return true;
  }

  /// 注销播放器实例
  ///
  /// [playerId] - 要注销的播放器标识，用于验证
  void unregisterPlayer({String? playerId}) {
    if (_activePlayerId != playerId && playerId != null) {
      debugPrint('GlobalPlayerManager: 尝试注销不匹配的播放器，忽略');
      return;
    }

    debugPrint('GlobalPlayerManager: 注销播放器: $_activePlayerId');
    _notifyPlayerStateChange(PlayerState.idle, _activePlayerId);

    _activePlayerDisposer = null;
    _activePlayerId = null;
  }

  /// 强制释放当前播放器（用于应用退出等场景）
  void forceDispose() {
    if (_activePlayerDisposer != null) {
      debugPrint('GlobalPlayerManager: 强制释放播放器: $_activePlayerId');
      _notifyPlayerStateChange(PlayerState.disposing, _activePlayerId);

      try {
        _activePlayerDisposer!();
      } catch (e) {
        debugPrint('GlobalPlayerManager: 强制释放时出错: $e');
      }

      _activePlayerDisposer = null;
      _activePlayerId = null;
    }
  }

  /// 检查是否有活动的播放器
  bool get hasActivePlayer => _activePlayerDisposer != null;

  /// 获取当前活动播放器ID
  String? get activePlayerId => _activePlayerId;

  /// 通知播放器状态变化
  void _notifyPlayerStateChange(PlayerState state, String? playerId) {
    if (!_playerStateController.isClosed) {
      _playerStateController.add(PlayerStateEvent(state, playerId));
    }
  }

  /// 释放管理器资源
  void dispose() {
    forceDispose();
    _playerStateController.close();
  }
}

/// 播放器状态
enum PlayerState {
  idle, // 空闲状态
  playing, // 正在播放
  disposing, // 正在释放
}

/// 播放器状态事件
class PlayerStateEvent {
  final PlayerState state;
  final String? playerId;

  const PlayerStateEvent(this.state, this.playerId);

  @override
  String toString() => 'PlayerStateEvent(state: $state, playerId: $playerId)';
}

/// 全局播放器管理混入
///
/// 用于 State 类中简化与 GlobalPlayerManager 的集成
mixin GlobalPlayerMixin<T extends StatefulWidget> on State<T> {
  String? _playerId;
  bool _isRegistered = false;

  /// 初始化全局播放器管理
  ///
  /// [disposer] - 释放播放器资源的回调
  /// [playerId] - 播放器唯一标识
  void initGlobalPlayer(VoidCallback disposer, {String? playerId}) {
    _playerId = playerId ?? '$runtimeType _$hashCode';
    _isRegistered = GlobalPlayerManager.instance.registerPlayer(
      () {
        _isRegistered = false;
        disposer();
      },
      playerId: _playerId,
    );
  }

  /// 注销全局播放器
  void disposeGlobalPlayer() {
    if (_isRegistered) {
      GlobalPlayerManager.instance.unregisterPlayer(playerId: _playerId);
      _isRegistered = false;
    }
  }

  @override
  void dispose() {
    disposeGlobalPlayer();
    super.dispose();
  }
}
