import 'dart:async';

import 'package:flutter/material.dart';

/// 性能优化工具类
/// 提供各种性能优化的辅助方法和 Widget
class PerformanceUtils {
  PerformanceUtils._();

  /// 缓存的 empty widget
  static const Widget emptyWidget = SizedBox.shrink();

  /// 缓存的 sliver empty widget
  static const Widget sliverEmptyWidget =
      SliverToBoxAdapter(child: SizedBox.shrink());

  /// 创建 const SizedBox 的便捷方法
  static const Widget sizedBoxZero = SizedBox.shrink();
  static const Widget sizedBoxW4 = SizedBox(width: 4);
  static const Widget sizedBoxW8 = SizedBox(width: 8);
  static const Widget sizedBoxW12 = SizedBox(width: 12);
  static const Widget sizedBoxW16 = SizedBox(width: 16);
  static const Widget sizedBoxW24 = SizedBox(width: 24);

  static const Widget sizedBoxH4 = SizedBox(height: 4);
  static const Widget sizedBoxH8 = SizedBox(height: 8);
  static const Widget sizedBoxH12 = SizedBox(height: 12);
  static const Widget sizedBoxH16 = SizedBox(height: 16);
  static const Widget sizedBoxH24 = SizedBox(height: 24);

  /// 创建 const EdgeInsets 的便捷方法
  static const EdgeInsets edgeZero = EdgeInsets.zero;
  static const EdgeInsets edgeAll4 = EdgeInsets.all(4);
  static const EdgeInsets edgeAll8 = EdgeInsets.all(8);
  static const EdgeInsets edgeAll12 = EdgeInsets.all(12);
  static const EdgeInsets edgeAll16 = EdgeInsets.all(16);

  static const EdgeInsets edgeH4 = EdgeInsets.symmetric(horizontal: 4);
  static const EdgeInsets edgeH8 = EdgeInsets.symmetric(horizontal: 8);
  static const EdgeInsets edgeH12 = EdgeInsets.symmetric(horizontal: 12);
  static const EdgeInsets edgeH16 = EdgeInsets.symmetric(horizontal: 16);

  static const EdgeInsets edgeV4 = EdgeInsets.symmetric(vertical: 4);
  static const EdgeInsets edgeV8 = EdgeInsets.symmetric(vertical: 8);
  static const EdgeInsets edgeV12 = EdgeInsets.symmetric(vertical: 12);
  static const EdgeInsets edgeV16 = EdgeInsets.symmetric(vertical: 16);

  /// 创建 const BorderRadius 的便捷方法
  static const BorderRadius radiusZero = BorderRadius.zero;
  static const BorderRadius radius4 = BorderRadius.all(Radius.circular(4));
  static const BorderRadius radius8 = BorderRadius.all(Radius.circular(8));
  static const BorderRadius radius12 = BorderRadius.all(Radius.circular(12));
  static const BorderRadius radius16 = BorderRadius.all(Radius.circular(16));

  /// 防抖函数
  /// [delay] 延迟时间
  /// [onAction] 要执行的动作
  static VoidCallback debounce(
    VoidCallback onAction, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    Timer? timer;
    return () {
      timer?.cancel();
      timer = Timer(delay, onAction);
    };
  }

  /// 节流函数
  /// [delay] 延迟时间
  /// [onAction] 要执行的动作
  static VoidCallback throttle(
    VoidCallback onAction, {
    Duration delay = const Duration(milliseconds: 300),
  }) {
    bool isThrottled = false;
    return () {
      if (isThrottled) return;
      isThrottled = true;
      onAction();
      Future.delayed(delay, () => isThrottled = false);
    };
  }
}

/// 防抖 StatefulWidget
class DebouncedWidget extends StatefulWidget {
  final Widget child;
  final Duration debounceTime;
  final VoidCallback onBuild;

  const DebouncedWidget({
    super.key,
    required this.child,
    required this.onBuild,
    this.debounceTime = const Duration(milliseconds: 100),
  });

  @override
  State<DebouncedWidget> createState() => _DebouncedWidgetState();
}

class _DebouncedWidgetState extends State<DebouncedWidget> {
  Timer? _debounceTimer;

  @override
  void didUpdateWidget(DebouncedWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounceTime, widget.onBuild);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// 防止 rebuild 的 Widget
/// 当 child 没有变化时，不会触发重建
class ConstWidget extends StatelessWidget {
  final Widget child;

  const ConstWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}
