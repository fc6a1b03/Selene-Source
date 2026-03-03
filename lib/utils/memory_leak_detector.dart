import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 内存泄漏检测器
/// 用于检测和防止内存泄漏
class MemoryLeakDetector {
  static final MemoryLeakDetector _instance = MemoryLeakDetector._internal();
  static MemoryLeakDetector get instance => _instance;
  MemoryLeakDetector._internal();

  bool _isEnabled = kDebugMode;
  final Map<String, _TrackedObject> _trackedObjects = {};
  Timer? _cleanupTimer;

  /// 启用/禁用检测
  void setEnabled({required bool enabled}) {
    _isEnabled = enabled;
    if (enabled) {
      _startCleanupTimer();
    } else {
      _cleanupTimer?.cancel();
    }
  }

  /// 追踪对象
  void trackObject(String key, Object object, {String? description}) {
    if (!_isEnabled) return;

    _trackedObjects[key] = _TrackedObject(
      object: object,
      description: description ?? key,
      trackedAt: DateTime.now(),
    );
  }

  /// 取消追踪
  void untrackObject(String key) {
    _trackedObjects.remove(key);
  }

  /// 检查泄漏
  void checkLeaks() {
    if (!_isEnabled) return;

    final now = DateTime.now();
    final leaks = <String>[];

    _trackedObjects.forEach((key, tracked) {
      final age = now.difference(tracked.trackedAt);
      if (age > const Duration(minutes: 5)) {
        // 5分钟未释放可能是泄漏
        leaks.add('${tracked.description} (age: ${age.inMinutes}m)');
      }
    });

    if (leaks.isNotEmpty) {
      developer.log(
        '⚠️ Potential memory leaks detected:\n${leaks.join('\n')}',
        name: 'MemoryLeakDetector',
      );
    }
  }

  /// 获取报告
  Map<String, dynamic> getReport() {
    final now = DateTime.now();
    return {
      'trackedCount': _trackedObjects.length,
      'objects': _trackedObjects.map((key, tracked) => MapEntry(
            key,
            {
              'description': tracked.description,
              'age': now.difference(tracked.trackedAt).inSeconds,
            },
          )),
    };
  }

  void _startCleanupTimer() {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      checkLeaks();
    });
  }

  /// 清除所有追踪
  void clear() {
    _trackedObjects.clear();
  }
}

class _TrackedObject {
  final Object object;
  final String description;
  final DateTime trackedAt;

  _TrackedObject({
    required this.object,
    required this.description,
    required this.trackedAt,
  });
}

/// 自动释放 Mixin
/// 用于自动管理资源释放
mixin AutoDisposeMixin<T extends StatefulWidget> on State<T> {
  final List<VoidCallback> _disposeCallbacks = [];
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final List<Timer> _timers = [];
  final List<AnimationController> _animationControllers = [];
  final List<TextEditingController> _textControllers = [];
  final List<ScrollController> _scrollControllers = [];
  final List<PageController> _pageControllers = [];
  final List<TabController> _tabControllers = [];

  /// 添加释放回调
  void addDisposeCallback(VoidCallback callback) {
    _disposeCallbacks.add(callback);
  }

  /// 自动管理 StreamSubscription
  void autoDispose(StreamSubscription<dynamic> subscription) {
    _subscriptions.add(subscription);
  }

  /// 自动管理 Timer
  void autoDisposeTimer(Timer timer) {
    _timers.add(timer);
  }

  /// 自动管理 AnimationController
  void autoDisposeAnimation(AnimationController controller) {
    _animationControllers.add(controller);
  }

  /// 自动管理 TextEditingController
  void autoDisposeTextController(TextEditingController controller) {
    _textControllers.add(controller);
  }

  /// 自动管理 ScrollController
  void autoDisposeScrollController(ScrollController controller) {
    _scrollControllers.add(controller);
  }

  /// 自动管理 PageController
  void autoDisposePageController(PageController controller) {
    _pageControllers.add(controller);
  }

  /// 自动管理 TabController
  void autoDisposeTabController(TabController controller) {
    _tabControllers.add(controller);
  }

  @override
  void dispose() {
    // 取消所有订阅
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();

    // 取消所有定时器
    for (final timer in _timers) {
      timer.cancel();
    }
    _timers.clear();

    // 释放动画控制器
    for (final controller in _animationControllers) {
      controller.dispose();
    }
    _animationControllers.clear();

    // 释放文本控制器
    for (final controller in _textControllers) {
      controller.dispose();
    }
    _textControllers.clear();

    // 释放滚动控制器
    for (final controller in _scrollControllers) {
      controller.dispose();
    }
    _scrollControllers.clear();

    // 释放页面控制器
    for (final controller in _pageControllers) {
      controller.dispose();
    }
    _pageControllers.clear();

    // 释放 Tab 控制器
    for (final controller in _tabControllers) {
      controller.dispose();
    }
    _tabControllers.clear();

    // 执行其他释放回调
    for (final callback in _disposeCallbacks) {
      callback();
    }
    _disposeCallbacks.clear();

    super.dispose();
  }
}

/// 安全的 StreamBuilder
/// 自动处理流订阅和状态检查
class SafeStreamBuilder<T> extends StatefulWidget {
  final Stream<T> stream;
  final T? initialData;
  final AsyncWidgetBuilder<T> builder;

  const SafeStreamBuilder({
    super.key,
    required this.stream,
    this.initialData,
    required this.builder,
  });

  @override
  State<SafeStreamBuilder<T>> createState() => _SafeStreamBuilderState<T>();
}

class _SafeStreamBuilderState<T> extends State<SafeStreamBuilder<T>> {
  StreamSubscription<T>? _subscription;
  T? _data;
  // ignore: unused_field
  Object? _error;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;
    _subscribe();
  }

  @override
  void didUpdateWidget(SafeStreamBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stream != widget.stream) {
      _unsubscribe();
      _subscribe();
    }
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  void _subscribe() {
    _subscription = widget.stream.listen(
      (data) {
        if (mounted) {
          setState(() {
            _data = data;
            _error = null;
          });
        }
      },
      onError: (Object error) {
        if (mounted) {
          setState(() {
            _error = error;
          });
        }
      },
    );
  }

  void _unsubscribe() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      AsyncSnapshot<T>.withData(
        ConnectionState.active,
        _data as T,
      ),
    );
  }
}

/// 弱引用包装
/// 用于避免循环引用
class WeakReference<T extends Object> {
  final T _target;
  bool _isDisposed = false;

  WeakReference(this._target);

  T? get target => _isDisposed ? null : _target;

  void dispose() {
    _isDisposed = true;
  }
}

/// 对象池
/// 复用对象减少内存分配
class ObjectPool<T> {
  final int maxSize;
  final T Function() factory;
  final void Function(T)? reset;

  final List<T> _available = [];
  final List<T> _inUse = [];

  ObjectPool({
    required this.factory,
    this.reset,
    this.maxSize = 10,
  });

  /// 获取对象
  T acquire() {
    if (_available.isNotEmpty) {
      final obj = _available.removeLast();
      _inUse.add(obj);
      return obj;
    }

    if (_inUse.length >= maxSize) {
      throw StateError('Object pool exhausted');
    }

    final obj = factory();
    _inUse.add(obj);
    return obj;
  }

  /// 释放对象
  void release(T obj) {
    _inUse.remove(obj);
    reset?.call(obj);

    if (_available.length < maxSize) {
      _available.add(obj);
    }
  }

  /// 清除所有对象
  void clear() {
    _available.clear();
    _inUse.clear();
  }

  /// 获取统计
  Map<String, int> getStats() => {
        'available': _available.length,
        'inUse': _inUse.length,
        'maxSize': maxSize,
      };
}
