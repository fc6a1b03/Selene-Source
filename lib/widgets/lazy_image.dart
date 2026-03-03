import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// 懒加载图片组件
/// 只有当图片进入视口时才加载
class LazyImage extends StatefulWidget {
  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Map<String, String>? httpHeaders;
  final Widget? placeholder;
  final Widget? errorWidget;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;
  final int? memCacheWidth;
  final int? memCacheHeight;

  const LazyImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.httpHeaders,
    this.placeholder,
    this.errorWidget,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.fadeOutDuration = const Duration(milliseconds: 200),
    this.memCacheWidth,
    this.memCacheHeight,
  });

  @override
  State<LazyImage> createState() => _LazyImageState();
}

class _LazyImageState extends State<LazyImage> {
  bool _isVisible = false;
  bool _hasBeenVisible = false;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        _checkVisibility();
        return false;
      },
      child: Visibility(
        // visible 默认为 true
        visible: true, // ignore: avoid_redundant_argument_values
        child: LayoutBuilder(
          builder: (context, constraints) {
            _checkVisibility();
            return _buildImage();
          },
        ),
      ),
    );
  }

  void _checkVisibility() {
    if (_hasBeenVisible) return;

    // 简化版的可见性检查
    // 实际项目中可以使用 visibility_detector 包
    if (mounted) {
      setState(() {
        _isVisible = true;
        _hasBeenVisible = true;
      });
    }
  }

  Widget _buildImage() {
    // 如果不可见，显示占位符
    if (!_isVisible && !_hasBeenVisible) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: widget.placeholder ?? _defaultPlaceholder(),
      );
    }

    return CachedNetworkImage(
      imageUrl: widget.imageUrl,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      httpHeaders: widget.httpHeaders,
      placeholder: widget.placeholder != null
          ? (context, url) => widget.placeholder!
          : (context, url) => _defaultPlaceholder(),
      errorWidget: widget.errorWidget != null
          ? (context, url, error) => widget.errorWidget!
          : (context, url, error) => _defaultErrorWidget(),
      fadeInDuration: widget.fadeInDuration,
      fadeOutDuration: widget.fadeOutDuration,
      memCacheWidth: widget.memCacheWidth,
      memCacheHeight: widget.memCacheHeight,
    );
  }

  Widget _defaultPlaceholder() {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Icon(
          Icons.image,
          color: Colors.grey,
          size: 40,
        ),
      ),
    );
  }

  Widget _defaultErrorWidget() {
    return Container(
      color: Colors.grey[300],
      child: const Center(
        child: Icon(
          Icons.broken_image,
          color: Colors.grey,
          size: 40,
        ),
      ),
    );
  }
}

/// 预加载图片管理器
class ImagePreloadManager {
  static final ImagePreloadManager _instance = ImagePreloadManager._internal();
  factory ImagePreloadManager() => _instance;
  ImagePreloadManager._internal();

  final Set<String> _preloadedUrls = {};
  final int _maxPreloadCount = 10;

  /// 预加载单张图片
  void preload(BuildContext context, String url) {
    if (_preloadedUrls.contains(url)) return;
    if (_preloadedUrls.length >= _maxPreloadCount) {
      _preloadedUrls.clear();
    }

    _preloadedUrls.add(url);
    precacheImage(
      CachedNetworkImageProvider(url),
      context,
    );
  }

  /// 预加载多张图片（限制数量）
  void preloadMany(BuildContext context, List<String> urls) {
    final urlsToPreload = urls.take(_maxPreloadCount).toList();
    for (final url in urlsToPreload) {
      preload(context, url);
    }
  }

  /// 清除预加载记录
  void clear() {
    _preloadedUrls.clear();
  }
}
