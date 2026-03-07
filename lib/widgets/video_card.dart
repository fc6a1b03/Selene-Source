import 'package:async/async.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:selene/components/animations/modern_badge.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/models/search_result.dart';
import 'package:selene/models/video_info.dart';
import 'package:selene/services/theme_service.dart';
import 'package:selene/utils/device_utils.dart';
import 'package:selene/utils/image_url.dart';
import 'package:selene/widgets/video_menu_bottom_sheet.dart';

/// 现代化视频卡片组件
///
/// 采用 2026 设计系统：
/// - 圆角玻璃拟态效果
/// - 霓虹悬停光效
/// - 流畅的动画过渡
/// - 现代化的徽章和指示器
class VideoCard extends StatefulWidget {
  final VideoInfo videoInfo;
  final VoidCallback? onTap;
  final String from;
  final double? cardWidth;
  final void Function(VideoMenuAction)? onGlobalMenuAction;
  final bool isFavorited;
  final List<SearchResult>? originalResults;
  final void Function(SearchResult)? onSourceSelected;

  const VideoCard({
    super.key,
    required this.videoInfo,
    this.onTap,
    this.from = 'playrecord',
    this.cardWidth,
    this.onGlobalMenuAction,
    this.isFavorited = false,
    this.originalResults,
    this.onSourceSelected,
  });

  @override
  State<VideoCard> createState() => _VideoCardState();
}

class _VideoCardState extends State<VideoCard> {
  final ValueNotifier<bool> _isHovered = ValueNotifier<bool>(false);
  AsyncMemoizer<String>? _imageUrlMemoizer;

  @override
  void initState() {
    super.initState();
    _initImageUrlFuture();
  }

  void _initImageUrlFuture() {
    _imageUrlMemoizer = AsyncMemoizer();
    _imageUrlMemoizer!.runOnce(
        () => getImageUrl(widget.videoInfo.cover, widget.videoInfo.source));
  }

  @override
  void didUpdateWidget(VideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只在封面或来源变化时重新获取
    if (oldWidget.videoInfo.cover != widget.videoInfo.cover ||
        oldWidget.videoInfo.source != widget.videoInfo.source) {
      // 重新初始化 memoizer
      _initImageUrlFuture();
    }
  }

  @override
  void dispose() {
    _isHovered.dispose();
    super.dispose();
  }

  Future<String> get _imageUrlFuture => _imageUrlMemoizer!.future;

  @override
  Widget build(BuildContext context) {
    final isPC = DeviceUtils.isPC();
    // 使用 Selector 只监听 isDarkMode，避免主题其他变化时重建
    final isDark = context.select<ThemeService, bool>((s) => s.isDarkMode);

    // 卡片尺寸
    final width = widget.cardWidth ?? 140.0;
    final height = width * 1.4;

    // 缓存计算结果
    final shouldShowEpisodeInfo = _shouldShowEpisodeInfo();
    final shouldShowProgress = _shouldShowProgress();
    final episodeText = shouldShowEpisodeInfo ? _getEpisodeText() : '';

    return FutureBuilder<String>(
      future: _imageUrlFuture,
      builder: (context, snapshot) {
        final imageUrl = snapshot.data ?? widget.videoInfo.cover;
        final headers =
            getImageRequestHeaders(imageUrl, widget.videoInfo.source);

        // 使用 AnimatedBuilder 监听 _isHovered 变化，避免频繁 setState
        return AnimatedBuilder(
          animation: _isHovered,
          builder: (context, _) {
            final isHovered = _isHovered.value;

            Widget card = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 封面区域
                _buildCover(
                  width: width,
                  height: height,
                  imageUrl: imageUrl,
                  headers: headers,
                  isDark: isDark,
                  isPC: isPC,
                  shouldShowEpisodeInfo: shouldShowEpisodeInfo,
                  shouldShowProgress: shouldShowProgress,
                  episodeText: episodeText,
                  isHovered: isHovered,
                ),
                const SizedBox(height: 10),
                // 标题区域
                _buildTitle(
                    width: width,
                    isDark: isDark,
                    isPC: isPC,
                    isHovered: isHovered),
              ],
            );

            // 添加悬停/点击效果
            if (isPC) {
              card = _buildPCInteraction(card, isHovered);
            } else {
              card = _buildMobileInteraction(card);
            }

            return SizedBox(
              width: width,
              child: card,
            );
          },
        );
      },
    );
  }

  /// 构建封面区域
  Widget _buildCover({
    required double width,
    required double height,
    required String imageUrl,
    required Map<String, String>? headers,
    required bool isDark,
    required bool isPC,
    required bool shouldShowEpisodeInfo,
    required bool shouldShowProgress,
    required String episodeText,
    required bool isHovered,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkElevated : AppColors.lightElevated,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isHovered ? AppShadows.neonGradient : AppShadows.medium,
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 封面图片
            _buildImage(imageUrl: imageUrl, headers: headers, isDark: isDark),

            // 悬停渐变遮罩
            if (isPC)
              AnimatedOpacity(
                opacity: isHovered ? 1.0 : 0.0,
                duration: AppAnimations.fast,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                      stops: const [0.4, 1.0],
                    ),
                  ),
                ),
              ),

            // 年份徽章
            if ((widget.from == 'search' || widget.from == 'agg') &&
                widget.videoInfo.year.isNotEmpty &&
                widget.videoInfo.year != 'unknown')
              Positioned(
                top: 10,
                left: 10,
                child: ModernBadge.gradient(
                  widget.videoInfo.year,
                  gradient: AppColors.techGradient,
                ),
              ),

            // 评分徽章（豆瓣/Bangumi模式）
            if ((widget.from == 'douban' || widget.from == 'bangumi') &&
                _shouldShowRating())
              Positioned(
                top: 10,
                right: 10,
                child:
                    RatingBadge(rating: double.parse(widget.videoInfo.rate!)),
              )
            // 集数徽章
            else if (shouldShowEpisodeInfo)
              Positioned(
                top: 10,
                right: 10,
                child: ModernBadge(
                  text: episodeText,
                  backgroundColor: AppColors.success,
                ),
              ),

            // 进度条
            if (shouldShowProgress)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _buildProgressBar(isDark: isDark),
              ),

            // 悬停操作按钮（PC）
            if (isPC && isHovered) _buildHoverActions(isDark: isDark),
          ],
        ),
      ),
    );
  }

  /// 构建图片 - 优化版本，添加内存缓存限制
  Widget _buildImage({
    required String imageUrl,
    required Map<String, String>? headers,
    required bool isDark,
  }) {
    // 计算合适的缓存尺寸
    final width = widget.cardWidth ?? 140.0;
    final height = width * 1.4;

    // 限制缓存尺寸，避免内存占用过大
    // 使用物理像素尺寸，考虑 2x 和 3x 设备
    final cacheWidth = (width * 3).toInt();
    final cacheHeight = (height * 3).toInt();

    return CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      cacheKey: imageUrl,
      httpHeaders: headers,
      // 限制内存缓存大小
      memCacheWidth: cacheWidth,
      memCacheHeight: cacheHeight,
      placeholder: (context, url) => ShimmerAnimation(
        child: Container(
          color: isDark ? AppColors.darkElevated : AppColors.lightElevated,
        ),
      ),
      errorWidget: (context, url, error) => ColoredBox(
        color: isDark ? AppColors.darkElevated : AppColors.lightElevated,
        child: Icon(
          LucideIcons.film,
          color:
              isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
          size: 40,
        ),
      ),
      fadeInDuration: AppAnimations.medium,
      fadeOutDuration: AppAnimations.fast,
    );
  }

  /// 构建进度条
  Widget _buildProgressBar({required bool isDark}) {
    return Container(
      height: 4,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(2),
      ),
      child: FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widget.videoInfo.progressPercentage,
        child: Container(
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  /// 构建悬停操作按钮
  Widget _buildHoverActions({required bool isDark}) {
    final width = widget.cardWidth ?? 140.0;
    // 根据卡片宽度调整按钮大小
    final isSmall = width < 150;
    final primarySize = isSmall ? 44.0 : 52.0;
    final secondarySize = isSmall ? 36.0 : 40.0;
    final spacing = isSmall ? 8.0 : 12.0;

    return Positioned.fill(
      child: Center(
        child: Wrap(
          spacing: spacing,
          alignment: WrapAlignment.center,
          children: [
            // 播放按钮
            _buildActionButton(
              icon: LucideIcons.play,
              onTap: widget.onTap,
              isPrimary: true,
              size: primarySize,
            ),
            if (widget.from == 'playrecord') ...[
              // 收藏按钮
              _buildActionButton(
                icon:
                    widget.isFavorited ? LucideIcons.heart : LucideIcons.heart,
                onTap: _handleFavoriteButtonTap,
                color: widget.isFavorited ? AppColors.error : null,
                size: secondarySize,
              ),
              // 删除按钮
              _buildActionButton(
                icon: LucideIcons.trash2,
                onTap: _handleDeleteButtonTap,
                color: AppColors.error,
                size: secondarySize,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建操作按钮
  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback? onTap,
    Color? color,
    bool isPrimary = false,
    double? size,
  }) {
    final effectiveSize = size ?? (isPrimary ? 52.0 : 40.0);
    final iconSize = isPrimary ? effectiveSize * 0.4 : effectiveSize * 0.4;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppAnimations.fast,
        width: effectiveSize,
        height: effectiveSize,
        decoration: BoxDecoration(
          gradient: isPrimary ? AppColors.primaryGradient : null,
          color: isPrimary ? null : Colors.white.withValues(alpha: 0.2),
          shape: BoxShape.circle,
          boxShadow: isPrimary ? AppShadows.neonPrimary : null,
        ),
        child: Icon(
          icon,
          color: color ?? Colors.white,
          size: iconSize,
        ),
      ),
    );
  }

  /// 构建标题区域
  Widget _buildTitle({
    required double width,
    required bool isDark,
    required bool isPC,
    required bool isHovered,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 标题
        Text(
          widget.videoInfo.title,
          style: AppTypography.videoTitle(
            isDark: isDark,
            fontSize: width < 100 ? 13 : 14,
          ).copyWith(
            color: isHovered && isPC
                ? AppColors.primary
                : AppColors.textPrimary(isDark: isDark),
          ),
          maxLines: widget.from == 'douban' ? 2 : 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        // 来源（豆瓣和Bangumi模式不显示）
        if (widget.from != 'douban' &&
            widget.from != 'bangumi' &&
            widget.from != 'agg') ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: isHovered && isPC
                  ? AppColors.primary.withValues(alpha: 0.1)
                  : (isDark ? AppColors.darkElevated : AppColors.lightElevated),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              widget.videoInfo.sourceName,
              style: AppTypography.videoSubtitle(
                isDark: isDark,
                fontSize: 11,
              ).copyWith(
                color: isHovered && isPC
                    ? AppColors.primary
                    : AppColors.textSecondary(isDark: isDark),
              ),
            ),
          ),
        ],
        // 聚合模式显示源数量
        if (widget.from == 'agg' && widget.originalResults != null)
          Text(
            '${widget.originalResults!.length} 个来源',
            style: AppTypography.videoSubtitle(
              isDark: isDark,
              fontSize: 11,
            ).copyWith(
              color: AppColors.primary,
            ),
          ),
      ],
    );
  }

  /// PC 交互处理
  Widget _buildPCInteraction(Widget child, bool isHovered) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _isHovered.value = true,
      onExit: (_) => _isHovered.value = false,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: isHovered ? 1.02 : 1.0,
          duration: AppAnimations.fast,
          curve: AppAnimations.emphasize,
          child: child,
        ),
      ),
    );
  }

  /// 移动端交互处理
  Widget _buildMobileInteraction(Widget child) {
    final hasLongPressAction = [
      'playrecord',
      'douban',
      'bangumi',
      'favorite',
      'search',
      'agg',
    ].contains(widget.from);

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: hasLongPressAction && widget.onGlobalMenuAction != null
          ? () {
              HapticFeedback.mediumImpact();
              Future.delayed(const Duration(milliseconds: 50), () {
                if (mounted) {
                  _showGlobalMenu(context);
                }
              });
            }
          : null,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }

  /// 判断是否显示集数信息
  bool _shouldShowEpisodeInfo() {
    if (widget.from == 'douban' || widget.from == 'bangumi') {
      return false;
    }
    if (widget.videoInfo.totalEpisodes <= 1) {
      return false;
    }
    return true;
  }

  /// 获取集数显示文本
  String _getEpisodeText() {
    switch (widget.from) {
      case 'favorite':
        return widget.videoInfo.index > 0
            ? '${widget.videoInfo.index}/${widget.videoInfo.totalEpisodes}'
            : '${widget.videoInfo.totalEpisodes}';
      case 'playrecord':
        return '${widget.videoInfo.index}/${widget.videoInfo.totalEpisodes}';
      case 'search':
      case 'agg':
        return '${widget.videoInfo.totalEpisodes}';
      default:
        return '${widget.videoInfo.index}/${widget.videoInfo.totalEpisodes}';
    }
  }

  /// 判断是否显示进度条
  bool _shouldShowProgress() {
    return widget.from == 'playrecord';
  }

  /// 判断是否显示评分
  bool _shouldShowRating() {
    if (widget.videoInfo.rate == null || widget.videoInfo.rate!.isEmpty) {
      return false;
    }
    try {
      final rating = double.parse(widget.videoInfo.rate!);
      return rating > 0;
    } catch (e) {
      return false;
    }
  }

  /// 处理删除按钮点击
  void _handleDeleteButtonTap() {
    widget.onGlobalMenuAction?.call(VideoMenuAction.deleteRecord);
  }

  /// 处理收藏按钮点击
  void _handleFavoriteButtonTap() {
    widget.onGlobalMenuAction?.call(
      widget.isFavorited
          ? VideoMenuAction.unfavorite
          : VideoMenuAction.favorite,
    );
  }

  /// 显示视频菜单
  void _showGlobalMenu(BuildContext context) {
    VideoMenuBottomSheet.show(
      context,
      videoInfo: widget.videoInfo,
      isFavorited: widget.isFavorited,
      onActionSelected: widget.onGlobalMenuAction!,
      from: widget.from,
      originalResults: widget.originalResults,
      onSourceSelected: widget.onSourceSelected,
    );
  }
}
