import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:selene/components/animations/glass_card.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/screens/uvc_camera_screen.dart';
import 'package:selene/services/api_service.dart';
import 'package:selene/services/search_service.dart';
import 'package:selene/services/theme_service.dart';
import 'package:selene/services/usb_capture_service.dart';
import 'package:selene/services/user_data_service.dart';
import 'package:selene/utils/device_utils.dart';
import 'package:selene/widgets/usb_capture_notification.dart';
import 'package:selene/widgets/user_menu.dart';
import 'package:selene/widgets/windows_title_bar.dart';

/// 现代化主布局组件
///
/// 采用 2026 设计系统：
/// - 玻璃拟态导航栏
/// - 霓虹光效按钮
/// - 流畅的搜索建议动画
/// - 现代化的底部导航
class MainLayout extends StatefulWidget {
  final Widget content;
  final int currentBottomNavIndex;
  final void Function(int) onBottomNavChanged;
  final String selectedTopTab;
  final void Function(String) onTopTabChanged;
  final bool isSearchMode;
  final VoidCallback? onSearchTap;
  final VoidCallback? onHomeTap;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  final String? searchQuery;
  final void Function(String)? onSearchQueryChanged;
  final void Function(String)? onSearchSubmitted;
  final VoidCallback? onClearSearch;
  final bool showBottomNav;

  const MainLayout({
    super.key,
    required this.content,
    required this.currentBottomNavIndex,
    required this.onBottomNavChanged,
    required this.selectedTopTab,
    required this.onTopTabChanged,
    this.isSearchMode = false,
    this.onSearchTap,
    this.onHomeTap,
    this.searchController,
    this.searchFocusNode,
    this.searchQuery,
    this.onSearchQueryChanged,
    this.onSearchSubmitted,
    this.onClearSearch,
    this.showBottomNav = true,
  });

  @override
  State<MainLayout> createState() => _MainLayoutState();
}

class _MainLayoutState extends State<MainLayout> {
  bool _showUserMenu = false;
  int? _hoveredNavIndex;
  bool _isSearchHovered = false;
  bool _isThemeHovered = false;
  bool _isUserHovered = false;
  final ValueNotifier<bool> _isSearchSubmitHovered = ValueNotifier<bool>(false);
  final ValueNotifier<bool> _isClearHovered = ValueNotifier<bool>(false);

  // 搜索建议相关状态
  List<String> _searchSuggestions = [];
  Timer? _debounceTimer;
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _removeOverlay();
    _isSearchSubmitHovered.dispose();
    _isClearHovered.dispose();
    super.dispose();
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _fetchSearchSuggestions(String query) async {
    if (query.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _searchSuggestions = []);
          _removeOverlay();
        }
      });
      return;
    }

    final currentQuery = query;
    final isLocalMode = await UserDataService.getIsLocalMode();
    final isLocalSearch = await UserDataService.getLocalSearch();

    List<String> suggestionResults;
    if (isLocalMode || isLocalSearch) {
      suggestionResults = await SearchService.searchRecommand(query.trim());
    } else {
      suggestionResults = await ApiService.getSearchSuggestions(query.trim());
    }

    if (!mounted ||
        widget.searchQuery != currentQuery ||
        suggestionResults.isEmpty) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.searchQuery != currentQuery) return;

      if (suggestionResults.isNotEmpty) {
        setState(() => _searchSuggestions = suggestionResults.take(8).toList());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _searchSuggestions.isNotEmpty) {
            _showSuggestionsOverlay();
          }
        });
      } else {
        setState(() => _searchSuggestions = []);
        _removeOverlay();
      }
    });
  }

  void _onSearchQueryChanged(String query) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onSearchQueryChanged?.call(query);
    });

    _debounceTimer?.cancel();

    if (query.trim().isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _searchSuggestions = []);
          _removeOverlay();
        }
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted && query == widget.searchQuery) {
        _fetchSearchSuggestions(query);
      }
    });
  }

  void _showSuggestionsOverlay() {
    _removeOverlay();

    if (_searchSuggestions.isEmpty) return;

    final themeService = Provider.of<ThemeService>(context, listen: false);
    final isDark = themeService.isDarkMode;
    final isTablet = DeviceUtils.isTablet(context);

    final screenWidth = MediaQuery.of(context).size.width;
    final suggestionWidth =
        isTablet ? screenWidth * 0.5 : screenWidth - 32 - 16 - 32 - 12 - 32;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: suggestionWidth,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 50),
          child: GlassCard(
            isDark: isDark,
            borderRadius: 16,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _searchSuggestions.length,
                itemBuilder: (context, index) {
                  final suggestion = _searchSuggestions[index];
                  return _SuggestionItem(
                    suggestion: suggestion,
                    isDark: isDark,
                    onTap: () {
                      widget.searchController?.text = suggestion;
                      widget.onSearchSubmitted?.call(suggestion);
                      _removeOverlay();
                    },
                    delay: index * 0.05,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (context, themeService, child) {
        final isDark = themeService.isDarkMode;

        return Theme(
          data: isDark ? themeService.darkTheme : themeService.lightTheme,
          child: Scaffold(
            resizeToAvoidBottomInset: !widget.isSearchMode,
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.backgroundGradient(isDark: isDark),
              ),
              child: Stack(
                children: [
                  Column(
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            // Header（Windows 下延伸到顶部）
                            _buildHeader(context, themeService),
                            // 主内容（包含 USB 采集卡提示）
                            Expanded(
                              child: _buildContentWithUsbNotification(),
                            ),
                          ],
                        ),
                      ),
                      // 底部导航
                      if (widget.showBottomNav)
                        _buildBottomNavBar(themeService),
                    ],
                  ),
                  // Windows 标题栏悬浮在最上层
                  if (Platform.isWindows)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: WindowsTitleBar(
                        customBackgroundColor: widget.isSearchMode
                            ? AppColors.surface(isDark: isDark)
                            : null,
                      ),
                    ),
                  // 用户菜单
                  if (_showUserMenu)
                    UserMenu(
                      isDarkMode: isDark,
                      onClose: () => setState(() => _showUserMenu = false),
                    ),
                  // USB 采集卡浮动按钮（Android 平台，右下角，不挡底部导航）
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 打开 USB 摄像头预览页面
  void _openUsbCaptureScreen(BuildContext context) {
    debugPrint('MainLayout: 打开 USB 摄像头页面');

    // 使用 root Navigator 确保正确导航
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (context) => const UVCCameraScreen(),
        fullscreenDialog: true, // 全屏对话框模式
      ),
    );
  }

  /// 构建 USB 采集卡浮动按钮
  // ignore: unused_element
  Widget _buildUsbCaptureFab(BuildContext context) {
    return Consumer<UsbCaptureService>(
      builder: (context, service, _) {
        final isConnected = service.isCaptureCardConnected;

        // 使用 AnimatedScale 实现平滑的显示/隐藏动画
        return AnimatedScale(
          scale: isConnected ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: AnimatedOpacity(
            opacity: isConnected ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: isConnected
                ? FloatingActionButton(
                    heroTag: 'usbCaptureFab',
                    onPressed: () {
                      debugPrint('MainLayout: 浮动按钮被点击');
                      _openUsbCaptureScreen(context);
                    },
                    backgroundColor: AppColors.primary,
                    child: const Icon(LucideIcons.monitor,
                        color: Colors.white, size: 24),
                  )
                : const SizedBox.shrink(),
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, ThemeService themeService) {
    final isDark = themeService.isDarkMode;
    final topPadding = DeviceUtils.isMacOS()
        ? MediaQuery.of(context).padding.top + 32
        : Platform.isWindows
            ? 36.0
            : MediaQuery.of(context).padding.top + 8;

    // Windows 下使用透明背景，与悬浮标题栏融合
    if (Platform.isWindows) {
      return Container(
        padding: EdgeInsets.only(
          top: topPadding,
          left: 16,
          right: 16,
          bottom: 12,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface(isDark: isDark).withValues(alpha: 0.0),
        ),
        child: widget.isSearchMode
            ? _buildSearchHeader(themeService)
            : _buildNormalHeader(themeService),
      );
    }

    return GlassCard(
      isDark: isDark,
      borderRadius: 0,
      padding: EdgeInsets.only(
        top: topPadding,
        left: 16,
        right: 16,
        bottom: 12,
      ),
      child: widget.isSearchMode
          ? _buildSearchHeader(themeService)
          : _buildNormalHeader(themeService),
    );
  }

  Widget _buildNormalHeader(ThemeService themeService) {
    final isDark = themeService.isDarkMode;

    return SizedBox(
      height: 48,
      child: Stack(
        children: [
          // 左侧搜索按钮
          Align(
            alignment: Alignment.centerLeft,
            child: _buildIconButton(
              icon: LucideIcons.search,
              onTap: widget.onSearchTap,
              isHovered: _isSearchHovered,
              onHover: (value) => setState(() => _isSearchHovered = value),
              isDark: isDark,
            ),
          ),
          // 居中 Logo
          Center(
            child: GestureDetector(
              onTap: widget.onHomeTap,
              child: ShaderMask(
                shaderCallback: (bounds) =>
                    AppColors.primaryGradient.createShader(bounds),
                child: Text(
                  'Selene',
                  style: AppTypography.brand(fontSize: 28)
                      .copyWith(color: Colors.white),
                ),
              ),
            ),
          ),
          // 右侧按钮组
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 主题切换
                _buildIconButton(
                  icon: isDark ? LucideIcons.sun : LucideIcons.moon,
                  onTap: () => themeService.toggleTheme(context),
                  isHovered: _isThemeHovered,
                  onHover: (value) => setState(() => _isThemeHovered = value),
                  isDark: isDark,
                ),
                const SizedBox(width: 8),
                // 用户菜单
                _buildIconButton(
                  icon: LucideIcons.user,
                  onTap: () => setState(() => _showUserMenu = true),
                  isHovered: _isUserHovered,
                  onHover: (value) => setState(() => _isUserHovered = value),
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchHeader(ThemeService themeService) {
    final isDark = themeService.isDarkMode;
    final isTablet = DeviceUtils.isTablet(context);

    final searchField = CompositedTransformTarget(
      link: _layerLink,
      child: GlassCard(
        isDark: isDark,
        borderRadius: 16,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus) _removeOverlay();
          },
          child: TextField(
            controller: widget.searchController,
            focusNode: widget.searchFocusNode,
            decoration: InputDecoration(
              hintText: '搜索电影、剧集、动漫...',
              hintStyle: AppTypography.bodyMediumStyle(isDark: isDark).copyWith(
                color: AppColors.textTertiary(isDark: isDark),
              ),
              prefixIcon: Icon(
                LucideIcons.search,
                color: AppColors.textTertiary(isDark: isDark),
                size: 20,
              ),
              suffixIcon:
                  _buildSearchSuffix(isDark: isDark, isTablet: isTablet),
              border: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            style: AppTypography.bodyMediumStyle(isDark: isDark),
            onSubmitted: (value) {
              _removeOverlay();
              widget.onSearchSubmitted?.call(value);
            },
            onChanged: _onSearchQueryChanged,
          ),
        ),
      ),
    );

    if (isTablet) {
      return SizedBox(
        height: 48,
        child: Row(
          children: [
            _buildIconButton(
              icon: LucideIcons.arrowLeft,
              onTap: () => Navigator.pop(context),
              isHovered: false,
              onHover: (_) {},
              isDark: isDark,
            ),
            const SizedBox(width: 16),
            Expanded(child: searchField),
            const SizedBox(width: 16),
            _buildIconButton(
              icon: LucideIcons.x,
              onTap: widget.onClearSearch,
              isHovered: false,
              onHover: (_) {},
              isDark: isDark,
            ),
          ],
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(child: searchField),
          const SizedBox(width: 12),
          _buildIconButton(
            icon: isDark ? LucideIcons.sun : LucideIcons.moon,
            onTap: () => themeService.toggleTheme(context),
            isHovered: _isThemeHovered,
            onHover: (value) => setState(() => _isThemeHovered = value),
            isDark: isDark,
          ),
          const SizedBox(width: 8),
          _buildIconButton(
            icon: LucideIcons.user,
            onTap: () => setState(() => _showUserMenu = true),
            isHovered: _isUserHovered,
            onHover: (value) => setState(() => _isUserHovered = value),
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSuffix({required bool isDark, required bool isTablet}) {
    final hasQuery = widget.searchQuery?.isNotEmpty ?? false;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 清除按钮
        AnimatedOpacity(
          opacity: hasQuery ? 1.0 : 0.0,
          duration: AppAnimations.fast,
          child: MouseRegion(
            onEnter: (_) => _isClearHovered.value = true,
            onExit: (_) => _isClearHovered.value = false,
            child: GestureDetector(
              onTap: () {
                _removeOverlay();
                widget.onClearSearch?.call();
              },
              child: AnimatedBuilder(
                animation: _isClearHovered,
                builder: (context, child) {
                  return AnimatedContainer(
                    duration: AppAnimations.fast,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _isClearHovered.value
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: child,
                  );
                },
                child: Icon(
                  LucideIcons.x,
                  color: AppColors.textTertiary(isDark: isDark),
                  size: 18,
                ),
              ),
            ),
          ),
        ),
        // 搜索按钮
        MouseRegion(
          onEnter: (_) => _isSearchSubmitHovered.value = true,
          onExit: (_) => _isSearchSubmitHovered.value = false,
          child: GestureDetector(
            onTap: hasQuery
                ? () {
                    _removeOverlay();
                    widget.onSearchSubmitted?.call(widget.searchQuery!);
                  }
                : null,
            child: AnimatedBuilder(
              animation: _isSearchSubmitHovered,
              builder: (context, child) {
                return AnimatedContainer(
                  duration: AppAnimations.fast,
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: hasQuery && _isSearchSubmitHovered.value
                        ? AppColors.primaryGradient
                        : null,
                    color: hasQuery && !_isSearchSubmitHovered.value
                        ? AppColors.primary.withValues(alpha: 0.1)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: child,
                );
              },
              child: Icon(
                LucideIcons.arrowRight,
                color: hasQuery
                    ? (_isSearchSubmitHovered.value
                        ? Colors.white
                        : AppColors.primary)
                    : AppColors.textTertiary(isDark: isDark),
                size: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback? onTap,
    required bool isHovered,
    // ignore: avoid_positional_boolean_parameters
    required void Function(bool) onHover,
    required bool isDark,
  }) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppAnimations.fast,
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isHovered
                ? AppColors.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: isHovered
                ? AppColors.primary
                : AppColors.textPrimary(isDark: isDark),
            size: 22,
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNavBar(ThemeService themeService) {
    final isDark = themeService.isDarkMode;
    final isTablet = DeviceUtils.isTablet(context);

    final navItems = [
      {'icon': LucideIcons.house, 'label': '首页'},
      {'icon': LucideIcons.film, 'label': '电影'},
      {'icon': LucideIcons.tv, 'label': '剧集'},
      {'icon': LucideIcons.cat, 'label': '动漫'},
      {'icon': LucideIcons.clover, 'label': '综艺'},
      {'icon': LucideIcons.radio, 'label': '直播'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0F172A).withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: isTablet
            ? BorderRadius.circular(24)
            : const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
        border: Border(
          top: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      margin: isTablet ? const EdgeInsets.all(16) : EdgeInsets.zero,
      padding: EdgeInsets.only(
        left: isTablet ? 24 : 8,
        right: isTablet ? 24 : 8,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Row(
        mainAxisAlignment:
            isTablet ? MainAxisAlignment.center : MainAxisAlignment.spaceEvenly,
        children: navItems.asMap().entries.expand((entry) {
          final index = entry.key;
          final item = entry.value;
          final isSelected =
              !widget.isSearchMode && widget.currentBottomNavIndex == index;
          final isHovered = DeviceUtils.isPC() && _hoveredNavIndex == index;

          return [
            MouseRegion(
              cursor: DeviceUtils.isPC()
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
              onEnter: DeviceUtils.isPC()
                  ? (_) => setState(() => _hoveredNavIndex = index)
                  : null,
              onExit: DeviceUtils.isPC()
                  ? (_) => setState(() => _hoveredNavIndex = null)
                  : null,
              child: GestureDetector(
                onTap: () => widget.onBottomNavChanged(index),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: AppAnimations.fast,
                  padding: EdgeInsets.symmetric(
                    horizontal: isTablet ? 16 : 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.primary.withValues(alpha: 0.12)
                        : (isHovered
                            ? AppColors.primary.withValues(alpha: 0.06)
                            : Colors.transparent),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item['icon']! as IconData,
                        color: isSelected
                            ? AppColors.primary
                            : (isHovered
                                ? AppColors.primary
                                : AppColors.textSecondary(isDark: isDark)),
                        size: 22,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        item['label']! as String,
                        style: AppTypography.labelMediumStyle(isDark: isDark)
                            .copyWith(
                          color: isSelected
                              ? AppColors.primary
                              : (isHovered
                                  ? AppColors.primary
                                  : AppColors.textSecondary(isDark: isDark)),
                          fontWeight: isSelected
                              ? AppTypography.semiBold
                              : AppTypography.medium,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ];
        }).toList(),
      ),
    );
  }

  /// 构建带 USB 采集卡提示的内容区域
  Widget _buildContentWithUsbNotification() {
    // 只在 Android 平台显示 USB 采集卡提示
    if (!Platform.isAndroid) {
      return widget.content;
    }

    return Consumer<UsbCaptureService>(
      builder: (context, service, _) {
        return Column(
          children: [
            // 当检测到采集卡时显示提示
            if (service.isCaptureCardConnected)
              UsbCaptureNotification(
                onTap: () {
                  debugPrint('MainLayout: 提示条被点击');
                  _openUsbCaptureScreen(context);
                },
              ),
            // 主内容
            Expanded(child: widget.content),
          ],
        );
      },
    );
  }
}

/// 搜索建议项
class _SuggestionItem extends StatelessWidget {
  final String suggestion;
  final bool isDark;
  final VoidCallback onTap;
  final double delay;

  const _SuggestionItem({
    required this.suggestion,
    required this.isDark,
    required this.onTap,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return AppAnimations.entrance(
      delay: delay,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(
                  LucideIcons.search,
                  size: 16,
                  color: AppColors.textTertiary(isDark: isDark),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    suggestion,
                    style: AppTypography.bodyMediumStyle(isDark: isDark),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  LucideIcons.arrowUpLeft,
                  size: 14,
                  color: AppColors.textTertiary(isDark: isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
