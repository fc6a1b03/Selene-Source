import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// 性能监控工具
class PerformanceMonitor {
  PerformanceMonitor._();

  static final PerformanceMonitor _instance = PerformanceMonitor._();
  static PerformanceMonitor get instance => _instance;

  bool _isEnabled = kDebugMode;
  final Map<String, _PerformanceMetric> _metrics = {};
  Timer? _cleanupTimer;

  /// 启用/禁用监控
  void setEnabled({required bool enabled}) {
    _isEnabled = enabled;
    if (enabled) {
      _startCleanupTimer();
    } else {
      _cleanupTimer?.cancel();
    }
  }

  /// 开始测量
  PerformanceMeasurement startMeasurement(String name) {
    if (!_isEnabled) return _NoOpMeasurement();

    final metric = _metrics.putIfAbsent(name, () => _PerformanceMetric(name));
    metric.startCount++;
    return _RealMeasurement(metric);
  }

  /// 记录帧时间
  void recordFrameTime(String name, Duration frameTime) {
    if (!_isEnabled) return;

    final metric = _metrics.putIfAbsent(name, () => _PerformanceMetric(name));
    metric.addFrameTime(frameTime);
  }

  /// 获取报告
  Map<String, dynamic> getReport() {
    final report = <String, dynamic>{};
    _metrics.forEach((name, metric) {
      report[name] = metric.toJson();
    });
    return report;
  }

  /// 打印报告
  void printReport() {
    if (!_isEnabled) return;

    developer.log('========== Performance Report ==========');
    _metrics.forEach((name, metric) {
      developer.log('$name: ${metric.averageTime.toStringAsFixed(2)}ms avg, '
          '${metric.maxTime.toStringAsFixed(2)}ms max, '
          '${metric.startCount} calls');
    });
    developer.log('========================================');
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _cleanup();
    });
  }

  /// 清理旧数据
  void _cleanup() {
    final now = DateTime.now();
    _metrics.removeWhere((name, metric) {
      return now.difference(metric.lastUpdated) > const Duration(minutes: 10);
    });
  }

  /// 清除所有数据
  void clear() {
    _metrics.clear();
  }
}

/// 性能指标
class _PerformanceMetric {
  final String name;
  int startCount = 0;
  int completeCount = 0;
  double totalTime = 0;
  double maxTime = 0;
  double minTime = double.infinity;
  final List<Duration> recentFrameTimes = [];
  DateTime lastUpdated = DateTime.now();

  _PerformanceMetric(this.name);

  void recordComplete(Duration duration) {
    completeCount++;
    final ms = duration.inMicroseconds / 1000;
    totalTime += ms;
    if (ms > maxTime) maxTime = ms;
    if (ms < minTime) minTime = ms;
    lastUpdated = DateTime.now();
  }

  void addFrameTime(Duration duration) {
    recentFrameTimes.add(duration);
    if (recentFrameTimes.length > 100) {
      recentFrameTimes.removeAt(0);
    }
    lastUpdated = DateTime.now();
  }

  double get averageTime => completeCount > 0 ? totalTime / completeCount : 0;

  Map<String, dynamic> toJson() => {
        'name': name,
        'startCount': startCount,
        'completeCount': completeCount,
        'averageTime': averageTime,
        'maxTime': maxTime,
        'minTime': minTime == double.infinity ? 0 : minTime,
        'recentFrameCount': recentFrameTimes.length,
      };
}

/// 测量接口
abstract class PerformanceMeasurement {
  void complete();
  void cancel();
}

/// 真实测量
class _RealMeasurement implements PerformanceMeasurement {
  final _PerformanceMetric _metric;
  final Stopwatch _stopwatch;
  bool _isComplete = false;

  _RealMeasurement(this._metric) : _stopwatch = Stopwatch()..start();

  @override
  void complete() {
    if (_isComplete) return;
    _isComplete = true;
    _stopwatch.stop();
    _metric.recordComplete(_stopwatch.elapsed);
  }

  @override
  void cancel() {
    _isComplete = true;
    _stopwatch.stop();
  }
}

/// 空测量（当监控禁用时使用）
class _NoOpMeasurement implements PerformanceMeasurement {
  @override
  void complete() {}

  @override
  void cancel() {}
}

/// 性能监控 Widget
/// 包装子组件并监控其构建性能
class PerformanceMonitorWidget extends StatelessWidget {
  final String name;
  final Widget child;
  final bool enabled;

  const PerformanceMonitorWidget({
    super.key,
    required this.name,
    required this.child,
    this.enabled = kDebugMode,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;

    final measurement = PerformanceMonitor.instance.startMeasurement(name);

    return _PerformanceMonitorScope(
      measurement: measurement,
      child: child,
    );
  }
}

class _PerformanceMonitorScope extends StatefulWidget {
  final PerformanceMeasurement measurement;
  final Widget child;

  const _PerformanceMonitorScope({
    required this.measurement,
    required this.child,
  });

  @override
  State<_PerformanceMonitorScope> createState() =>
      _PerformanceMonitorScopeState();
}

class _PerformanceMonitorScopeState extends State<_PerformanceMonitorScope> {
  @override
  void initState() {
    super.initState();
    // 下一帧完成测量
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.measurement.complete();
    });
  }

  @override
  void dispose() {
    widget.measurement.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 帧率监控 Widget
class FrameRateMonitor extends StatefulWidget {
  final Widget child;
  final ValueChanged<double>? onFpsChanged;

  const FrameRateMonitor({
    super.key,
    required this.child,
    this.onFpsChanged,
  });

  @override
  State<FrameRateMonitor> createState() => _FrameRateMonitorState();
}

class _FrameRateMonitorState extends State<FrameRateMonitor> {
  final List<Duration> _frameTimes = [];
  Timer? _fpsTimer;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), _reportFps);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _fpsTimer?.cancel();
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      final buildTime = timing.buildDuration;
      _frameTimes.add(buildTime);

      if (_frameTimes.length > 120) {
        _frameTimes.removeAt(0);
      }
    }
  }

  void _reportFps(Timer timer) {
    if (_frameTimes.isEmpty) return;

    final totalMicroseconds = _frameTimes.fold<int>(
      0,
      (sum, time) => sum + time.inMicroseconds,
    );
    final avgFrameTimeMs = totalMicroseconds / _frameTimes.length / 1000.0;

    final fps = avgFrameTimeMs > 0 ? 1000.0 / avgFrameTimeMs : 60.0;
    widget.onFpsChanged?.call(fps);

    _frameTimes.clear();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
