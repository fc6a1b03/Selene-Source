import 'dart:async';

import 'package:flutter/material.dart';

/// 应用启动优化器
/// 管理启动时任务的优先级和延迟执行
class AppStartupOptimizer {
  static final AppStartupOptimizer _instance = AppStartupOptimizer._internal();
  factory AppStartupOptimizer() => _instance;
  AppStartupOptimizer._internal();

  final List<_StartupTask> _tasks = [];
  bool _isRunning = false;

  /// 添加启动任务
  ///
  /// [task] 要执行的任务
  /// [priority] 优先级（0-100，数字越大优先级越高）
  /// [delay] 延迟执行时间
  void addTask(
    FutureOr<void> Function() task, {
    int priority = 50,
    Duration delay = Duration.zero,
    String? name,
  }) {
    _tasks.add(_StartupTask(
      task: task,
      priority: priority,
      delay: delay,
      name: name,
    ));
  }

  /// 按优先级排序并执行所有任务
  Future<void> runTasks() async {
    if (_isRunning) return;
    _isRunning = true;

    // 按优先级排序
    _tasks.sort((a, b) => b.priority.compareTo(a.priority));

    for (final task in _tasks) {
      if (task.delay > Duration.zero) {
        await Future<void>.delayed(task.delay);
      }

      try {
        await task.task();
      } catch (e) {
        debugPrint('Startup task ${task.name ?? "unknown"} failed: $e');
      }
    }

    _tasks.clear();
    _isRunning = false;
  }

  /// 清除所有任务
  void clear() {
    _tasks.clear();
  }
}

class _StartupTask {
  final FutureOr<void> Function() task;
  final int priority;
  final Duration delay;
  final String? name;

  _StartupTask({
    required this.task,
    required this.priority,
    required this.delay,
    this.name,
  });
}

/// 延迟加载 Widget
/// 在首次需要时才创建实际 Widget
class DeferredWidget extends StatefulWidget {
  final Widget Function() builder;
  final Widget? placeholder;
  final Duration delay;

  const DeferredWidget({
    super.key,
    required this.builder,
    this.placeholder,
    this.delay = const Duration(milliseconds: 50),
  });

  @override
  State<DeferredWidget> createState() => _DeferredWidgetState();
}

class _DeferredWidgetState extends State<DeferredWidget> {
  Widget? _actualWidget;
  // ignore: unused_field
  bool _isBuilding = false;

  @override
  void initState() {
    super.initState();
    _scheduleBuild();
  }

  void _scheduleBuild() {
    Future.delayed(widget.delay, () {
      if (!mounted) return;
      setState(() {
        _isBuilding = true;
      });

      // 下一帧构建实际 Widget
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _actualWidget = widget.builder();
          _isBuilding = false;
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_actualWidget != null) {
      return _actualWidget!;
    }

    return widget.placeholder ?? const SizedBox.shrink();
  }
}

/// 分帧加载器
/// 将大量子组件分散到多帧渲染，避免卡顿
class FrameSplitLoader extends StatefulWidget {
  final List<Widget> children;
  final int itemsPerFrame;
  final Widget? loadingPlaceholder;

  const FrameSplitLoader({
    super.key,
    required this.children,
    this.itemsPerFrame = 10,
    this.loadingPlaceholder,
  });

  @override
  State<FrameSplitLoader> createState() => _FrameSplitLoaderState();
}

class _FrameSplitLoaderState extends State<FrameSplitLoader> {
  final List<Widget> _loadedChildren = [];
  int _currentIndex = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNextBatch();
  }

  void _loadNextBatch() {
    if (_currentIndex >= widget.children.length) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final endIndex = (_currentIndex + widget.itemsPerFrame)
          .clamp(0, widget.children.length);
      final batch = widget.children.sublist(_currentIndex, endIndex);

      setState(() {
        _loadedChildren.addAll(batch);
        _currentIndex = endIndex;
      });

      // 继续加载下一批
      if (_currentIndex < widget.children.length) {
        _loadNextBatch();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ..._loadedChildren,
        if (_isLoading) widget.loadingPlaceholder ?? const SizedBox.shrink(),
      ],
    );
  }
}

/// 预加载管理器
/// 管理需要预加载的资源
class PreloadManager {
  static final PreloadManager _instance = PreloadManager._internal();
  factory PreloadManager() => _instance;
  PreloadManager._internal();

  final Set<String> _preloadedAssets = {};
  final int _maxConcurrent = 3;
  int _currentLoading = 0;
  final List<_PreloadTask> _queue = [];

  /// 预加载图片
  void preloadImage(BuildContext context, String url) {
    if (_preloadedAssets.contains(url)) return;

    final task = _PreloadTask(url: url, context: context);
    _queue.add(task);
    _processQueue();
  }

  /// 批量预加载
  void preloadImages(BuildContext context, List<String> urls) {
    for (final url in urls.take(10)) {
      // 限制预加载数量
      preloadImage(context, url);
    }
  }

  void _processQueue() async {
    if (_currentLoading >= _maxConcurrent || _queue.isEmpty) return;

    _currentLoading++;
    final task = _queue.removeAt(0);

    try {
      await precacheImage(
        NetworkImage(task.url),
        task.context,
      );
      _preloadedAssets.add(task.url);
    } catch (e) {
      debugPrint('Preload failed: $e');
    } finally {
      _currentLoading--;
      if (_queue.isNotEmpty) {
        _processQueue();
      }
    }
  }

  /// 清除预加载记录
  void clear() {
    _preloadedAssets.clear();
    _queue.clear();
  }
}

class _PreloadTask {
  final String url;
  final BuildContext context;

  _PreloadTask({required this.url, required this.context});
}
