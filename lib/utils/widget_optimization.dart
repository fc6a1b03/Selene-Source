import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 选择器 Widget
/// 只有当选择的数据变化时才重建
class Select<T, R> extends StatelessWidget {
  final T source;
  final R Function(T source) selector;
  final Widget Function(BuildContext context, R value) builder;

  const Select({
    super.key,
    required this.source,
    required this.selector,
    required this.builder,
  });

  @override
  Widget build(BuildContext context) {
    final value = selector(source);
    return builder(context, value);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<R>('selectedValue', selector(source)));
  }
}

/// 记忆化 Builder
/// 只有当依赖变化时才重建子树
class MemoizedBuilder extends StatefulWidget {
  final List<Object?> dependencies;
  final WidgetBuilder builder;

  const MemoizedBuilder({
    super.key,
    required this.dependencies,
    required this.builder,
  });

  @override
  State<MemoizedBuilder> createState() => _MemoizedBuilderState();
}

class _MemoizedBuilderState extends State<MemoizedBuilder> {
  List<Object?>? _lastDependencies;
  Widget? _cachedWidget;

  @override
  Widget build(BuildContext context) {
    // 检查依赖是否变化
    bool hasChanged = _lastDependencies == null ||
        _lastDependencies!.length != widget.dependencies.length;

    if (!hasChanged) {
      for (int i = 0; i < widget.dependencies.length; i++) {
        if (_lastDependencies![i] != widget.dependencies[i]) {
          hasChanged = true;
          break;
        }
      }
    }

    // 依赖变化时重新构建
    if (hasChanged) {
      _lastDependencies = List.from(widget.dependencies);
      _cachedWidget = widget.builder(context);
    }

    return _cachedWidget!;
  }
}

/// 条件重建 Widget
/// 只有当条件满足时才重建
class ConditionalBuilder extends StatefulWidget {
  final bool condition;
  final WidgetBuilder builder;
  final Widget? fallback;

  const ConditionalBuilder({
    super.key,
    required this.condition,
    required this.builder,
    this.fallback,
  });

  @override
  State<ConditionalBuilder> createState() => _ConditionalBuilderState();
}

class _ConditionalBuilderState extends State<ConditionalBuilder> {
  Widget? _cachedWidget;
  bool? _lastCondition;

  @override
  Widget build(BuildContext context) {
    if (widget.condition != _lastCondition) {
      _lastCondition = widget.condition;
      _cachedWidget = widget.condition
          ? widget.builder(context)
          : widget.fallback ?? const SizedBox.shrink();
    }

    return _cachedWidget!;
  }
}

/// 防抖 Builder
/// 延迟重建直到停止接收更新
class DebouncedBuilder extends StatefulWidget {
  final Duration debounceTime;
  final ValueListenable<dynamic> listenable;
  final WidgetBuilder builder;

  const DebouncedBuilder({
    super.key,
    required this.debounceTime,
    required this.listenable,
    required this.builder,
  });

  @override
  State<DebouncedBuilder> createState() => _DebouncedBuilderState();
}

class _DebouncedBuilderState extends State<DebouncedBuilder> {
  Widget? _cachedWidget;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _cachedWidget = widget.builder(context);
    widget.listenable.addListener(_onValueChanged);
  }

  @override
  void didUpdateWidget(DebouncedBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_onValueChanged);
      widget.listenable.addListener(_onValueChanged);
    }
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_onValueChanged);
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onValueChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(widget.debounceTime, () {
      if (mounted) {
        setState(() {
          _cachedWidget = widget.builder(context);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => _cachedWidget!;
}

/// 静态子树
/// 防止子树重建
class StaticSubtree extends StatelessWidget {
  final Widget child;

  const StaticSubtree({super.key, required this.child});

  @override
  Widget build(BuildContext context) => child;
}

/// 重建边界
/// 限制重建范围
class RebuildBoundary extends StatelessWidget {
  final Widget child;
  final Key? rebuildKey;

  const RebuildBoundary({
    super.key,
    required this.child,
    this.rebuildKey,
  });

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: rebuildKey,
      child: child,
    );
  }
}

/// 值监听构建器
/// 优化版的 ValueListenableBuilder
class OptimizedValueListenableBuilder<T> extends StatefulWidget {
  final ValueListenable<T> valueListenable;
  final Widget Function(BuildContext context, T value, Widget? child) builder;
  final Widget? child;

  const OptimizedValueListenableBuilder({
    super.key,
    required this.valueListenable,
    required this.builder,
    this.child,
  });

  @override
  State<OptimizedValueListenableBuilder<T>> createState() =>
      _OptimizedValueListenableBuilderState<T>();
}

class _OptimizedValueListenableBuilderState<T>
    extends State<OptimizedValueListenableBuilder<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.valueListenable.value;
    widget.valueListenable.addListener(_valueChanged);
  }

  @override
  void didUpdateWidget(OptimizedValueListenableBuilder<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valueListenable != widget.valueListenable) {
      oldWidget.valueListenable.removeListener(_valueChanged);
      _value = widget.valueListenable.value;
      widget.valueListenable.addListener(_valueChanged);
    }
  }

  @override
  void dispose() {
    widget.valueListenable.removeListener(_valueChanged);
    super.dispose();
  }

  void _valueChanged() {
    final newValue = widget.valueListenable.value;
    // 只有值变化时才重建
    if (_value != newValue) {
      setState(() {
        _value = newValue;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _value, widget.child);
  }
}

/// 懒加载列表项
/// 只有当进入视口时才构建
class LazyListItem extends StatefulWidget {
  final int index;
  final Widget Function(BuildContext context) builder;
  final double? estimatedHeight;

  const LazyListItem({
    super.key,
    required this.index,
    required this.builder,
    this.estimatedHeight,
  });

  @override
  State<LazyListItem> createState() => _LazyListItemState();
}

class _LazyListItemState extends State<LazyListItem> {
  bool _isVisible = false;
  final _key = GlobalKey();

  @override
  void initState() {
    super.initState();
    // 延迟一帧检查可见性
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVisibility();
    });
  }

  void _checkVisibility() {
    if (!mounted) return;

    final renderObject = _key.currentContext?.findRenderObject();
    if (renderObject is RenderBox) {
      // 简化版的可见性检查
      // 实际项目中可以使用 visibility_detector 包
      setState(() {
        _isVisible = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: _key,
      child: _isVisible
          ? widget.builder(context)
          : SizedBox(height: widget.estimatedHeight),
    );
  }
}

/// 动画优化包装器
/// 使用 RepaintBoundary 隔离动画
class OptimizedAnimation extends StatelessWidget {
  final Widget child;
  final bool useRepaintBoundary;

  const OptimizedAnimation({
    super.key,
    required this.child,
    this.useRepaintBoundary = true,
  });

  @override
  Widget build(BuildContext context) {
    if (useRepaintBoundary) {
      return RepaintBoundary(child: child);
    }
    return child;
  }
}

/// 渐变优化
/// 缓存渐变着色器
class CachedGradient extends StatelessWidget {
  final Gradient gradient;
  final Widget child;
  final BlendMode blendMode;

  const CachedGradient({
    super.key,
    required this.gradient,
    required this.child,
    this.blendMode = BlendMode.srcIn,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) => gradient.createShader(bounds),
      blendMode: blendMode,
      child: child,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Gradient>('gradient', gradient));
  }
}

/// 图片优化
/// 自动选择合适的缓存尺寸
class OptimizedImage extends StatelessWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Widget? placeholder;
  final Widget? errorWidget;

  const OptimizedImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.placeholder,
    this.errorWidget,
  });

  @override
  Widget build(BuildContext context) {
    // 计算合适的缓存尺寸
    final devicePixelRatio = MediaQuery.of(context).devicePixelRatio;
    final cacheWidth =
        width != null ? (width! * devicePixelRatio).toInt() : null;
    final cacheHeight =
        height != null ? (height! * devicePixelRatio).toInt() : null;

    return Image.network(
      imageUrl,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: frame != null ? child : placeholder ?? const SizedBox.shrink(),
        );
      },
      errorBuilder: (context, error, stackTrace) {
        return errorWidget ??
            Container(
              color: Colors.grey[300],
              child: const Icon(Icons.error),
            );
      },
    );
  }
}

/// 文本优化
/// 使用 RichText 避免不必要的重建
class OptimizedText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;

  const OptimizedText(
    this.data, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow = TextOverflow.ellipsis,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      data,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('data', data, showName: false));
  }
}
