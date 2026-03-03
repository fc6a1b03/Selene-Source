import 'dart:async';

import 'package:flutter/material.dart';

/// 错误恢复策略
enum RecoveryStrategy {
  /// 立即重试
  immediateRetry,

  /// 延迟重试
  delayedRetry,

  /// 降级处理
  fallback,

  /// 忽略错误
  ignore,

  /// 上报错误
  report,
}

/// 错误恢复配置
class ErrorRecoveryConfig {
  /// 最大重试次数
  final int maxRetries;

  /// 重试延迟
  final Duration retryDelay;

  /// 延迟倍数（指数退避）
  final double backoffMultiplier;

  /// 最大延迟
  final Duration maxDelay;

  /// 恢复策略
  final RecoveryStrategy strategy;

  /// 降级处理函数
  final FutureOr<dynamic> Function()? fallback;

  const ErrorRecoveryConfig({
    this.maxRetries = 3,
    this.retryDelay = const Duration(seconds: 1),
    this.backoffMultiplier = 2.0,
    this.maxDelay = const Duration(minutes: 1),
    this.strategy = RecoveryStrategy.delayedRetry,
    this.fallback,
  });
}

/// 错误恢复管理器
class ErrorRecoveryManager {
  static final ErrorRecoveryManager _instance =
      ErrorRecoveryManager._internal();
  static ErrorRecoveryManager get instance => _instance;
  ErrorRecoveryManager._internal();

  final Map<String, _ErrorContext> _errorContexts = {};

  /// 执行带恢复的操作
  Future<T> execute<T>(
    String key,
    Future<T> Function() operation, {
    ErrorRecoveryConfig? config,
  }) async {
    final effectiveConfig = config ?? const ErrorRecoveryConfig();
    final context = _errorContexts.putIfAbsent(
      key,
      () => _ErrorContext(),
    );

    int attempts = 0;
    Duration currentDelay = effectiveConfig.retryDelay;

    while (true) {
      try {
        final result = await operation();
        context.recordSuccess();
        return result;
      } catch (e) {
        attempts++;
        context.recordFailure(e);

        // 检查是否需要重试
        if (attempts >= effectiveConfig.maxRetries) {
          // 尝试降级处理
          if (effectiveConfig.fallback != null) {
            return await effectiveConfig.fallback!() as T;
          }
          rethrow;
        }

        // 根据策略处理
        switch (effectiveConfig.strategy) {
          case RecoveryStrategy.immediateRetry:
            continue;

          case RecoveryStrategy.delayedRetry:
            await Future<void>.delayed(currentDelay);
            currentDelay = Duration(
              milliseconds: (currentDelay.inMilliseconds *
                      effectiveConfig.backoffMultiplier)
                  .toInt()
                  .clamp(
                    0,
                    effectiveConfig.maxDelay.inMilliseconds,
                  ),
            );
            break;

          case RecoveryStrategy.fallback:
            if (effectiveConfig.fallback != null) {
              return await effectiveConfig.fallback!() as T;
            }
            rethrow;

          case RecoveryStrategy.ignore:
            return null as T;

          case RecoveryStrategy.report:
            _reportError(key, e, context);
            rethrow;
        }
      }
    }
  }

  /// 获取错误统计
  Map<String, dynamic> getStats(String key) {
    final context = _errorContexts[key];
    if (context == null) return {};

    return {
      'totalAttempts': context.totalAttempts,
      'successCount': context.successCount,
      'failureCount': context.failureCount,
      'lastError': context.lastError?.toString(),
      'lastErrorTime': context.lastErrorTime?.toIso8601String(),
    };
  }

  /// 清除错误记录
  void clear(String key) {
    _errorContexts.remove(key);
  }

  void _reportError(String key, dynamic error, _ErrorContext context) {
    debugPrint('Error in $key: $error');
    // 可以在这里添加错误上报逻辑
  }
}

class _ErrorContext {
  int totalAttempts = 0;
  int successCount = 0;
  int failureCount = 0;
  dynamic lastError;
  DateTime? lastErrorTime;

  void recordSuccess() {
    totalAttempts++;
    successCount++;
  }

  void recordFailure(dynamic error) {
    totalAttempts++;
    failureCount++;
    lastError = error;
    lastErrorTime = DateTime.now();
  }
}

/// 错误边界 Widget
class ErrorRecoveryBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(BuildContext context, Object error)? errorBuilder;
  final VoidCallback? onError;
  final ErrorRecoveryConfig? recoveryConfig;

  const ErrorRecoveryBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
    this.onError,
    this.recoveryConfig,
  });

  @override
  State<ErrorRecoveryBoundary> createState() => _ErrorRecoveryBoundaryState();
}

class _ErrorRecoveryBoundaryState extends State<ErrorRecoveryBoundary> {
  Object? _error;
  bool _isRecovering = false; // ignore: prefer_final_fields

  @override
  Widget build(BuildContext context) {
    if (_error != null && widget.errorBuilder != null) {
      return widget.errorBuilder!(context, _error!);
    }

    return _isRecovering
        ? const Center(child: CircularProgressIndicator())
        : widget.child;
  }
}

/// 超时包装器
Future<T> withTimeout<T>(
  Future<T> future, {
  required Duration timeout,
  String? message,
}) {
  return future.timeout(
    timeout,
    onTimeout: () => throw TimeoutException(
      message ?? 'Operation timed out after ${timeout.inSeconds}s',
    ),
  );
}

/// 取消令牌
class CancellationToken {
  bool _isCancelled = false;
  final _listeners = <VoidCallback>[];

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final listener in _listeners) {
      listener();
    }
    _listeners.clear();
  }

  void onCancelled(VoidCallback callback) {
    if (_isCancelled) {
      callback();
    } else {
      _listeners.add(callback);
    }
  }

  void throwIfCancelled() {
    if (_isCancelled) {
      throw CancellationException('Operation was cancelled');
    }
  }
}

/// 取消异常
class CancellationException implements Exception {
  final String message;
  CancellationException(this.message);

  @override
  String toString() => message;
}

/// 超时异常
class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}

/// 安全的 Future 执行
/// 自动处理取消和超时
Future<T> safeExecute<T>(
  Future<T> Function(CancellationToken token) operation, {
  Duration? timeout,
  CancellationToken? token,
}) async {
  final cancelToken = token ?? CancellationToken();

  try {
    Future<T> future = operation(cancelToken);

    if (timeout != null) {
      future = future.timeout(timeout);
    }

    return await future;
  } on TimeoutException {
    cancelToken.cancel();
    rethrow;
  }
}

/// 批处理执行器
/// 分批执行任务，支持取消
class BatchExecutor {
  final int batchSize;
  final Duration? delayBetweenBatches;
  final CancellationToken? cancellationToken;

  BatchExecutor({
    this.batchSize = 10,
    this.delayBetweenBatches,
    this.cancellationToken,
  });

  /// 执行批处理
  Future<List<T>> execute<T>(
    List<Future<T> Function()> tasks,
  ) async {
    final results = <T>[];

    for (var i = 0; i < tasks.length; i += batchSize) {
      cancellationToken?.throwIfCancelled();

      final batch = tasks.sublist(
        i,
        (i + batchSize).clamp(0, tasks.length),
      );

      final batchResults = await Future.wait(
        batch.map((task) => task()),
        // eagerError 默认为 false，可以省略
      );

      results.addAll(batchResults.whereType<T>());

      if (delayBetweenBatches != null && i + batchSize < tasks.length) {
        await Future<void>.delayed(delayBetweenBatches!);
      }
    }

    return results;
  }
}
