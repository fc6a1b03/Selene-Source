import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 连接状态
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// 连接配置
class ConnectionConfig {
  /// 基础 URL
  final String baseUrl;

  /// 连接超时
  final Duration connectionTimeout;

  /// 读取超时
  final Duration readTimeout;

  /// 重试次数
  final int maxRetries;

  /// 重试间隔
  final Duration retryInterval;

  /// 心跳间隔
  final Duration? heartbeatInterval;

  const ConnectionConfig({
    required this.baseUrl,
    this.connectionTimeout = const Duration(seconds: 10),
    this.readTimeout = const Duration(seconds: 30),
    this.maxRetries = 3,
    this.retryInterval = const Duration(seconds: 2),
    this.heartbeatInterval,
  });
}

/// SSE 连接管理器
/// 自动重连、心跳检测、连接状态管理
class SSEConnectionManager {
  ConnectionConfig config;

  http.Client? _client;
  StreamSubscription<String>? _subscription;
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;

  ConnectionState _state = ConnectionState.disconnected;
  int _retryCount = 0;
  bool _isDisposed = false;

  // 状态回调
  final void Function(ConnectionState state)? onStateChanged;
  final void Function(String data)? onData;
  final void Function(String error)? onError;
  final VoidCallback? onConnected;
  final VoidCallback? onDisconnected;

  SSEConnectionManager({
    required this.config,
    this.onStateChanged,
    this.onData,
    this.onError,
    this.onConnected,
    this.onDisconnected,
  });

  /// 当前连接状态
  ConnectionState get state => _state;

  /// 是否已连接
  bool get isConnected => _state == ConnectionState.connected;

  /// 开始连接
  Future<void> connect(Map<String, String> headers) async {
    if (_isDisposed) return;
    if (_state == ConnectionState.connecting ||
        _state == ConnectionState.connected) {
      return;
    }

    _setState(ConnectionState.connecting);

    try {
      _client?.close();
      _client = http.Client();

      final request = http.Request('GET', Uri.parse(config.baseUrl));
      request.headers.addAll(headers);
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final response = await _client!.send(request).timeout(
            config.connectionTimeout,
          );

      if (response.statusCode == 200) {
        _setState(ConnectionState.connected);
        _retryCount = 0;
        onConnected?.call();

        // 启动心跳
        _startHeartbeat();

        // 监听数据
        _subscription = response.stream
            .transform(const Utf8Decoder())
            .transform(const LineSplitter())
            .listen(
              _onData,
              onError: _onError,
              onDone: _onDone,
              cancelOnError: true,
            );
      } else {
        throw HttpException('HTTP ${response.statusCode}');
      }
    } catch (e) {
      _onError(e);
    }
  }

  /// 断开连接
  void disconnect() {
    _retryCount = config.maxRetries; // 防止自动重连
    _cleanup();
    _setState(ConnectionState.disconnected);
    onDisconnected?.call();
  }

  /// 发送心跳
  void _startHeartbeat() {
    if (config.heartbeatInterval == null) return;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(config.heartbeatInterval!, (_) {
      // 可以在这里发送 ping 消息
    });
  }

  /// 数据回调
  void _onData(String line) {
    if (line.startsWith('data: ')) {
      final data = line.substring(6);
      onData?.call(data);
    }
  }

  /// 错误回调
  void _onError(dynamic error) {
    onError?.call(error.toString());
    _attemptReconnect();
  }

  /// 连接关闭回调
  void _onDone() {
    if (_state == ConnectionState.connected) {
      _attemptReconnect();
    }
  }

  /// 尝试重连
  void _attemptReconnect() {
    if (_isDisposed) return;
    if (_retryCount >= config.maxRetries) {
      _setState(ConnectionState.error);
      return;
    }

    _setState(ConnectionState.reconnecting);
    _retryCount++;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(
      config.retryInterval * _retryCount,
      () => connect({}),
    );
  }

  /// 清理资源
  void _cleanup() {
    _subscription?.cancel();
    _subscription = null;

    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;

    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    _client?.close();
    _client = null;
  }

  /// 设置状态
  void _setState(ConnectionState newState) {
    if (_state != newState) {
      _state = newState;
      onStateChanged?.call(newState);
    }
  }

  /// 释放资源
  void dispose() {
    _isDisposed = true;
    _cleanup();
  }
}

/// 连接池管理器
/// 管理多个连接
class ConnectionPool {
  static final ConnectionPool _instance = ConnectionPool._internal();
  static ConnectionPool get instance => _instance;
  ConnectionPool._internal();

  final Map<String, SSEConnectionManager> _connections = {};
  final int _maxConnections = 5;

  /// 创建或获取连接
  SSEConnectionManager getConnection(
    String key,
    ConnectionConfig config, {
    void Function(ConnectionState)? onStateChanged,
    void Function(String)? onData,
    void Function(String)? onError,
    VoidCallback? onConnected,
    VoidCallback? onDisconnected,
  }) {
    // 如果连接已存在，返回现有连接
    if (_connections.containsKey(key)) {
      return _connections[key]!;
    }

    // 如果超过最大连接数，关闭最旧的
    if (_connections.length >= _maxConnections) {
      final oldestKey = _connections.keys.first;
      _connections[oldestKey]?.dispose();
      _connections.remove(oldestKey);
    }

    // 创建新连接
    final connection = SSEConnectionManager(
      config: config,
      onStateChanged: onStateChanged,
      onData: onData,
      onError: onError,
      onConnected: onConnected,
      onDisconnected: onDisconnected,
    );

    _connections[key] = connection;
    return connection;
  }

  /// 关闭指定连接
  void closeConnection(String key) {
    _connections[key]?.dispose();
    _connections.remove(key);
  }

  /// 关闭所有连接
  void closeAll() {
    for (final connection in _connections.values) {
      connection.dispose();
    }
    _connections.clear();
  }

  /// 获取连接统计
  Map<String, ConnectionState> getStats() {
    return _connections.map(
      (key, conn) => MapEntry(key, conn.state),
    );
  }
}
