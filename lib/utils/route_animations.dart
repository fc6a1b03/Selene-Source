import 'package:flutter/material.dart';

/// 轻量级路由动画
/// 提供高性能的页面切换动画
class RouteAnimations {
  RouteAnimations._();

  /// 无动画路由 - 最快的切换
  static PageRouteBuilder<T> noAnimation<T>(
    Widget page, {
    RouteSettings? settings,
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (_, __, ___) => page,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
  }

  /// 淡入淡出动画 - 轻量级
  static PageRouteBuilder<T> fade<T>(
    Widget page, {
    RouteSettings? settings,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeInOut,
          ),
          child: child,
        );
      },
      transitionDuration: duration,
      reverseTransitionDuration: duration,
    );
  }

  /// 滑动动画 - 平台风格
  static PageRouteBuilder<T> slide<T>(
    Widget page, {
    RouteSettings? settings,
    Duration duration = const Duration(milliseconds: 250),
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        const begin = Offset(1.0, 0.0);
        const end = Offset.zero;
        const curve = Curves.easeInOutCubic;

        final tween = Tween(begin: begin, end: end).chain(
          CurveTween(curve: curve),
        );

        return SlideTransition(
          position: animation.drive(tween),
          child: child,
        );
      },
      transitionDuration: duration,
      reverseTransitionDuration: duration,
    );
  }

  /// 缩放动画 - 适合弹窗
  static PageRouteBuilder<T> scale<T>(
    Widget page, {
    RouteSettings? settings,
    Duration duration = const Duration(milliseconds: 200),
  }) {
    return PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, animation, __, child) {
        return ScaleTransition(
          scale: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: child,
        );
      },
      transitionDuration: duration,
      reverseTransitionDuration: duration,
    );
  }
}

/// 高性能页面路由
/// 使用 RepaintBoundary 减少重绘
class OptimizedPageRoute<T> extends MaterialPageRoute<T> {
  OptimizedPageRoute({
    required super.builder,
    super.settings,
    super.maintainState,
    super.fullscreenDialog,
  });

  @override
  Widget buildContent(BuildContext context) {
    // 使用 RepaintBoundary 隔离页面重绘
    return RepaintBoundary(
      child: super.buildContent(context),
    );
  }

  @override
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);
}

/// 自定义导航器观察者
/// 用于监控页面切换性能
class PerformanceNavigatorObserver extends NavigatorObserver {
  final void Function(String from, String to, Duration duration)? onPageChange;

  PerformanceNavigatorObserver({this.onPageChange});

  DateTime? _routeStartTime;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routeStartTime = DateTime.now();
    super.didPush(route, previousRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _reportTransition(previousRoute?.settings.name, route.settings.name);
    super.didPop(route, previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _reportTransition(oldRoute?.settings.name, newRoute?.settings.name);
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
  }

  void _reportTransition(String? from, String? to) {
    if (_routeStartTime != null) {
      final duration = DateTime.now().difference(_routeStartTime!);
      onPageChange?.call(from ?? 'unknown', to ?? 'unknown', duration);
      debugPrint(
          'Page transition: $from -> $to (${duration.inMilliseconds}ms)');
    }
  }
}

/// 保持页面状态的 Mixin
/// 用于 Tab 切换时保持页面状态
mixin KeepAlivePageMixin<T extends StatefulWidget> on State<T> {
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    return buildContent(context);
  }

  Widget buildContent(BuildContext context);
}

/// 页面切换动画配置
class PageTransitionConfig {
  /// 是否启用动画
  final bool enabled;

  /// 动画持续时间
  final Duration duration;

  /// 动画类型
  final PageTransitionType type;

  const PageTransitionConfig({
    this.enabled = true,
    this.duration = const Duration(milliseconds: 250),
    this.type = PageTransitionType.fade,
  });

  /// 默认配置
  static const defaultConfig = PageTransitionConfig();

  /// 无动画配置（最高性能）
  static const noAnimation = PageTransitionConfig(enabled: false);

  /// 快速动画配置
  static const fast = PageTransitionConfig(
    duration: Duration(milliseconds: 150),
    type: PageTransitionType.fade, // ignore: avoid_redundant_argument_values
  );
}

enum PageTransitionType {
  fade,
  slide,
  scale,
  none,
}
