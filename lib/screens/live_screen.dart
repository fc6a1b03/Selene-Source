import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:selene/components/animations/modern_loading_animation.dart';
import 'package:selene/design/colors.dart';
import 'package:selene/models/live_channel.dart';
import 'package:selene/models/live_source.dart';
import 'package:selene/screens/live_player_screen.dart';
import 'package:selene/services/live_service.dart';
import 'package:selene/services/source_speed_test_service.dart';
import 'package:selene/services/speed_test_cache_service.dart';
import 'package:selene/services/theme_service.dart';
import 'package:selene/utils/device_utils.dart';
import 'package:selene/utils/font_utils.dart';
import 'package:selene/widgets/filter_options_selector.dart';
import 'package:selene/widgets/filter_pill_hover.dart';

/// 速度过滤类型
enum SpeedFilterType {
  all('全部', Colors.grey),
  fast('极快', Color(0xFF27ae60)), // 绿色
  normal('一般', Color(0xFFf39c12)), // 橙色
  slow('较慢', Color(0xFFe67e22)), // 深橙
  unavailable('不可用', Color(0xFFe74c3c)); // 红色

  final String label;
  final Color color;

  const SpeedFilterType(this.label, this.color);
}

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});

  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen>
    with SingleTickerProviderStateMixin {
  List<LiveChannelGroup> _channelGroups = [];
  List<LiveSource> _liveSources = [];
  LiveSource? _currentSource;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _isInitialLoad = true; // 标记是否是首次加载
  String? _errorMessage;
  String _selectedGroup = '全部';
  final ScrollController _scrollController = ScrollController();
  late AnimationController _refreshIconController;
  bool _isRefreshButtonHovered = false;

  // 测速相关
  SourceSpeedTestService? _speedTestService;
  final Map<String, bool> _channelAvailability = {}; // 频道可用性缓存
  final Map<String, int> _channelLatency = {}; // 频道延迟缓存
  bool _isSpeedTesting = false; // 是否正在测速
  int _speedTestProgress = 0; // 测速进度
  int _speedTestTotal = 0; // 测速总数

  // 速度过滤相关
  SpeedFilterType _selectedSpeedFilter = SpeedFilterType.all;

  // 搜索相关
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearching = false;
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _refreshIconController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    // 延迟加载数据，避免页面切换动画卡顿
    // 使用延迟确保页面切换动画完成后再开始加载数据
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // 再延迟150ms，确保页面切换动画已完成
        Future<void>.delayed(const Duration(milliseconds: 150), () {
          if (mounted) {
            _loadChannels();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _refreshIconController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _speedTestService?.cancelAllTests();
    _speedTestService?.dispose();
    _speedTestService = null;
    super.dispose();
  }

  /// 批量测速当前显示的频道
  Future<void> _testChannelsSpeed() async {
    final channels = _getFilteredChannels();
    if (channels.isEmpty) return;

    // 取消之前的测速
    _speedTestService?.cancelAllTests();
    _speedTestService?.dispose();
    _speedTestService = SourceSpeedTestService();

    setState(() {
      _isSpeedTesting = true;
      _speedTestProgress = 0;
      _speedTestTotal = channels.length;
      // 清空之前的测速结果
      _channelAvailability.clear();
      _channelLatency.clear();
    });

    try {
      // 构建测速列表
      final urls = channels
          .map((c) => {'id': c.id, 'url': c.url})
          .where((item) => item['url']!.isNotEmpty)
          .toList();

      await _speedTestService!.batchCheckUrls(
        urls: urls,
        maxConcurrency: 10, // 直播测速并发数可以高一些
        onResult: (String id,
            {required bool isAvailable, required int latencyMs}) {
          setState(() {
            _channelAvailability[id] = isAvailable;
            _channelLatency[id] = latencyMs;
            _speedTestProgress++;
          });
        },
      );
    } catch (e) {
      debugPrint('测速失败: $e');
    } finally {
      // 测速完成后，对频道进行排序
      _sortChannelsByLatency();

      // 保存测速结果到缓存
      if (_currentSource != null) {
        await SpeedTestCacheService.saveCache(
          _currentSource!.key,
          _currentSource!.url,
          _channelAvailability,
          _channelLatency,
        );
      }

      setState(() {
        _isSpeedTesting = false;
      });
      // 清理测速服务
      _speedTestService?.dispose();
      _speedTestService = null;
    }
  }

  /// 从缓存加载测速结果
  Future<void> _loadCachedSpeedTestResults(
      String sourceKey, String sourceUrl) async {
    try {
      final cache = SpeedTestCacheService.getCache(
        sourceKey,
        sourceUrl: sourceUrl,
      );
      if (cache == null) {
        debugPrint('没有可用的测速缓存: $sourceKey');
        return;
      }

      // 清空旧的结果
      _channelAvailability.clear();
      _channelLatency.clear();

      // 从缓存加载结果
      for (final item in cache.items) {
        _channelAvailability[item.channelId] = item.isAvailable;
        _channelLatency[item.channelId] = item.latencyMs;
      }

      // 更新UI，并自动选中极快过滤
      if (mounted) {
        setState(() {
          // 如果有极快频道，自动选中极快过滤
          final hasFastChannels = cache.items.any(
            (item) => item.isAvailable && item.latencyMs < 200,
          );
          if (hasFastChannels) {
            _selectedSpeedFilter = SpeedFilterType.fast;
          }
        });
      }

      debugPrint(
          '已加载测速缓存: $sourceKey, 共 ${cache.items.length} 个频道, 缓存时间: ${cache.lastUpdated}');
    } catch (e) {
      debugPrint('加载测速缓存失败: $e');
    }
  }

  /// 根据测速延迟对频道列表进行排序
  /// 对每个分组内的频道分别排序
  void _sortChannelsByLatency() {
    if (_channelLatency.isEmpty || _channelGroups.isEmpty) return;

    // 延迟到下一帧执行，避免阻塞当前UI渲染
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 对每个分组内的频道进行排序
      final sortedGroups = <LiveChannelGroup>[];

      for (final group in _channelGroups) {
        // 复制当前分组的频道列表进行排序
        final sortedChannels = List<LiveChannel>.from(group.channels);

        // 对频道进行排序：可用的按延迟排序，不可用排在最后
        sortedChannels.sort((a, b) {
          final latencyA = _channelLatency[a.id] ?? -1;
          final latencyB = _channelLatency[b.id] ?? -1;

          // -1 表示未测试或不可用，排在最后
          if (latencyA < 0 && latencyB < 0) return 0;
          if (latencyA < 0) return 1;
          if (latencyB < 0) return -1;

          // 按延迟从小到大排序
          return latencyA.compareTo(latencyB);
        });

        // 创建新的分组对象（保持分组名称，更新频道顺序）
        sortedGroups.add(LiveChannelGroup(
          name: group.name,
          channels: sortedChannels,
        ));
      }

      // 检查列表是否真的发生了变化
      var hasChanged = false;
      for (var i = 0; i < sortedGroups.length; i++) {
        final oldChannels = _channelGroups[i].channels;
        final newChannels = sortedGroups[i].channels;

        if (oldChannels.length != newChannels.length) {
          hasChanged = true;
          break;
        }

        for (var j = 0; j < oldChannels.length; j++) {
          if (oldChannels[j].id != newChannels[j].id) {
            hasChanged = true;
            break;
          }
        }

        if (hasChanged) break;
      }

      // 只有顺序变化了才更新UI
      if (hasChanged && mounted) {
        setState(() {
          _channelGroups = sortedGroups;
        });
        debugPrint('直播频道列表已按延迟排序');
      }
    });
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _loadChannels({LiveSource? source}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. 获取所有直播源
      final liveSources = await LiveService.getLiveSources();
      if (liveSources.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = '暂无直播源';
            _isLoading = false;
            _isInitialLoad = false;
            _liveSources = [];
            _currentSource = null;
          });
        }
        return;
      }
      // 2. 确定要使用的直播源
      final targetSource = source ?? _currentSource ?? liveSources.first;
      // 在确定加载源后立即展示源筛选（更新状态）
      if (mounted) {
        setState(() {
          _liveSources = liveSources;
          _currentSource = targetSource;
          _isInitialLoad = false;
        });
      }
      // 3. 获取该直播源的频道列表
      final channels = await LiveService.getLiveChannels(targetSource.key);
      if (channels.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = '该直播源暂无频道';
            _isLoading = false;
          });
        }
        return;
      }
      // 4. 获取去重后的频道列表
      final uniqueChannels = LiveService.getUniqueChannels(channels);
      // 5. 按 group 进行聚类
      final Map<String, List<LiveChannel>> groupedChannels = {};
      for (var channel in uniqueChannels) {
        final groupName = channel.group.isEmpty ? '未分组' : channel.group;
        if (!groupedChannels.containsKey(groupName)) {
          groupedChannels[groupName] = [];
        }
        groupedChannels[groupName]!.add(channel);
      }
      // 6. 转换为 LiveChannelGroup 列表
      final groups = groupedChannels.entries
          .map((entry) => LiveChannelGroup(
                name: entry.key,
                channels: entry.value,
              ))
          .toList();

      if (mounted) {
        setState(() {
          _channelGroups = groups;
          _isLoading = false;
        });
        // 加载缓存的测速结果（传入 sourceUrl 用于验证源是否变化）
        await _loadCachedSpeedTestResults(targetSource.key, targetSource.url);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '加载失败: $e';
          _isLoading = false;
          _isInitialLoad = false;
        });
      }
    }
  }

  Future<void> refreshChannels() async {
    if (mounted) {
      setState(() {
        _isRefreshButtonHovered = false;
        _isRefreshing = true;
        _errorMessage = null;
        // 刷新时清除测速结果和过滤条件
        _channelAvailability.clear();
        _channelLatency.clear();
        _selectedSpeedFilter = SpeedFilterType.all;
        _searchQuery = '';
        _searchController.clear();
        _isSearching = false;
      });
    }
    unawaited(_refreshIconController.repeat());
    try {
      LiveService.clearAllChannelsAndEpgCache();
      // 1. 重新获取所有直播源
      final liveSources = await LiveService.getLiveSources(forceRefresh: true);
      if (liveSources.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = '暂无直播源';
            _liveSources = [];
            _currentSource = null;
          });
        }
        return;
      }
      // 2. 检查当前源是否还存在
      LiveSource? targetSource;
      if (_currentSource != null) {
        // 尝试在新的源列表中找到当前源
        try {
          targetSource = liveSources.firstWhere(
            (source) => source.key == _currentSource!.key,
          );
        } catch (e) {
          // 当前源不存在，使用第一个源
          targetSource = liveSources.first;
          if (mounted) {
            _showMessage('当前源已不存在，已切换到 ${targetSource.name}');
          }
        }
      } else {
        // 没有当前源，使用第一个源
        targetSource = liveSources.first;
      }
      // 3. 获取目标源的频道列表
      final channels = await LiveService.getLiveChannels(targetSource.key);
      if (channels.isEmpty) {
        if (mounted) {
          setState(() {
            _errorMessage = '该直播源暂无频道';
            _liveSources = liveSources;
            _currentSource = targetSource;
          });
        }
        return;
      }
      // 4. 获取去重后的频道列表
      final uniqueChannels = LiveService.getUniqueChannels(channels);
      // 5. 按 group 进行聚类
      final Map<String, List<LiveChannel>> groupedChannels = {};
      for (var channel in uniqueChannels) {
        final groupName = channel.group.isEmpty ? '未分组' : channel.group;
        if (!groupedChannels.containsKey(groupName)) {
          groupedChannels[groupName] = [];
        }
        groupedChannels[groupName]!.add(channel);
      }
      // 6. 转换为 LiveChannelGroup 列表
      final groups = groupedChannels.entries
          .map((entry) => LiveChannelGroup(
                name: entry.key,
                channels: entry.value,
              ))
          .toList();
      if (mounted) {
        setState(() {
          _channelGroups = groups;
          _liveSources = liveSources;
          _currentSource = targetSource;
        });
        // _showMessage('刷新成功');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = '刷新失败: $e';
        });
        _showMessage('刷新失败: $e');
      }
    } finally {
      // 停止旋转动画
      if (mounted) {
        _refreshIconController.stop();
        _refreshIconController.reset();
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: FontUtils.poppins(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF3498DB),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  List<LiveChannel> _getFilteredChannels() {
    // 1. 先按分组过滤
    List<LiveChannel> channels;
    if (_selectedGroup == '全部') {
      channels = _channelGroups.expand((g) => g.channels).toList();
    } else {
      channels = _channelGroups
          .firstWhere((g) => g.name == _selectedGroup,
              orElse: () => LiveChannelGroup(name: '', channels: []))
          .channels;
    }

    // 2. 按速度过滤（仅在测速完成后有效）
    final isSpeedFilterActive = _selectedSpeedFilter != SpeedFilterType.all &&
        _channelAvailability.isNotEmpty;

    if (isSpeedFilterActive) {
      channels = channels.where((channel) {
        final isAvailable = _channelAvailability[channel.id];
        final latencyMs = _channelLatency[channel.id];

        switch (_selectedSpeedFilter) {
          case SpeedFilterType.fast:
            return isAvailable == true && (latencyMs ?? 9999) < 200;
          case SpeedFilterType.normal:
            return isAvailable == true &&
                (latencyMs ?? 9999) >= 200 &&
                (latencyMs ?? 9999) < 500;
          case SpeedFilterType.slow:
            return isAvailable == true && (latencyMs ?? 9999) >= 500;
          case SpeedFilterType.unavailable:
            return isAvailable == false;
          case SpeedFilterType.all:
            return true;
        }
      }).toList();

      // 速度过滤激活时，按速度排序（快的在前）
      // 使用稳定的排序算法，确保相同延迟的频道保持相对顺序
      channels.sort((a, b) {
        final latencyA = _channelLatency[a.id] ?? -1;
        final latencyB = _channelLatency[b.id] ?? -1;

        // -1 表示未测试或不可用，排在最后
        if (latencyA < 0 && latencyB < 0) return 0;
        if (latencyA < 0) return 1;
        if (latencyB < 0) return -1;

        // 按延迟从小到大排序（速度快的在前）
        return latencyA.compareTo(latencyB);
      });
    }

    // 3. 按搜索关键词过滤
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      channels = channels.where((channel) {
        return channel.name.toLowerCase().contains(query) ||
            channel.group.toLowerCase().contains(query);
      }).toList();
    }

    return channels;
  }

  /// 获取当前过滤结果的统计信息
  Map<String, int> _getFilteredStats() {
    final allChannels = _selectedGroup == '全部'
        ? _channelGroups.expand((g) => g.channels).toList()
        : _channelGroups
            .firstWhere((g) => g.name == _selectedGroup,
                orElse: () => LiveChannelGroup(name: '', channels: []))
            .channels;

    var fast = 0;
    var normal = 0;
    var slow = 0;
    var unavailable = 0;
    var untested = 0;

    for (final channel in allChannels) {
      final isAvailable = _channelAvailability[channel.id];
      final latencyMs = _channelLatency[channel.id];

      if (isAvailable == null) {
        untested++;
      } else if (!isAvailable) {
        unavailable++;
      } else if (latencyMs != null) {
        if (latencyMs < 200) {
          fast++;
        } else if (latencyMs < 500) {
          normal++;
        } else {
          slow++;
        }
      }
    }

    return {
      'total': allChannels.length,
      'fast': fast,
      'normal': normal,
      'slow': slow,
      'unavailable': unavailable,
      'untested': untested,
    };
  }

  /// 清除所有过滤条件
  void _clearFilters() {
    setState(() {
      _selectedGroup = '全部';
      _selectedSpeedFilter = SpeedFilterType.all;
      _searchQuery = '';
      _searchController.clear();
      _isSearching = false;
    });
    _scrollToTop();
  }

  @override
  Widget build(BuildContext context) {
    // 使用 Selector 只监听 isDarkMode 变化
    return Selector<ThemeService, bool>(
      selector: (_, themeService) => themeService.isDarkMode,
      builder: (context, isDarkMode, child) {
        return Column(
          children: [
            _buildTopBar(isDarkMode),
            Expanded(
              child: _isRefreshing
                  ? _buildRefreshingView(isDarkMode)
                  : _isLoading
                      ? _buildLoadingView(isDarkMode)
                      : _errorMessage != null
                          ? _buildErrorView(isDarkMode)
                          : _buildChannelList(isDarkMode),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar(bool isDarkMode) {
    final allGroups = ['全部', ..._channelGroups.map((g) => g.name)];

    // 构建分组选项
    final groupOptions =
        allGroups.map((g) => SelectorOption(label: g, value: g)).toList();

    // 构建直播源选项
    final sourceOptions = _liveSources
        .map((s) => SelectorOption(label: s.name, value: s.key))
        .toList();

    // 判断是否只有一个直播源
    final showSourceFilter = _liveSources.length > 1;

    // 首次加载时隐藏分组筛选
    final showGroupFilter = !_isInitialLoad && _channelGroups.isNotEmpty;

    // 是否显示速度过滤（测速完成后才显示）
    final showSpeedFilter = !_isInitialLoad &&
        _channelGroups.isNotEmpty &&
        _channelAvailability.isNotEmpty;

    // 获取过滤统计
    final stats = _getFilteredStats();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      color: Colors.transparent,
      child: Row(
        children: [
          // 直播源筛选（只有多个源时显示）
          if (showSourceFilter) ...[
            _buildFilterPill(
              '直播源',
              sourceOptions,
              _currentSource?.key ?? '',
              (value) {
                final source = _liveSources.firstWhere((s) => s.key == value);
                // 立即更新选中的源
                setState(() {
                  _currentSource = source;
                  _selectedGroup = '全部';
                  _selectedSpeedFilter = SpeedFilterType.all;
                  _searchQuery = '';
                  _searchController.clear();
                });
                _loadChannels(source: source);
                _scrollToTop();
              },
              isDarkMode,
            ),
            const SizedBox(width: 8),
          ],
          // 分组筛选（首次加载完成后才显示）
          if (showGroupFilter) ...[
            _buildFilterPill(
              '分组',
              groupOptions,
              _selectedGroup,
              (value) {
                setState(() {
                  _selectedGroup = value;
                });
                _scrollToTop();
              },
              isDarkMode,
            ),
            // 显示分组内的频道数量
            if (_selectedGroup != '全部')
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  '(${stats['total']})',
                  style: FontUtils.poppins(
                    fontSize: 12,
                    color: isDarkMode ? Colors.grey[500] : Colors.grey[600],
                  ),
                ),
              ),
          ],
          // 速度筛选（测速完成后显示）
          if (showSpeedFilter) ...[
            const SizedBox(width: 8),
            _buildSpeedFilterPill(isDarkMode, stats),
          ],
          const Spacer(),
          // 搜索框
          if (!_isInitialLoad && _channelGroups.isNotEmpty)
            _buildSearchBox(isDarkMode),
          const SizedBox(width: 8),
          // 测速按钮
          if (!_isInitialLoad && _channelGroups.isNotEmpty)
            _buildSpeedTestButton(isDarkMode),
          // 刷新按钮
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: MouseRegion(
              cursor: DeviceUtils.isPC() && !_isRefreshing
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
              onEnter: DeviceUtils.isPC() && !_isRefreshing
                  ? (_) {
                      setState(() {
                        _isRefreshButtonHovered = true;
                      });
                    }
                  : null,
              onExit: DeviceUtils.isPC() && !_isRefreshing
                  ? (_) {
                      setState(() {
                        _isRefreshButtonHovered = false;
                      });
                    }
                  : null,
              child: GestureDetector(
                onTap: _isRefreshing ? null : refreshChannels,
                behavior: HitTestBehavior.opaque,
                child: SizedBox(
                  width: 32,
                  height: 32,
                  child: Center(
                    child: RotationTransition(
                      turns: _refreshIconController,
                      child: Icon(
                        Icons.refresh,
                        size: 20,
                        color: _isRefreshing
                            ? const Color(0xFF27ae60)
                            : (DeviceUtils.isPC() && _isRefreshButtonHovered
                                ? const Color(0xFF27ae60)
                                : (isDarkMode
                                    ? Colors.grey[600]
                                    : Colors.grey[500])),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 构建搜索框
  Widget _buildSearchBox(bool isDarkMode) {
    final isPC = DeviceUtils.isPC();

    if (_isSearching || _searchQuery.isNotEmpty) {
      // 展开状态：显示搜索输入框
      return AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: isPC ? 200 : 150,
        height: 32,
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: (value) {
            setState(() {
              _searchQuery = value;
            });
          },
          style: FontUtils.poppins(
            fontSize: 13,
            color: isDarkMode ? Colors.white : const Color(0xFF2c3e50),
          ),
          decoration: InputDecoration(
            hintText: '搜索频道...',
            hintStyle: FontUtils.poppins(
              fontSize: 13,
              color: isDarkMode ? Colors.grey[500] : Colors.grey[400],
            ),
            prefixIcon: Icon(
              Icons.search,
              size: 16,
              color: isDarkMode ? Colors.grey[500] : Colors.grey[400],
            ),
            suffixIcon: _searchQuery.isNotEmpty
                ? MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _searchQuery = '';
                          _searchController.clear();
                          if (_searchQuery.isEmpty) {
                            _isSearching = false;
                          }
                        });
                      },
                      child: Icon(
                        Icons.close,
                        size: 16,
                        color: isDarkMode ? Colors.grey[500] : Colors.grey[400],
                      ),
                    ),
                  )
                : null,
            filled: true,
            fillColor: isDarkMode
                ? Colors.grey[800]!.withValues(alpha: 0.5)
                : Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
            ),
          ),
        ),
      );
    }

    // 收起状态：显示搜索图标按钮
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          setState(() {
            _isSearching = true;
          });
          // 延迟聚焦，确保动画完成
          Future.delayed(const Duration(milliseconds: 100), () {
            _searchFocusNode.requestFocus();
          });
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isDarkMode
                ? Colors.grey[800]!.withValues(alpha: 0.5)
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.search,
            size: 18,
            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  /// 构建速度筛选按钮
  Widget _buildSpeedFilterPill(bool isDarkMode, Map<String, int> stats) {
    // 构建速度过滤选项
    final speedOptions = [
      SelectorOption(
        label: '${SpeedFilterType.all.label} (${stats['total']})',
        value: SpeedFilterType.all.name,
      ),
      SelectorOption(
        label: '${SpeedFilterType.fast.label} (${stats['fast']})',
        value: SpeedFilterType.fast.name,
      ),
      SelectorOption(
        label: '${SpeedFilterType.normal.label} (${stats['normal']})',
        value: SpeedFilterType.normal.name,
      ),
      SelectorOption(
        label: '${SpeedFilterType.slow.label} (${stats['slow']})',
        value: SpeedFilterType.slow.name,
      ),
      SelectorOption(
        label: '${SpeedFilterType.unavailable.label} (${stats['unavailable']})',
        value: SpeedFilterType.unavailable.name,
      ),
    ];

    final isDefault = _selectedSpeedFilter == SpeedFilterType.all;

    // 构建颜色指示点
    Widget buildColorDot(Color color) {
      return Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(right: 4),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      );
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          _showFilterOptions(
            context,
            '速度筛选',
            speedOptions,
            _selectedSpeedFilter.name,
            (value) {
              setState(() {
                _selectedSpeedFilter = SpeedFilterType.values.firstWhere(
                  (t) => t.name == value,
                  orElse: () => SpeedFilterType.all,
                );
              });
              _scrollToTop();
            },
          );
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDefault
                ? Colors.transparent
                : _selectedSpeedFilter.color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDefault
                  ? (isDarkMode ? Colors.grey[600]! : Colors.grey[400]!)
                  : _selectedSpeedFilter.color,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isDefault)
                buildColorDot(_selectedSpeedFilter.color)
              else
                Icon(
                  Icons.speed,
                  size: 14,
                  color: isDarkMode ? Colors.grey[500] : Colors.grey[600],
                ),
              const SizedBox(width: 4),
              Text(
                isDefault ? '速度' : _selectedSpeedFilter.label,
                style: FontUtils.poppins(
                  fontSize: 12,
                  color: isDefault
                      ? (isDarkMode ? Colors.grey[500] : Colors.grey[600])
                      : _selectedSpeedFilter.color,
                  fontWeight: isDefault ? FontWeight.normal : FontWeight.w500,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: isDefault
                    ? (isDarkMode ? Colors.grey[500] : Colors.grey[600])
                    : _selectedSpeedFilter.color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建测速按钮
  Widget _buildSpeedTestButton(bool isDarkMode) {
    return MouseRegion(
      cursor: DeviceUtils.isPC() && !_isSpeedTesting
          ? SystemMouseCursors.click
          : MouseCursor.defer,
      child: GestureDetector(
        onTap: _isSpeedTesting ? null : _testChannelsSpeed,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: _isSpeedTesting
                ? const Color(0xFF27ae60).withValues(alpha: 0.1)
                : (_channelAvailability.isNotEmpty
                    ? const Color(0xFF3498db).withValues(alpha: 0.1)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _isSpeedTesting
                  ? const Color(0xFF27ae60)
                  : (_channelAvailability.isNotEmpty
                      ? const Color(0xFF3498db)
                      : (isDarkMode ? Colors.grey[600]! : Colors.grey[400]!)),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: _isSpeedTesting
                    ? CircularProgressIndicator(
                        strokeWidth: 2,
                        value: _speedTestTotal > 0
                            ? _speedTestProgress / _speedTestTotal
                            : null,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            Color(0xFF27ae60)),
                      )
                    : Icon(
                        Icons.speed,
                        size: 16,
                        color: _channelAvailability.isNotEmpty
                            ? const Color(0xFF3498db)
                            : (isDarkMode
                                ? Colors.grey[500]
                                : Colors.grey[600]),
                      ),
              ),
              const SizedBox(width: 4),
              Text(
                _isSpeedTesting
                    ? '$_speedTestProgress/$_speedTestTotal'
                    : (_channelAvailability.isNotEmpty ? '已测速' : '测速'),
                style: FontUtils.poppins(
                  fontSize: 12,
                  color: _isSpeedTesting
                      ? const Color(0xFF27ae60)
                      : (_channelAvailability.isNotEmpty
                          ? const Color(0xFF3498db)
                          : (isDarkMode ? Colors.grey[500] : Colors.grey[600])),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPill(
    String title,
    List<SelectorOption> options,
    String selectedValue,
    ValueChanged<String> onSelected,
    bool isDarkMode,
  ) {
    final selectedOption = options.firstWhere(
      (e) => e.value == selectedValue,
      orElse: () => options.first,
    );
    final isDefault = selectedValue == '全部' || selectedValue.isEmpty;

    // 使用与速度筛选一致的样式
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          _showFilterOptions(
              context, title, options, selectedValue, onSelected);
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: isDefault
                ? Colors.transparent
                : const Color(0xFF27ae60).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDefault
                  ? (isDarkMode ? Colors.grey[600]! : Colors.grey[400]!)
                  : const Color(0xFF27ae60),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDefault ? Icons.folder_outlined : Icons.check_circle_outline,
                size: 14,
                color: isDefault
                    ? (isDarkMode ? Colors.grey[500] : Colors.grey[600])
                    : const Color(0xFF27ae60),
              ),
              const SizedBox(width: 4),
              Text(
                isDefault ? title : selectedOption.label,
                style: FontUtils.poppins(
                  fontSize: 12,
                  color: isDefault
                      ? (isDarkMode ? Colors.grey[500] : Colors.grey[600])
                      : const Color(0xFF27ae60),
                  fontWeight: isDefault ? FontWeight.normal : FontWeight.w500,
                ),
              ),
              Icon(
                Icons.arrow_drop_down,
                size: 18,
                color: isDefault
                    ? (isDarkMode ? Colors.grey[500] : Colors.grey[600])
                    : const Color(0xFF27ae60),
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
      ValueChanged<String> onSelected) {
    if (DeviceUtils.isPC()) {
      // PC端使用 filter_options_selector.dart 中的 PC 组件
      showFilterOptionsSelector(
        context: context,
        title: title,
        options: options,
        selectedValue: selectedValue,
        onSelected: onSelected,
        useCompactLayout: title == '分组', // 只有标题筛选使用紧凑布局
      );
    } else {
      // 移动端显示底部弹出
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          final screenWidth = MediaQuery.of(context).size.width;
          final modalWidth =
              DeviceUtils.isTablet(context) ? screenWidth * 0.5 : screenWidth;
          const horizontalPadding = 16.0;
          const spacing = 10.0;
          final itemWidth =
              (modalWidth - horizontalPadding * 2 - spacing * 2) / 3;

          return Container(
            width: DeviceUtils.isTablet(context)
                ? modalWidth
                : double.infinity, // 设置宽度为100%
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, // 左对齐
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ),
                Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.6,
                    minHeight: 200.0,
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: horizontalPadding, vertical: 8),
                      child: Wrap(
                        spacing: spacing,
                        runSpacing: spacing,
                        children: options.map((option) {
                          final isSelected = option.value == selectedValue;
                          return SizedBox(
                            width: itemWidth,
                            child: InkWell(
                              onTap: () {
                                onSelected(option.value);
                                Navigator.pop(context);
                              },
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                alignment: Alignment.centerLeft, // 内容左对齐
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? const Color(0xFF27AE60)
                                      : Theme.of(context)
                                          .chipTheme
                                          .backgroundColor,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  option.label,
                                  textAlign: TextAlign.left, // 文字左对齐
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : null,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      );
    }
  }

  Widget _buildLoadingView(bool isDarkMode) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: isDarkMode
            ? AppColors.darkBackgroundGradient
            : AppColors.lightBackgroundGradient,
      ),
      child: Center(
        child: ModernLoadingAnimation(
          message: '加载中',
          subMessage: '正在获取直播频道',
          isDarkMode: isDarkMode,
        ),
      ),
    );
  }

  Widget _buildRefreshingView(bool isDarkMode) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: isDarkMode
            ? AppColors.darkBackgroundGradient
            : AppColors.lightBackgroundGradient,
      ),
      child: Center(
        child: ModernLoadingAnimation(
          message: '刷新中',
          subMessage: '正在更新直播频道数据',
          isDarkMode: isDarkMode,
        ),
      ),
    );
  }

  Widget _buildErrorView(bool isDarkMode) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: 64,
            color:
                isDarkMode ? const Color(0xFF666666) : const Color(0xFF95a5a6),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? '加载失败',
            style: FontUtils.poppins(
              color: isDarkMode
                  ? const Color(0xFFb0b0b0)
                  : const Color(0xFF7f8c8d),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: refreshChannels,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27ae60),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              '刷新',
              style: FontUtils.poppins(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChannelList(bool isDarkMode) {
    final channels = _getFilteredChannels();
    final stats = _getFilteredStats();

    if (channels.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off,
              size: 48,
              color: isDarkMode
                  ? const Color(0xFF666666)
                  : const Color(0xFF95a5a6),
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty ||
                      _selectedSpeedFilter != SpeedFilterType.all
                  ? '没有符合条件的频道'
                  : '暂无频道',
              style: FontUtils.poppins(
                color: isDarkMode
                    ? const Color(0xFFb0b0b0)
                    : const Color(0xFF7f8c8d),
              ),
            ),
            if (_searchQuery.isNotEmpty ||
                _selectedSpeedFilter != SpeedFilterType.all ||
                _selectedGroup != '全部') ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _clearFilters,
                icon: const Icon(Icons.clear_all, size: 18),
                label: Text(
                  '清除过滤',
                  style: FontUtils.poppins(),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF27ae60),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    // 非 PC 平台直接使用 2 列，PC 平台根据宽度计算列数
    final int crossAxisCount = DeviceUtils.getLiveChannelColumnCount(context);
    const double childAspectRatio = 1.5;

    return Column(
      children: [
        // 结果统计栏
        if (_searchQuery.isNotEmpty ||
            _selectedSpeedFilter != SpeedFilterType.all ||
            _selectedGroup != '全部')
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Text(
                  '显示 ${channels.length} 个频道',
                  style: FontUtils.poppins(
                    fontSize: 12,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                if (stats['total'] != channels.length)
                  Text(
                    ' / 共 ${stats['total']} 个',
                    style: FontUtils.poppins(
                      fontSize: 12,
                      color: isDarkMode ? Colors.grey[500] : Colors.grey[500],
                    ),
                  ),
                const Spacer(),
                // 清除过滤按钮
                if (_searchQuery.isNotEmpty ||
                    _selectedSpeedFilter != SpeedFilterType.all ||
                    _selectedGroup != '全部')
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: _clearFilters,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF27ae60).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.clear_all,
                              size: 12,
                              color: const Color(0xFF27ae60),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '清除',
                              style: FontUtils.poppins(
                                fontSize: 11,
                                color: const Color(0xFF27ae60),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        // 频道网格
        Expanded(
          child: GridView.builder(
            controller: _scrollController,
            cacheExtent: 200,
            padding: const EdgeInsets.all(16),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: childAspectRatio,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: channels.length,
            itemBuilder: (context, index) {
              return _buildChannelCard(channels[index], isDarkMode);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildChannelCard(LiveChannel channel, bool isDarkMode) {
    // 获取测速结果
    final isAvailable = _channelAvailability[channel.id];
    final latencyMs = _channelLatency[channel.id];

    return _LiveChannelCard(
      channel: channel,
      isDarkMode: isDarkMode,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (context) => LivePlayerScreen(
              channel: channel,
              source: _currentSource!,
            ),
          ),
        ).then((_) => _loadChannels());
      },
      buildChannelLogo: _buildChannelLogo,
      isAvailable: isAvailable,
      latencyMs: latencyMs,
    );
  }

  Widget _buildChannelLogo(LiveChannel channel, {required bool isDarkMode}) {
    // 如果有台标，显示台标
    if (channel.logo.isNotEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF2a2a2a) : const Color(0xFFc0c0c0),
        ),
        child: Image.network(
          channel.logo,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) {
            return _buildDefaultPreview(isDarkMode);
          },
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) return child;
            return _buildDefaultPreview(isDarkMode);
          },
        ),
      );
    }
    // 没有台标，显示默认图标
    return _buildDefaultPreview(isDarkMode);
  }

  Widget _buildDefaultPreview(bool isDarkMode) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2a2a2a) : const Color(0xFFc0c0c0),
      ),
      child: Center(
        child: Icon(
          Icons.tv,
          size: 48,
          color: isDarkMode ? const Color(0xFF666666) : const Color(0xFF95a5b0),
        ),
      ),
    );
  }
}

class _LiveChannelCard extends StatefulWidget {
  final LiveChannel channel;
  final bool isDarkMode;
  final VoidCallback onTap;
  final Widget Function(LiveChannel, {required bool isDarkMode})
      buildChannelLogo;
  final bool? isAvailable; // 测速结果：是否可用
  final int? latencyMs; // 测速结果：延迟毫秒

  const _LiveChannelCard({
    required this.channel,
    required this.isDarkMode,
    required this.onTap,
    required this.buildChannelLogo,
    this.isAvailable,
    this.latencyMs,
  });

  @override
  State<_LiveChannelCard> createState() => _LiveChannelCardState();
}

class _LiveChannelCardState extends State<_LiveChannelCard> {
  bool _isHovered = false;

  /// 获取状态颜色
  Color _getStatusColor() {
    if (widget.isAvailable == null) {
      return Colors.transparent; // 未测速
    }
    if (!widget.isAvailable!) {
      return const Color(0xFFe74c3c); // 不可用 - 红色
    }
    // 根据延迟显示不同颜色
    final latency = widget.latencyMs ?? 0;
    if (latency < 200) {
      return const Color(0xFF27ae60); // 极快 - 绿色
    } else if (latency < 500) {
      return const Color(0xFFf39c12); // 一般 - 橙色
    } else {
      return const Color(0xFFe67e22); // 较慢 - 深橙
    }
  }

  /// 构建状态指示器
  Widget _buildStatusIndicator() {
    if (widget.isAvailable == null) {
      return const SizedBox.shrink(); // 未测速不显示
    }

    final color = _getStatusColor();

    return Positioned(
      top: 8,
      right: 8,
      child: Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.isDarkMode ? const Color(0xFF1e1e1e) : Colors.white,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建延迟文本
  Widget _buildLatencyText() {
    if (widget.isAvailable == null || widget.latencyMs == null) {
      return const SizedBox.shrink();
    }

    if (!widget.isAvailable!) {
      return const SizedBox.shrink(); // 不可用不显示延迟
    }

    return Positioned(
      bottom: 8,
      right: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          '${widget.latencyMs}ms',
          style: FontUtils.poppins(
            fontSize: 10,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isPC = DeviceUtils.isPC();

    return MouseRegion(
      cursor: isPC ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: isPC ? (_) => setState(() => _isHovered = true) : null,
      onExit: isPC ? (_) => setState(() => _isHovered = false) : null,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: isPC && _isHovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 卡片主体 - 2:1 长宽比
              Expanded(
                child: AspectRatio(
                  aspectRatio: 2.0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: widget.isDarkMode
                          ? const Color(0xFF1e1e1e)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: widget.buildChannelLogo(widget.channel,
                              isDarkMode: widget.isDarkMode),
                        ),
                        // 状态指示器
                        _buildStatusIndicator(),
                        // 延迟文本
                        _buildLatencyText(),
                      ],
                    ),
                  ),
                ),
              ),
              // 标题 - 放在卡片下方居中
              const SizedBox(height: 8),
              Text(
                widget.channel.name,
                style: FontUtils.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isPC && _isHovered
                      ? const Color(0xFF27ae60)
                      : (widget.isDarkMode
                          ? Colors.white
                          : const Color(0xFF2c3e50)),
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
