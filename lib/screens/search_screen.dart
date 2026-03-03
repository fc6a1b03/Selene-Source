import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/models/search_result.dart';
import 'package:selene/models/video_info.dart';
import 'package:selene/screens/player_screen.dart';
import 'package:selene/services/page_cache_service.dart';
import 'package:selene/services/sse_search_service.dart';
import 'package:selene/services/theme_service.dart';
import 'package:selene/utils/device_utils.dart';
import 'package:selene/widgets/custom_switch.dart';
import 'package:selene/widgets/favorites_grid.dart';
import 'package:selene/widgets/filter_options_selector.dart';
import 'package:selene/widgets/filter_pill_hover.dart';
import 'package:selene/widgets/main_layout.dart';
import 'package:selene/widgets/search_result_agg_grid.dart';
import 'package:selene/widgets/search_results_grid.dart';
import 'package:selene/widgets/video_menu_bottom_sheet.dart';

enum SortOrder { none, asc, desc }

/// 现代化搜索页面
///
/// 采用 Design System 2026 设计规范：
/// - 玻璃拟态效果
/// - 霓虹光效
/// - 流畅的微交互动画
/// - 渐变背景
class SearchScreen extends StatefulWidget {
  const SearchScreen({
    super.key,
  });

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  String _searchQuery = '';
  List<String> _searchHistory = [];
  final List<SearchResult> _searchResults = [];
  bool _hasSearched = false;
  bool _hasReceivedStart = false;
  String? _searchError;
  SearchProgress? _searchProgress;
  bool _useAggregatedView = true;

  // 筛选和排序状态
  String _selectedSource = 'all';
  String _selectedYear = 'all';
  String _selectedTitle = 'all';
  SortOrder _yearSortOrder = SortOrder.none;

  // 动画状态
  late AnimationController _entranceController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // hover 状态
  String? _hoveredHistoryItem;
  String? _hoveredDeleteButton;
  String? _hoveredFilterPill;
  bool _isYearSortHovered = false;

  late SSESearchService _searchService;
  StreamSubscription<List<SearchResult>>? _incrementalResultsSubscription;
  StreamSubscription<SearchProgress>? _progressSubscription;
  StreamSubscription<String>? _errorSubscription;

  // 缓存过滤结果
  List<SearchResult>? _cachedFilteredResults;
  String? _lastFilterCacheKey;

  /// 生成缓存键
  String _generateFilterCacheKey() {
    return '${_searchResults.length}_${_selectedSource}_${_selectedYear}_${_selectedTitle}_${_yearSortOrder.index}';
  }

  List<SearchResult> get _filteredSearchResults {
    final currentKey = _generateFilterCacheKey();

    // 如果缓存有效，直接返回缓存结果
    if (_cachedFilteredResults != null && _lastFilterCacheKey == currentKey) {
      return _cachedFilteredResults!;
    }

    // 计算过滤结果
    List<SearchResult> results = List.from(_searchResults);

    // Source filter
    if (_selectedSource != 'all') {
      results = results.where((r) => r.sourceName == _selectedSource).toList();
    }

    // Year filter
    if (_selectedYear != 'all') {
      results = results.where((r) => r.year == _selectedYear).toList();
    }

    // Title filter
    if (_selectedTitle != 'all') {
      results = results.where((r) => r.title == _selectedTitle).toList();
    }

    // Year sort - 使用更高效的排序
    if (_yearSortOrder != SortOrder.none && results.length > 1) {
      // 预解析年份，避免重复解析
      final parsedYears = <SearchResult, int?>{};
      for (final r in results) {
        parsedYears[r] = int.tryParse(r.year);
      }

      results.sort((a, b) {
        final yearA = parsedYears[a];
        final yearB = parsedYears[b];

        if (yearA != null && yearB == null) return -1;
        if (yearA == null && yearB != null) return 1;
        if (yearA == null && yearB == null) return 0;

        if (_yearSortOrder == SortOrder.desc) {
          return yearB!.compareTo(yearA!);
        } else {
          return yearA!.compareTo(yearB!);
        }
      });
    }

    // 更新缓存
    _cachedFilteredResults = results;
    _lastFilterCacheKey = currentKey;

    return results;
  }

  /// 清除过滤缓存
  void _clearFilterCache() {
    _cachedFilteredResults = null;
    _lastFilterCacheKey = null;
  }

  @override
  void initState() {
    super.initState();

    // 初始化入场动画
    _entranceController = AnimationController(
      vsync: this,
      duration: AppAnimations.showcase,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _entranceController,
      curve: AppAnimations.enter,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: AppAnimations.enter,
    ));

    _searchService = SSESearchService();
    _setupSearchListeners();
    _loadSearchHistory();

    // 进入搜索页面时自动聚焦搜索框并启动入场动画
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        _searchFocusNode.requestFocus();
        _entranceController.forward();
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _incrementalResultsSubscription?.cancel();
    _progressSubscription?.cancel();
    _errorSubscription?.cancel();
    _batchUpdateTimer?.cancel();
    _batchUpdateTimer?.cancel();
    _searchService.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  // 批量更新相关
  final List<SearchResult> _pendingResults = [];
  Timer? _batchUpdateTimer;
  static const int _batchUpdateThreshold = 50; // 每50条更新一次
  static const Duration _batchUpdateInterval =
      Duration(milliseconds: 300); // 或每300ms更新一次

  /// 批量更新结果到UI
  void _flushPendingResults() {
    if (!mounted || _pendingResults.isEmpty) return;

    setState(() {
      _searchResults.addAll(_pendingResults);
      _pendingResults.clear();
      // 清除过滤缓存，因为有新数据
      _clearFilterCache();
    });
  }

  /// 设置搜索监听器
  void _setupSearchListeners() {
    _incrementalResultsSubscription?.cancel();
    _progressSubscription?.cancel();
    _errorSubscription?.cancel();
    _batchUpdateTimer?.cancel();
    _pendingResults.clear();

    _incrementalResultsSubscription =
        _searchService.incrementalResultsStream.listen((incrementalResults) {
      if (mounted && incrementalResults.isNotEmpty) {
        _pendingResults.addAll(incrementalResults);

        // 批量更新策略：积累到一定数量或定时更新
        if (_pendingResults.length >= _batchUpdateThreshold) {
          _flushPendingResults();
        } else {
          _batchUpdateTimer?.cancel();
          _batchUpdateTimer = Timer(_batchUpdateInterval, _flushPendingResults);
        }
      }
    });

    _progressSubscription = _searchService.progressStream.listen((progress) {
      if (mounted) {
        setState(() {
          _searchProgress = progress;
          _hasReceivedStart = true;
        });
      }
    });

    _errorSubscription = _searchService.errorStream.listen((error) {
      if (mounted) {
        final errorString = error.toLowerCase();
        if (errorString.contains('connection closed') ||
            errorString.contains('clientexception') ||
            errorString.contains('connection terminated')) {
          return;
        }

        setState(() {
          _searchError = error;
        });
      }
    });
  }

  Future<void> _loadSearchHistory() async {
    try {
      final result = await PageCacheService().getSearchHistory(context);
      if (mounted) {
        setState(() {
          _searchHistory = result.success ? (result.data ?? []) : [];
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _searchHistory = [];
        });
      }
    }
  }

  Future<void> _refreshSearchHistory() async {
    try {
      await PageCacheService().refreshSearchHistory(context);
      if (mounted) {
        final result = await PageCacheService().getSearchHistory(context);
        setState(() {
          _searchHistory = result.success ? (result.data ?? []) : [];
        });
      }
    } catch (e) {
      // 错误处理
    }
  }

  Future<void> _refreshFavorites() async {
    try {
      await PageCacheService().refreshFavorites(context);
    } catch (e) {
      // 错误处理
    }
  }

  void addSearchHistory(String query) {
    if (query.trim().isEmpty) return;

    final trimmedQuery = query.trim();
    PageCacheService().addSearchHistory(trimmedQuery, context);

    if (mounted) {
      setState(() {
        final existingIndex =
            _searchHistory.indexWhere((item) => item == trimmedQuery);

        if (existingIndex == -1) {
          _searchHistory.insert(0, trimmedQuery);
        } else {
          final existingItem = _searchHistory[existingIndex];
          _searchHistory.removeAt(existingIndex);
          _searchHistory.insert(0, existingItem);
        }
      });
    }
  }

  void _showClearConfirmation() {
    final isDark = context.read<ThemeService>().isDarkMode;

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              gradient: isDark
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.darkSurface,
                        AppColors.darkSurface.withValues(alpha: 0.95),
                      ],
                    )
                  : LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.lightSurface,
                        AppColors.lightElevated,
                      ],
                    ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDark
                    ? AppColors.darkGlassBorder
                    : AppColors.lightGlassBorder,
              ),
              boxShadow: isDark ? AppShadows.darkGlass : AppShadows.lightGlass,
            ),
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 发光图标
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.error.withValues(alpha: 0.3),
                          AppColors.error.withValues(alpha: 0.1),
                        ],
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.error.withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: -5,
                        ),
                      ],
                    ),
                    child: Icon(
                      LucideIcons.trash2,
                      color: AppColors.error,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '清空搜索历史',
                    style: AppTypography.headlineSmallStyle(isDark: isDark),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '确定要清空所有搜索历史吗？此操作无法撤销。',
                    style:
                        AppTypography.bodyMediumStyle(isDark: isDark).copyWith(
                      color: AppColors.textSecondary(isDark: isDark),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      Expanded(
                        child: _GlassButton(
                          onTap: () => Navigator.of(context).pop(),
                          isDark: isDark,
                          child: Text(
                            '取消',
                            style: AppTypography.primary(
                              fontWeight: AppTypography.medium,
                              color: AppColors.textSecondary(isDark: isDark),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _GlowButton(
                          onTap: () {
                            Navigator.of(context).pop();
                            _clearSearchHistory();
                          },
                          backgroundColor: AppColors.error,
                          child: Text(
                            '清空',
                            style: AppTypography.primary(
                              fontWeight: AppTypography.semiBold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _clearSearchHistory() async {
    try {
      final result = await PageCacheService().clearSearchHistory(context);

      if (result.success) {
        if (mounted) {
          setState(() {
            _searchHistory.clear();
          });
        }
      } else {
        await _refreshSearchHistory();
      }
    } catch (e) {
      await _refreshSearchHistory();
    }
  }

  Future<void> _deleteSearchHistory(String historyItem) async {
    try {
      final result =
          await PageCacheService().deleteSearchHistory(historyItem, context);

      if (result.success) {
        if (mounted) {
          setState(() {
            _searchHistory.remove(historyItem);
          });
        }
      } else {
        await _refreshSearchHistory();
      }
    } catch (e) {
      await _refreshSearchHistory();
    }
  }

  void _performSearch(String query) async {
    if (query.trim().isEmpty) return;

    // 清除批量更新相关
    _batchUpdateTimer?.cancel();
    _pendingResults.clear();

    setState(() {
      _searchQuery = query.trim();
      _hasSearched = true;
      _hasReceivedStart = false;
      _searchError = null;
      _searchResults.clear();
      _clearFilterCache(); // 清除过滤缓存
      _searchProgress = null;
      _useAggregatedView = true;
      _selectedSource = 'all';
      _selectedYear = 'all';
      _selectedTitle = 'all';
      _yearSortOrder = SortOrder.none;
    });

    addSearchHistory(_searchQuery);
    _searchFocusNode.unfocus();

    try {
      await _searchService.startSearch(_searchQuery);
      _setupSearchListeners();
    } catch (e) {
      if (mounted) {
        final errorString = e.toString().toLowerCase();
        if (errorString.contains('connection closed') ||
            errorString.contains('clientexception') ||
            errorString.contains('connection terminated')) {
          return;
        }

        setState(() {
          _searchError = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Selector 只监听 isDarkMode 变化，避免主题其他属性变化时重建
    return Selector<ThemeService, bool>(
      selector: (_, themeService) => themeService.isDarkMode,
      builder: (context, isDark, child) {
        // 获取底部安全区域高度（适配虚拟导航栏）
        final bottomPadding = MediaQuery.of(context).padding.bottom;

        return MainLayout(
          content: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.backgroundGradient(isDark: isDark),
            ),
            child: SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!_hasSearched) ...[
                        if (_searchError != null)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: _buildSearchError(isDark),
                          ),
                        Expanded(
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: _buildSearchHistory(isDark),
                          ),
                        ),
                      ],
                      if (_hasSearched) ...[
                        Expanded(
                          child: _buildSearchResults(isDark,
                              bottomPadding: bottomPadding),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          currentBottomNavIndex: -1,
          onBottomNavChanged: (index) {
            Navigator.pop(context);
          },
          selectedTopTab: '',
          onTopTabChanged: (tab) {},
          showBottomNav: false,
          isSearchMode: true,
          searchController: _searchController,
          searchFocusNode: _searchFocusNode,
          searchQuery: _searchQuery,
          onSearchQueryChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
          onSearchSubmitted: (value) {
            _performSearch(value);
          },
          onClearSearch: () {
            _batchUpdateTimer?.cancel();
            _pendingResults.clear();
            setState(() {
              _searchQuery = '';
              _searchController.clear();
              _hasSearched = false;
              _hasReceivedStart = false;
              _searchResults.clear();
              _clearFilterCache();
              _searchError = null;
              _searchProgress = null;
              _searchService.stopSearch();
            });
          },
          onHomeTap: () {
            Navigator.pop(context);
          },
        );
      },
    );
  }

  Widget _buildSearchHistory(bool isDark) {
    if (_searchHistory.isEmpty) {
      return _buildEmptyHistoryState(isDark);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 24,
                    decoration: BoxDecoration(
                      gradient: AppColors.primaryGradient,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '搜索历史',
                    style: AppTypography.headlineSmallStyle(isDark: isDark),
                  ),
                ],
              ),
              _GlassButton(
                onTap: _showClearConfirmation,
                isDark: isDark,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.trash2,
                      size: 14,
                      color: AppColors.textSecondary(isDark: isDark),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '清空',
                      style: AppTypography.labelMediumStyle(isDark: isDark),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // 历史标签
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: _searchHistory.asMap().entries.map((entry) {
              final index = entry.key;
              final history = entry.value;
              final isHovered = _hoveredHistoryItem == history;

              return AppAnimations.entrance(
                delay: index * 0.05,
                child: MouseRegion(
                  onEnter: (_) => setState(() => _hoveredHistoryItem = history),
                  onExit: (_) => setState(() => _hoveredHistoryItem = null),
                  child: GestureDetector(
                    onTap: () {
                      _searchController.text = history;
                      setState(() => _searchQuery = history);
                      _performSearch(history);
                    },
                    child: AnimatedContainer(
                      duration: AppAnimations.fast,
                      curve: AppAnimations.standard,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: isHovered
                            ? AppColors.primaryGradient
                            : LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  isDark
                                      ? AppColors.darkElevated
                                      : AppColors.lightSurface,
                                  isDark
                                      ? AppColors.darkElevated
                                          .withValues(alpha: 0.8)
                                      : AppColors.lightSurface
                                          .withValues(alpha: 0.8),
                                ],
                              ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isHovered
                              ? AppColors.primary.withValues(alpha: 0.5)
                              : isDark
                                  ? AppColors.darkBorder
                                  : AppColors.lightBorder,
                        ),
                        boxShadow: isHovered
                            ? AppShadows.primary(intensity: 0.4)
                            : isDark
                                ? AppShadows.darkGlass
                                : AppShadows.lightGlass,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.history,
                            size: 14,
                            color: isHovered
                                ? Colors.white
                                : AppColors.textSecondary(isDark: isDark),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            history,
                            style: AppTypography.primary(
                              fontSize: 14,
                              fontWeight: isHovered
                                  ? AppTypography.medium
                                  : AppTypography.regular,
                              color: isHovered
                                  ? Colors.white
                                  : AppColors.textPrimary(isDark: isDark),
                            ),
                          ),
                          // 删除按钮 - 支持 PC 和移动端
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () => _deleteSearchHistory(history),
                            child: DeviceUtils.isPC()
                                ? MouseRegion(
                                    onEnter: (_) => setState(
                                        () => _hoveredDeleteButton = history),
                                    onExit: (_) => setState(
                                        () => _hoveredDeleteButton = null),
                                    child: AnimatedContainer(
                                      duration: AppAnimations.micro,
                                      width: 18,
                                      height: 18,
                                      decoration: BoxDecoration(
                                        color: _hoveredDeleteButton == history
                                            ? AppColors.error
                                            : isDark
                                                ? AppColors.darkTextTertiary
                                                : AppColors.lightTextTertiary,
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.close,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                    ),
                                  )
                                : Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? AppColors.darkTextTertiary
                                          : AppColors.lightTextTertiary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.close,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHistoryState(bool isDark) {
    return Center(
      child: AppAnimations.entrance(
        child: Container(
          margin: const EdgeInsets.only(top: 120),
          padding: const EdgeInsets.all(48),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                isDark
                    ? AppColors.darkSurface.withValues(alpha: 0.5)
                    : AppColors.lightSurface.withValues(alpha: 0.5),
                isDark
                    ? AppColors.darkElevated.withValues(alpha: 0.3)
                    : AppColors.lightElevated.withValues(alpha: 0.3),
              ],
            ),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: isDark
                  ? AppColors.darkGlassBorder
                  : AppColors.lightGlassBorder,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 发光搜索图标
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.3),
                      AppColors.secondary.withValues(alpha: 0.1),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.2),
                      blurRadius: 30,
                      spreadRadius: -5,
                    ),
                  ],
                ),
                child: Icon(
                  LucideIcons.search,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '开始探索',
                style: AppTypography.headlineMediumStyle(isDark: isDark),
              ),
              const SizedBox(height: 12),
              Text(
                '搜索你喜欢的影视内容',
                style: AppTypography.bodyLargeStyle(isDark: isDark).copyWith(
                  color: AppColors.textSecondary(isDark: isDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchError(bool isDark) {
    final error = _searchError;
    if (error == null) return const SizedBox.shrink();

    return AppAnimations.entrance(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.error.withValues(alpha: 0.15),
              AppColors.error.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.error.withValues(alpha: 0.3),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.error.withValues(alpha: 0.1),
              blurRadius: 20,
              spreadRadius: -5,
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                color: AppColors.error,
                size: 20,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                error,
                style: AppTypography.bodyMediumStyle(isDark: isDark).copyWith(
                  color: AppColors.error,
                ),
              ),
            ),
            _GlassButton(
              onTap: () => setState(() => _searchError = null),
              isDark: isDark,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                '重试',
                style: AppTypography.labelMediumStyle(isDark: isDark).copyWith(
                  color: AppColors.error,
                  fontWeight: AppTypography.semiBold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults(bool isDark, {double bottomPadding = 0}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        // 标题栏
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      '搜索结果',
                      style: AppTypography.headlineSmallStyle(isDark: isDark),
                    ),
                    if (_hasReceivedStart) ...[
                      const SizedBox(width: 12),
                      _buildProgressIndicator(isDark),
                    ],
                  ],
                ),
              ),
              if (_hasSearched && _searchResults.isNotEmpty) ...[
                Text(
                  '聚合',
                  style: AppTypography.labelMediumStyle(isDark: isDark),
                ),
                const SizedBox(width: 8),
                CustomSwitch(
                  value: _useAggregatedView,
                  onChanged: (value) {
                    setState(() => _useAggregatedView = value);
                  },
                  activeColor: AppColors.primary,
                  inactiveColor:
                      isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  width: 36,
                  height: 20,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        // 搜索状态
        if (_hasSearched && _searchResults.isEmpty && !_hasReceivedStart)
          Expanded(child: _buildSearchingState(isDark))
        else if (_hasSearched && _searchResults.isEmpty && _hasReceivedStart)
          Expanded(child: _buildNoResultsState(isDark))
        else ...[
          // 筛选器 - 固定在顶部，带玻璃拟态背景
          if (_hasSearched && _searchResults.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 20),
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    isDark
                        ? AppColors.darkSurface.withValues(alpha: 0.8)
                        : AppColors.lightSurface.withValues(alpha: 0.8),
                    isDark
                        ? AppColors.darkElevated.withValues(alpha: 0.6)
                        : AppColors.lightElevated.withValues(alpha: 0.6),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark
                      ? AppColors.darkGlassBorder
                      : AppColors.lightGlassBorder,
                ),
              ),
              child: _buildFilterSection(isDark),
            ),
            const SizedBox(height: 12),
          ],
          // 结果网格 - 添加底部padding避免被导航栏遮挡
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: bottomPadding > 0 ? bottomPadding + 8 : 16,
              ),
              child: _useAggregatedView
                  ? SearchResultAggGrid(
                      key: const ValueKey('agg_grid'),
                      results: _filteredSearchResults,
                      themeService: context.read<ThemeService>(),
                      onVideoTap: _onVideoTap,
                      onGlobalMenuAction: _onGlobalMenuAction,
                      onSourceSelected: (SearchResult result) {
                        Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (context) => PlayerScreen(
                              source: result.source,
                              id: result.id,
                              year: result.year,
                              title: result.title,
                              stitle: _searchQuery,
                              stype:
                                  result.episodes.length > 1 ? 'tv' : 'movie',
                            ),
                          ),
                        );
                      },
                      hasReceivedStart: _hasReceivedStart,
                    )
                  : SearchResultsGrid(
                      key: const ValueKey('list_grid'),
                      results: _filteredSearchResults,
                      themeService: context.read<ThemeService>(),
                      onVideoTap: _onVideoTap,
                      onGlobalMenuAction: _onGlobalMenuAction,
                      hasReceivedStart: _hasReceivedStart,
                    ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildProgressIndicator(bool isDark) {
    final progress = _searchProgress;
    if (progress == null) {
      return const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      );
    }

    final percentage = progress.totalSources > 0
        ? progress.completedSources / progress.totalSources
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.primary.withValues(alpha: 0.15),
            AppColors.secondary.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              value: percentage > 0 ? percentage : null,
              strokeWidth: 2,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.primary),
              backgroundColor: AppColors.primary.withValues(alpha: 0.1),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${progress.completedSources}/${progress.totalSources}',
            style: AppTypography.mono(
              fontSize: 12,
              fontWeight: AppTypography.medium,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchingState(bool isDark) {
    return Center(
      child: AppAnimations.entrance(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 脉冲动画搜索图标
            PulseAnimation(
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.primary.withValues(alpha: 0.3),
                      AppColors.secondary.withValues(alpha: 0.2),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: AppShadows.neonPrimary,
                ),
                child: const Icon(
                  LucideIcons.search,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '搜索中...',
              style: AppTypography.headlineSmallStyle(isDark: isDark),
            ),
            const SizedBox(height: 12),
            Text(
              '正在聚合多源搜索结果',
              style: AppTypography.bodyLargeStyle(isDark: isDark).copyWith(
                color: AppColors.textSecondary(isDark: isDark),
              ),
            ),
            const SizedBox(height: 24),
            // 进度条
            Container(
              width: 200,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                borderRadius: BorderRadius.circular(2),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return ShimmerAnimation(
                    child: Container(
                      width: constraints.maxWidth * 0.5,
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: AppColors.primaryGradient,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState(bool isDark) {
    return Center(
      child: AppAnimations.entrance(
        child: Container(
          padding: const EdgeInsets.all(48),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                isDark
                    ? AppColors.darkSurface.withValues(alpha: 0.5)
                    : AppColors.lightSurface.withValues(alpha: 0.5),
                isDark
                    ? AppColors.darkElevated.withValues(alpha: 0.3)
                    : AppColors.lightElevated.withValues(alpha: 0.3),
              ],
            ),
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: isDark
                  ? AppColors.darkGlassBorder
                  : AppColors.lightGlassBorder,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.textTertiary(isDark: isDark)
                          .withValues(alpha: 0.2),
                      AppColors.textTertiary(isDark: isDark)
                          .withValues(alpha: 0.05),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  LucideIcons.folderSearch,
                  size: 40,
                  color: AppColors.textTertiary(isDark: isDark),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                '未找到结果',
                style: AppTypography.headlineSmallStyle(isDark: isDark),
              ),
              const SizedBox(height: 12),
              Text(
                '请尝试更换关键词搜索',
                style: AppTypography.bodyLargeStyle(isDark: isDark).copyWith(
                  color: AppColors.textSecondary(isDark: isDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterSection(bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          _buildFilterPill('来源', _sourceOptions, _selectedSource, (newValue) {
            setState(() => _selectedSource = newValue);
          }),
          const SizedBox(width: 8),
          _buildFilterPill('标题', _titleOptions, _selectedTitle, (newValue) {
            setState(() => _selectedTitle = newValue);
          }),
          const SizedBox(width: 8),
          _buildFilterPill('年份', _yearOptions, _selectedYear, (newValue) {
            setState(() => _selectedYear = newValue);
          }),
          const SizedBox(width: 8),
          _buildYearSortButton(isDark),
        ],
      ),
    );
  }

  Widget _buildFilterPill(
    String title,
    List<SelectorOption> options,
    String selectedValue,
    ValueChanged<String> onSelected,
  ) {
    final isDark = context.read<ThemeService>().isDarkMode;
    final bool isDefault = selectedValue == 'all';
    final bool isHovered = _hoveredFilterPill == title;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredFilterPill = title),
      onExit: (_) => setState(() => _hoveredFilterPill = null),
      child: GestureDetector(
        onTap: () => _showFilterOptions(
          context,
          title,
          options,
          selectedValue,
          onSelected,
        ),
        child: AnimatedContainer(
          duration: AppAnimations.fast,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: !isDefault
                ? AppColors.primaryGradient
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      isDark ? AppColors.darkElevated : AppColors.lightSurface,
                      isDark
                          ? AppColors.darkElevated.withValues(alpha: 0.8)
                          : AppColors.lightSurface.withValues(alpha: 0.8),
                    ],
                  ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: !isDefault
                  ? AppColors.primary.withValues(alpha: 0.5)
                  : isHovered
                      ? AppColors.primary
                      : isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
            ),
            boxShadow: !isDefault
                ? AppShadows.primary()
                : isHovered
                    ? AppShadows.small
                    : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: AppTypography.primary(
                  fontSize: 13,
                  fontWeight: !isDefault || isHovered
                      ? AppTypography.medium
                      : AppTypography.regular,
                  color: !isDefault
                      ? Colors.white
                      : isHovered
                          ? AppColors.primary
                          : AppColors.textSecondary(isDark: isDark),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: !isDefault
                    ? Colors.white70
                    : isHovered
                        ? AppColors.primary
                        : AppColors.textSecondary(isDark: isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildYearSortButton(bool isDark) {
    IconData icon;
    switch (_yearSortOrder) {
      case SortOrder.desc:
        icon = LucideIcons.arrowDown01;
        break;
      case SortOrder.asc:
        icon = LucideIcons.arrowUp01;
        break;
      case SortOrder.none:
        icon = LucideIcons.arrowUpDown;
        break;
    }

    final bool isDefault = _yearSortOrder == SortOrder.none;

    return MouseRegion(
      onEnter: (_) => setState(() => _isYearSortHovered = true),
      onExit: (_) => setState(() => _isYearSortHovered = false),
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (_yearSortOrder == SortOrder.none) {
              _yearSortOrder = SortOrder.desc;
            } else if (_yearSortOrder == SortOrder.desc) {
              _yearSortOrder = SortOrder.asc;
            } else {
              _yearSortOrder = SortOrder.none;
            }
          });
        },
        child: AnimatedContainer(
          duration: AppAnimations.fast,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            gradient: !isDefault
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppColors.secondary,
                      AppColors.secondaryLight,
                    ],
                  )
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      isDark ? AppColors.darkElevated : AppColors.lightSurface,
                      isDark
                          ? AppColors.darkElevated.withValues(alpha: 0.8)
                          : AppColors.lightSurface.withValues(alpha: 0.8),
                    ],
                  ),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: !isDefault
                  ? AppColors.secondary.withValues(alpha: 0.5)
                  : _isYearSortHovered
                      ? AppColors.secondary
                      : isDark
                          ? AppColors.darkBorder
                          : AppColors.lightBorder,
            ),
            boxShadow: !isDefault
                ? AppShadows.secondary()
                : _isYearSortHovered
                    ? AppShadows.small
                    : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '年份',
                style: AppTypography.primary(
                  fontSize: 13,
                  fontWeight: !isDefault || _isYearSortHovered
                      ? AppTypography.medium
                      : AppTypography.regular,
                  color: !isDefault
                      ? Colors.white
                      : _isYearSortHovered
                          ? AppColors.secondary
                          : AppColors.textSecondary(isDark: isDark),
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                icon,
                size: 16,
                color: !isDefault
                    ? Colors.white70
                    : _isYearSortHovered
                        ? AppColors.secondary
                        : AppColors.textSecondary(isDark: isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showFilterOptions(
    BuildContext context,
    String title,
    List<SelectorOption> options,
    String selectedValue,
    ValueChanged<String> onSelected,
  ) {
    final isDark = context.read<ThemeService>().isDarkMode;

    if (DeviceUtils.isPC()) {
      showFilterOptionsSelector(
        context: context,
        title: title,
        options: options,
        selectedValue: selectedValue,
        onSelected: onSelected,
        useCompactLayout: title == '标题',
      );
    } else {
      // 使用专门的移动端筛选弹窗组件
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) {
          return _FilterOptionsBottomSheet(
            title: title,
            options: options,
            selectedValue: selectedValue,
            onSelected: onSelected,
            isDark: isDark,
          );
        },
      );
    }
  }

  void _onVideoTap(VideoInfo videoInfo) {
    _onGlobalMenuAction(videoInfo, VideoMenuAction.play);
  }

  void _onGlobalMenuAction(VideoInfo videoInfo, VideoMenuAction action) {
    final stitle = _searchQuery;
    switch (action) {
      case VideoMenuAction.play:
        if (_useAggregatedView) {
          final parts = videoInfo.id.split('_');
          final type = parts.length > 2 ? parts.last : null;
          final year = parts.length > 1 ? parts[1] : null;

          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => PlayerScreen(
                title: videoInfo.title,
                stitle: stitle,
                stype: type,
                year: year,
              ),
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (context) => PlayerScreen(
                source: videoInfo.source,
                id: videoInfo.id,
                year: videoInfo.year,
                title: videoInfo.title,
                stype: videoInfo.totalEpisodes > 1 ? 'tv' : 'movie',
                stitle: stitle,
              ),
            ),
          );
        }
        break;
      case VideoMenuAction.favorite:
        _handleFavorite(videoInfo);
        break;
      case VideoMenuAction.unfavorite:
        _handleUnfavorite(videoInfo);
        break;
      case VideoMenuAction.deleteRecord:
        break;
      case VideoMenuAction.doubanDetail:
        _showSnackBar('正在打开豆瓣详情: ${videoInfo.title}', AppColors.secondary);
        break;
      case VideoMenuAction.bangumiDetail:
        _showSnackBar(
            '正在打开 Bangumi 详情: ${videoInfo.title}', AppColors.secondary);
        break;
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTypography.primary(color: Colors.white),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _handleFavorite(VideoInfo videoInfo) async {
    try {
      final favoriteData = {
        'cover': videoInfo.cover,
        'save_time': DateTime.now().millisecondsSinceEpoch,
        'source_name': videoInfo.sourceName,
        'title': videoInfo.title,
        'total_episodes': videoInfo.totalEpisodes,
        'year': videoInfo.year,
      };

      final result = await PageCacheService()
          .addFavorite(videoInfo.source, videoInfo.id, favoriteData, context);

      if (result.success) {
        if (mounted) setState(() {});
      } else {
        if (mounted) {
          _showSnackBar(result.errorMessage ?? '收藏失败', AppColors.error);
        }
        await _refreshFavorites();
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('收藏失败: ${e.toString()}', AppColors.error);
      }
      await _refreshFavorites();
    }
  }

  Future<void> _handleUnfavorite(VideoInfo videoInfo) async {
    try {
      FavoritesGrid.removeFavoriteFromUI(videoInfo.source, videoInfo.id);
      if (mounted) setState(() {});

      final result = await PageCacheService()
          .removeFavorite(videoInfo.source, videoInfo.id, context);

      if (!result.success) {
        if (mounted) {
          _showSnackBar(result.errorMessage ?? '取消收藏失败', AppColors.error);
        }
        await _refreshFavorites();
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('取消收藏失败: ${e.toString()}', AppColors.error);
      }
      await _refreshFavorites();
    }
  }

  /// 检查值是否为无效的程序关键字
  bool _isInvalidValue(String value) {
    final lowerValue = value.toLowerCase().trim();
    const invalidValues = {
      'null',
      'undefined',
      'unknown',
      'none',
      'nan',
      'infinity',
      '-infinity',
      'nil',
      'empty',
      'void',
      'default',
      'error',
      'exception',
    };
    return invalidValues.contains(lowerValue);
  }

  List<SelectorOption> get _sourceOptions {
    final sources = _searchResults
        .map((r) => r.sourceName)
        .where((s) => s.isNotEmpty && !_isInvalidValue(s))
        .toSet()
        .toList();
    sources.sort();
    final options =
        sources.map((s) => SelectorOption(label: s, value: s)).toList();
    return [
      const SelectorOption(label: '全部来源', value: 'all'),
      ...options,
    ];
  }

  List<SelectorOption> get _yearOptions {
    final years = _searchResults
        .map((r) => r.year)
        .where((y) => y.isNotEmpty && !_isInvalidValue(y))
        .toSet()
        .toList();
    years.sort((a, b) => b.compareTo(a));
    final options =
        years.map((y) => SelectorOption(label: y, value: y)).toList();
    return [
      const SelectorOption(label: '全部年份', value: 'all'),
      ...options,
    ];
  }

  List<SelectorOption> get _titleOptions {
    final titles = _searchResults
        .map((r) => r.title)
        .where((t) => t.isNotEmpty && !_isInvalidValue(t))
        .toSet()
        .toList();
    titles.sort();
    final options =
        titles.map((t) => SelectorOption(label: t, value: t)).toList();
    return [
      const SelectorOption(label: '全部标题', value: 'all'),
      ...options,
    ];
  }
}

/// 玻璃拟态按钮
class _GlassButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final bool isDark;
  final EdgeInsetsGeometry padding;

  const _GlassButton({
    required this.onTap,
    required this.child,
    required this.isDark,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              isDark
                  ? AppColors.darkElevated.withValues(alpha: 0.8)
                  : AppColors.lightSurface.withValues(alpha: 0.8),
              isDark
                  ? AppColors.darkElevated.withValues(alpha: 0.4)
                  : AppColors.lightSurface.withValues(alpha: 0.4),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color:
                isDark ? AppColors.darkGlassBorder : AppColors.lightGlassBorder,
          ),
          boxShadow: isDark ? AppShadows.darkGlass : AppShadows.lightGlass,
        ),
        child: child,
      ),
    );
  }
}

/// 发光按钮
class _GlowButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final Color backgroundColor;

  const _GlowButton({
    required this.onTap,
    required this.child,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              backgroundColor,
              backgroundColor.withValues(alpha: 0.8),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: backgroundColor.withValues(alpha: 0.4),
              blurRadius: 20,
              spreadRadius: -5,
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// 移动端筛选选项底部弹窗（高性能版本）
///
/// 使用 ListView.builder 实现虚拟列表，支持大量数据流畅滑动
/// 当选项超过20个时自动启用搜索功能
class _FilterOptionsBottomSheet extends StatefulWidget {
  final String title;
  final List<SelectorOption> options;
  final String selectedValue;
  final ValueChanged<String> onSelected;
  final bool isDark;

  const _FilterOptionsBottomSheet({
    required this.title,
    required this.options,
    required this.selectedValue,
    required this.onSelected,
    required this.isDark,
  });

  @override
  State<_FilterOptionsBottomSheet> createState() =>
      _FilterOptionsBottomSheetState();
}

class _FilterOptionsBottomSheetState extends State<_FilterOptionsBottomSheet> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<SelectorOption> get _filteredOptions {
    if (_searchQuery.isEmpty) return widget.options;
    return widget.options
        .where((option) =>
            option.label.toLowerCase().contains(_searchQuery.toLowerCase()))
        .toList();
  }

  /// 是否显示搜索栏（对所有筛选类型启用，方便快速定位）
  bool get _showSearch => widget.options.length > 20;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final filteredOptions = _filteredOptions;

    return Container(
      margin: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            widget.isDark ? AppColors.darkSurface : AppColors.lightSurface,
            widget.isDark
                ? AppColors.darkBackground
                : AppColors.lightBackground,
          ],
        ),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 拖动指示器
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textTertiary(isDark: widget.isDark),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: AppTypography.headlineSmallStyle(
                      isDark: widget.isDark,
                    ),
                  ),
                ),
                // 选项数量徽章
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${widget.options.length}',
                    style: AppTypography.mono(
                      fontSize: 12,
                      fontWeight: AppTypography.medium,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 搜索栏（选项较多时显示）
          if (_showSearch) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.isDark
                      ? AppColors.darkElevated
                      : AppColors.lightElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: widget.isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                  ),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  style: AppTypography.primary(
                    color: AppColors.textPrimary(isDark: widget.isDark),
                  ),
                  decoration: InputDecoration(
                    hintText: '搜索${widget.title}...',
                    hintStyle: AppTypography.primary(
                      color: AppColors.textTertiary(isDark: widget.isDark),
                    ),
                    prefixIcon: Icon(
                      LucideIcons.search,
                      color: AppColors.textSecondary(isDark: widget.isDark),
                      size: 20,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? GestureDetector(
                            onTap: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                            child: Icon(
                              LucideIcons.x,
                              color: AppColors.textSecondary(
                                  isDark: widget.isDark),
                              size: 18,
                            ),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value);
                  },
                ),
              ),
            ),
          ],
          // 选项列表（使用 ListView.builder 实现高性能虚拟列表）
          Flexible(
            child: filteredOptions.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    itemCount: filteredOptions.length,
                    itemBuilder: (context, index) {
                      final option = filteredOptions[index];
                      final isSelected = option.value == widget.selectedValue;

                      return AppAnimations.entrance(
                        delay: index * 0.01,
                        child: _FilterOptionItem(
                          option: option,
                          isSelected: isSelected,
                          isDark: widget.isDark,
                          onTap: () {
                            widget.onSelected(option.value);
                            Navigator.pop(context);
                          },
                        ),
                      );
                    },
                  ),
          ),
          // 底部安全区域 + 额外间距
          SizedBox(height: 16 + bottomInset),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.textTertiary(isDark: widget.isDark)
                    .withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(
                LucideIcons.search,
                size: 32,
                color: AppColors.textTertiary(isDark: widget.isDark),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '未找到匹配项',
              style:
                  AppTypography.bodyLargeStyle(isDark: widget.isDark).copyWith(
                color: AppColors.textSecondary(isDark: widget.isDark),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 筛选选项列表项
class _FilterOptionItem extends StatelessWidget {
  final SelectorOption option;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  const _FilterOptionItem({
    required this.option,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppAnimations.fast,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          gradient: isSelected ? AppColors.primaryGradient : null,
          color: isSelected
              ? null
              : isDark
                  ? AppColors.darkElevated
                  : AppColors.lightElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.5)
                : isDark
                    ? AppColors.darkBorder
                    : AppColors.lightBorder,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option.label,
                style: AppTypography.primary(
                  fontSize: 15,
                  fontWeight:
                      isSelected ? AppTypography.medium : AppTypography.regular,
                  color: isSelected
                      ? Colors.white
                      : AppColors.textPrimary(isDark: isDark),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.white24,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.check,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
