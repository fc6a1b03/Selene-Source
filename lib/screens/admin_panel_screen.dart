import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:selene/components/animations/glass_card.dart';
import 'package:selene/controllers/admin_panel_controller.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/models/admin_config.dart';
import 'package:selene/services/theme_service.dart';
import 'package:selene/widgets/admin_category_management_panel.dart';
import 'package:selene/widgets/admin_live_source_management_panel.dart';
import 'package:selene/widgets/admin_owner_tools_card.dart';
import 'package:selene/widgets/admin_panel_responsive.dart';
import 'package:selene/widgets/admin_site_settings_card.dart';
import 'package:selene/widgets/admin_source_management_panel.dart';
import 'package:selene/widgets/admin_user_management_panel.dart';

class AdminPanelScreen extends StatelessWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AdminPanelController>(
      create: (_) => AdminPanelController()..loadConfig(),
      child: const _AdminPanelPage(),
    );
  }
}

class _AdminPanelPage extends StatefulWidget {
  const _AdminPanelPage();

  @override
  State<_AdminPanelPage> createState() => _AdminPanelPageState();
}

class _AdminPanelPageState extends State<_AdminPanelPage> {
  final PageController _pageController = PageController();
  final ScrollController _sectionChipController = ScrollController();
  final Map<_AdminPanelSection, GlobalKey> _sectionChipKeys =
      <_AdminPanelSection, GlobalKey>{};
  _AdminPanelSection _selectedSection = _AdminPanelSection.overview;
  String _lastSectionSignature = '';

  @override
  void dispose() {
    _pageController.dispose();
    _sectionChipController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeService>(
      builder: (
        BuildContext context,
        ThemeService themeService,
        Widget? child,
      ) {
        final bool isDark = themeService.isDarkMode;
        return Theme(
          data: isDark ? themeService.darkTheme : themeService.lightTheme,
          child: Scaffold(
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.backgroundGradient(isDark: isDark),
              ),
              child: SafeArea(
                child: Consumer<AdminPanelController>(
                  builder: (
                    BuildContext context,
                    AdminPanelController controller,
                    Widget? child,
                  ) {
                    final List<_SectionMeta> sections =
                        _buildSections(controller.isOwner);
                    if (!sections.any(
                      (_SectionMeta item) => item.section == _selectedSection,
                    )) {
                      _selectedSection = sections.first.section;
                    }
                    _syncSectionNavigation(sections);

                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: <Widget>[
                          _buildHeader(isDark, controller),
                          const SizedBox(height: 12),
                          _buildSectionChips(isDark, sections),
                          const SizedBox(height: 12),
                          Expanded(
                            child: _buildBody(isDark, controller),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(bool isDark, AdminPanelController controller) {
    return GlassCard(
      isDark: isDark,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(LucideIcons.arrowLeft, size: 18),
            tooltip: '返回',
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '管理面板',
                  style: AppTypography.headlineMediumStyle(isDark: isDark),
                ),
              ],
            ),
          ),
          if (controller.role != null)
            _buildBadge(
              isDark: isDark,
              text: controller.role!.label,
              color:
                  controller.isOwner ? AppColors.accent : AppColors.secondary,
            ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: controller.isLoading ? null : controller.loadConfig,
            icon: const Icon(LucideIcons.refreshCcw, size: 18),
            tooltip: '刷新配置',
          ),
        ],
      ),
    );
  }

  Widget _buildSectionChips(bool isDark, List<_SectionMeta> sections) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        controller: _sectionChipController,
        scrollDirection: Axis.horizontal,
        itemCount: sections.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final _SectionMeta item = sections[index];
          final bool selected = item.section == _selectedSection;
          return KeyedSubtree(
            key: _chipKeyFor(item.section),
            child: ChoiceChip(
              label: Text(item.title),
              avatar: Icon(
                item.icon,
                size: 16,
                color: selected
                    ? Colors.white
                    : AppColors.textSecondary(isDark: isDark),
              ),
              selected: selected,
              onSelected: (_) => _handleSectionSelected(sections, item.section),
              labelStyle:
                  AppTypography.labelLargeStyle(isDark: isDark).copyWith(
                color: selected
                    ? Colors.white
                    : AppColors.textPrimary(isDark: isDark),
              ),
              selectedColor: AppColors.primary,
              backgroundColor: isDark
                  ? AppColors.darkElevated.withValues(alpha: 0.75)
                  : AppColors.lightElevated.withValues(alpha: 0.9),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(
    bool isDark,
    AdminPanelController controller,
  ) {
    if (controller.isLoading && controller.configResult == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (controller.configResult == null) {
      return Center(
        child: GlassCard(
          isDark: isDark,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                controller.errorMessage ?? '无法加载管理面板',
                style: AppTypography.bodyMediumStyle(isDark: isDark),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: controller.loadConfig,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final AdminConfigResult result = controller.configResult!;
    final List<_SectionMeta> sections = _buildSections(controller.isOwner);
    return PageView.builder(
      controller: _pageController,
      physics: Platform.isAndroid || Platform.isIOS
          ? const BouncingScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      allowImplicitScrolling: true,
      onPageChanged: (int index) => _handleSectionPageChanged(sections, index),
      itemCount: sections.length,
      itemBuilder: (BuildContext context, int index) {
        final _AdminPanelSection section = sections[index].section;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _buildSectionPage(
            key: '${section.name}_page',
            section: section,
            isDark: isDark,
            result: result,
            isOwner: controller.isOwner,
            isSavingSiteConfig: controller.isSavingSiteConfig,
            onSaveSiteConfig: controller.saveSiteConfig,
          ),
        );
      },
    );
  }

  Widget _buildSectionPage({
    required String key,
    required _AdminPanelSection section,
    required bool isDark,
    required AdminConfigResult result,
    required bool isOwner,
    required bool isSavingSiteConfig,
    required Future<bool> Function(AdminSiteConfig siteConfig) onSaveSiteConfig,
  }) {
    return switch (section) {
      _AdminPanelSection.overview => KeyedSubtree(
          key: ValueKey<String>(key),
          child: _buildOverviewSectionV3(isDark, result),
        ),
      _AdminPanelSection.site => _buildScrollableSection(
          key: key,
          child: AdminSiteSettingsCard(
            isDark: isDark,
            siteConfig: result.config.siteConfig,
            isSaving: isSavingSiteConfig,
            onSave: onSaveSiteConfig,
          ),
        ),
      _AdminPanelSection.users => KeyedSubtree(
          key: ValueKey<String>(key),
          child: _buildUsersSection(isDark, result.config, isOwner),
        ),
      _AdminPanelSection.sources => KeyedSubtree(
          key: ValueKey<String>(key),
          child: _buildSourcesSection(isDark, result.config),
        ),
      _AdminPanelSection.live => KeyedSubtree(
          key: ValueKey<String>(key),
          child: _buildLiveSection(isDark, result.config),
        ),
      _AdminPanelSection.categories => KeyedSubtree(
          key: ValueKey<String>(key),
          child: _buildCategoriesSection(isDark, result.config),
        ),
      _AdminPanelSection.ownerTools => _buildScrollableSection(
          key: key,
          child: _buildOwnerToolsSectionV2(isDark, result.config),
        ),
    };
  }

  Widget _buildScrollableSection({
    required String key,
    required Widget child,
  }) {
    return SingleChildScrollView(
      key: ValueKey<String>(key),
      padding: const EdgeInsets.only(bottom: 12),
      child: child,
    );
  }

  void _syncSectionNavigation(List<_SectionMeta> sections) {
    final String signature =
        sections.map((_SectionMeta item) => item.section.name).join('|');
    if (signature == _lastSectionSignature) {
      return;
    }
    _lastSectionSignature = signature;
    final int selectedIndex = sections.indexWhere(
      (_SectionMeta item) => item.section == _selectedSection,
    );
    if (selectedIndex < 0) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      if (_pageController.hasClients) {
        final int currentIndex = _currentPageIndex;
        if (currentIndex != selectedIndex) {
          _pageController.jumpToPage(selectedIndex);
        }
      }
      _ensureSectionChipVisible(_selectedSection);
    });
  }

  void _handleSectionSelected(
    List<_SectionMeta> sections,
    _AdminPanelSection section,
  ) {
    final int targetIndex = sections.indexWhere(
      (_SectionMeta item) => item.section == section,
    );
    if (targetIndex < 0) {
      return;
    }
    if (_selectedSection != section) {
      setState(() {
        _selectedSection = section;
      });
    }
    _ensureSectionChipVisible(section);
    if (_pageController.hasClients && _currentPageIndex != targetIndex) {
      _pageController.animateToPage(
        targetIndex,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _handleSectionPageChanged(List<_SectionMeta> sections, int index) {
    if (index < 0 || index >= sections.length) {
      return;
    }
    final _AdminPanelSection section = sections[index].section;
    if (_selectedSection != section) {
      setState(() {
        _selectedSection = section;
      });
    }
    _ensureSectionChipVisible(section);
  }

  int get _currentPageIndex {
    if (!_pageController.hasClients) {
      return 0;
    }
    final double? page = _pageController.page;
    return (page ?? _pageController.initialPage.toDouble()).round();
  }

  GlobalKey _chipKeyFor(_AdminPanelSection section) {
    return _sectionChipKeys.putIfAbsent(section, GlobalKey.new);
  }

  void _ensureSectionChipVisible(_AdminPanelSection section) {
    final BuildContext? chipContext = _chipKeyFor(section).currentContext;
    if (chipContext == null) {
      return;
    }
    Scrollable.ensureVisible(
      chipContext,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: 0.5,
    );
  }

  List<_SectionMeta> _buildSections(bool isOwner) {
    final List<_SectionMeta> items = <_SectionMeta>[
      const _SectionMeta(
          _AdminPanelSection.overview, '总览', LucideIcons.layoutDashboard),
      const _SectionMeta(_AdminPanelSection.site, '站点设置', LucideIcons.settings),
      const _SectionMeta(_AdminPanelSection.users, '用户配置', LucideIcons.users),
      const _SectionMeta(_AdminPanelSection.sources, '视频源', LucideIcons.video),
      const _SectionMeta(_AdminPanelSection.live, '直播源', LucideIcons.tv),
      const _SectionMeta(
          _AdminPanelSection.categories, '分类配置', LucideIcons.folderOpen),
    ];
    if (isOwner) {
      items.add(
        const _SectionMeta(
            _AdminPanelSection.ownerTools, '站长工具', LucideIcons.database),
      );
    }
    return items;
  }

  // ignore: unused_element
  Widget _buildOverviewSection(bool isDark, AdminConfigResult result) {
    final AdminConfig config = result.config;
    return Column(
      key: const ValueKey<String>('overview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '总览',
          style: AppTypography.headlineLargeStyle(isDark: isDark),
        ),
        const SizedBox(height: 8),
        Text(
          '当前已经打通管理配置读取，并提供站点设置的原生保存入口。',
          style: AppTypography.bodyMediumStyle(isDark: isDark).copyWith(
            color: AppColors.textSecondary(isDark: isDark),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: <Widget>[
            _buildStatCard(
                isDark,
                '用户总数',
                '${config.userConfig.users.length}',
                '封禁 ${config.bannedUserCount} 个',
                LucideIcons.users,
                AppColors.primary),
            _buildStatCard(
                isDark,
                '视频源',
                '${config.sourceConfig.length}',
                '禁用 ${config.disabledSourceCount} 个',
                LucideIcons.video,
                AppColors.secondary),
            _buildStatCard(
                isDark,
                '直播源',
                '${config.liveConfig.length}',
                '禁用 ${config.disabledLiveSourceCount} 个',
                LucideIcons.tv,
                AppColors.success),
            _buildStatCard(
                isDark,
                '分类',
                '${config.customCategories.length}',
                '禁用 ${config.disabledCategoryCount} 个',
                LucideIcons.folderTree,
                AppColors.accent),
          ],
        ),
        const SizedBox(height: 16),
        GlassCard(
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '配置快照',
                style: AppTypography.headlineSmallStyle(isDark: isDark),
              ),
              const SizedBox(height: 12),
              _buildKeyValueRow(
                  isDark: isDark,
                  label: '站点名称',
                  value: config.siteConfig.siteName.isEmpty
                      ? '未设置'
                      : config.siteConfig.siteName),
              _buildKeyValueRow(
                  isDark: isDark,
                  label: '配置订阅',
                  value: config.configSubscription.url.isEmpty
                      ? '未配置'
                      : config.configSubscription.url),
              _buildKeyValueRow(
                  isDark: isDark,
                  label: '自动更新',
                  value: config.configSubscription.autoUpdate ? '开启' : '关闭'),
              _buildKeyValueRow(
                  isDark: isDark,
                  label: '配置大小',
                  value: '${config.configFile.length} 字符',
                  isLast: true),
            ],
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
  Widget _buildOverviewSectionV2(bool isDark, AdminConfigResult result) {
    final AdminConfig config = result.config;
    final int ownerCount = config.userConfig.users
        .where((AdminUser user) => user.role == AdminUserRole.owner)
        .length;
    final int adminCount = config.userConfig.users
        .where((AdminUser user) => user.role == AdminUserRole.admin)
        .length;
    final int enabledSourceCount =
        config.sourceConfig.length - config.disabledSourceCount;
    final int enabledLiveCount =
        config.liveConfig.length - config.disabledLiveSourceCount;
    final int customSourceCount = config.sourceConfig
        .where((AdminSourceConfig source) => source.isCustom)
        .length;
    final int customLiveCount = config.liveConfig
        .where((AdminLiveSourceConfig source) => source.isCustom)
        .length;
    final int totalChannels = config.liveConfig.fold<int>(
      0,
      (int total, AdminLiveSourceConfig source) => total + source.channelNumber,
    );
    final List<_OverviewMetric> metrics = <_OverviewMetric>[
      _OverviewMetric(
        title: '用户总数',
        value: '${config.userConfig.users.length}',
        subtitle: '封禁 ${config.bannedUserCount} 个',
        icon: LucideIcons.users,
        color: AppColors.primary,
      ),
      _OverviewMetric(
        title: '视频源',
        value: '${config.sourceConfig.length}',
        subtitle: '启用 $enabledSourceCount 个',
        icon: LucideIcons.video,
        color: AppColors.secondary,
      ),
      _OverviewMetric(
        title: '直播源',
        value: '${config.liveConfig.length}',
        subtitle: '频道 $totalChannels 个',
        icon: LucideIcons.tv,
        color: AppColors.success,
      ),
      _OverviewMetric(
        title: '分类',
        value: '${config.customCategories.length}',
        subtitle: '禁用 ${config.disabledCategoryCount} 个',
        icon: LucideIcons.folderTree,
        color: AppColors.accent,
      ),
    ];

    return LayoutBuilder(
      key: const ValueKey<String>('overview_v2'),
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool tight = AdminPanelLayout.isTightWidth(constraints.maxWidth);
        final double panelWidth =
            tight ? constraints.maxWidth : (constraints.maxWidth - 12) / 2;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AdminSectionHeader(
                  isDark: isDark,
                  title: '总览',
                  description: '当前已经打通管理配置读取，并提供站点管理、权限分配与来源维护的统一入口。'),
              const SizedBox(height: 16),
              GlassCard(
                isDark: isDark,
                padding: EdgeInsets.all(tight ? 16 : 20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? <Color>[
                          const Color(0xFF102A43).withValues(alpha: 0.92),
                          const Color(0xFF0F172A).withValues(alpha: 0.88),
                        ]
                      : <Color>[
                          const Color(0xFFE0F2FE).withValues(alpha: 0.96),
                          const Color(0xFFF8FAFC).withValues(alpha: 0.96),
                        ],
                ),
                child: LayoutBuilder(
                  builder: (
                    BuildContext context,
                    BoxConstraints heroConstraints,
                  ) {
                    final bool compactHero = heroConstraints.maxWidth < 760;
                    final Widget heroContent = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '管理中心已联通',
                          style:
                              AppTypography.displaySmallStyle(isDark: isDark),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '当前可直接维护站点配置、用户权限、视频源、直播源与分类配置，适合在 Windows 桌面和 Android 窄屏场景下快速切换。',
                          style: AppTypography.bodyMediumStyle(
                            isDark: isDark,
                          ).copyWith(
                            color: AppColors.textSecondary(isDark: isDark),
                          ),
                        ),
                      ],
                    );
                    final Widget summaryStrip = Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        _buildOverviewChip(
                          isDark: isDark,
                          label: '启用视频源',
                          value: '$enabledSourceCount',
                          color: AppColors.secondary,
                        ),
                        _buildOverviewChip(
                          isDark: isDark,
                          label: '自定义来源',
                          value: '$customSourceCount',
                          color: AppColors.primary,
                        ),
                        _buildOverviewChip(
                          isDark: isDark,
                          label: '启用直播源',
                          value: '$enabledLiveCount',
                          color: AppColors.success,
                        ),
                      ],
                    );

                    if (compactHero) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          heroContent,
                          const SizedBox(height: 16),
                          summaryStrip,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: heroContent),
                        const SizedBox(width: 16),
                        Flexible(child: summaryStrip),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: metrics.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisExtent: 168,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemBuilder: (BuildContext context, int index) {
                  final _OverviewMetric metric = metrics[index];
                  return _buildModernStatCard(
                    isDark,
                    metric.title,
                    metric.value,
                    metric.subtitle,
                    metric.icon,
                    metric.color,
                  );
                },
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  SizedBox(
                    width: panelWidth,
                    child: GlassCard(
                      isDark: isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '配置快照',
                            style: AppTypography.headlineSmallStyle(
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildResponsiveKeyValueRow(
                            isDark: isDark,
                            label: '站点名称',
                            value: config.siteConfig.siteName.isEmpty
                                ? '未设置'
                                : config.siteConfig.siteName,
                          ),
                          _buildResponsiveKeyValueRow(
                            isDark: isDark,
                            label: '配置订阅',
                            value: config.configSubscription.url.isEmpty
                                ? '未配置'
                                : config.configSubscription.url,
                          ),
                          _buildResponsiveKeyValueRow(
                            isDark: isDark,
                            label: '自动更新',
                            value: config.configSubscription.autoUpdate
                                ? '开启'
                                : '关闭',
                          ),
                          _buildResponsiveKeyValueRow(
                            isDark: isDark,
                            label: '配置大小',
                            value: '${config.configFile.length} 字符',
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: panelWidth,
                    child: GlassCard(
                      isDark: isDark,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            '角色与来源概况',
                            style: AppTypography.headlineSmallStyle(
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildResponsiveKeyValueRow(
                            isDark: isDark,
                            label: '站长',
                            value: '$ownerCount 个',
                          ),
                          _buildResponsiveKeyValueRow(
                            isDark: isDark,
                            label: '管理员',
                            value: '$adminCount 个',
                          ),
                          _buildResponsiveKeyValueRow(
                            isDark: isDark,
                            label: '用户组',
                            value: '${config.userConfig.groups.length} 个',
                          ),
                          _buildResponsiveKeyValueRow(
                            isDark: isDark,
                            label: '自定义直播',
                            value: '$customLiveCount 个',
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOverviewSectionV3(bool isDark, AdminConfigResult result) {
    final AdminConfig config = result.config;
    final int totalUserCount = config.userConfig.users.length;
    final int bannedUserCount = config.bannedUserCount;
    final int activeUserCount = totalUserCount - bannedUserCount;
    final int ownerCount = config.userConfig.users
        .where((AdminUser user) => user.role == AdminUserRole.owner)
        .length;
    final int adminCount = config.userConfig.users
        .where((AdminUser user) => user.role == AdminUserRole.admin)
        .length;
    final int normalUserCount = totalUserCount - ownerCount - adminCount;
    final int groupCount = config.userConfig.groups.length;
    final int limitedGroupCount = config.userConfig.groups
        .where((AdminUserGroup group) => group.enabledApis.isNotEmpty)
        .length;
    final int restrictedUserCount = config.userConfig.users
        .where(
          (AdminUser user) =>
              user.enabledApis.isNotEmpty || user.tags.isNotEmpty,
        )
        .length;
    final int totalSourceCount = config.sourceConfig.length;
    final int enabledSourceCount =
        totalSourceCount - config.disabledSourceCount;
    final int disabledSourceCount = config.disabledSourceCount;
    final int customSourceCount = config.sourceConfig
        .where((AdminSourceConfig source) => source.isCustom)
        .length;
    final int configSourceCount = totalSourceCount - customSourceCount;
    final int totalLiveCount = config.liveConfig.length;
    final int enabledLiveCount =
        totalLiveCount - config.disabledLiveSourceCount;
    final int disabledLiveCount = config.disabledLiveSourceCount;
    final int customLiveCount = config.liveConfig
        .where((AdminLiveSourceConfig source) => source.isCustom)
        .length;
    final int totalChannels = config.liveConfig.fold<int>(
      0,
      (int total, AdminLiveSourceConfig source) => total + source.channelNumber,
    );
    final int averageChannelsPerLive =
        totalLiveCount == 0 ? 0 : (totalChannels / totalLiveCount).round();
    final int maxChannelsPerLive = config.liveConfig.isEmpty
        ? 0
        : config.liveConfig
            .map((AdminLiveSourceConfig source) => source.channelNumber)
            .reduce(math.max);
    final int totalCategoryCount = config.customCategories.length;
    final int enabledCategoryCount =
        totalCategoryCount - config.disabledCategoryCount;
    final bool hasSubscription = config.configSubscription.url.isNotEmpty;
    final String lastCheckText = _formatOverviewDateTime(
      config.configSubscription.lastCheck,
    );
    final String siteName =
        config.siteConfig.siteName.isEmpty ? '未设置' : config.siteConfig.siteName;
    final String subscriptionUrl =
        hasSubscription ? config.configSubscription.url : '未配置';
    final String announcementState =
        config.siteConfig.announcement.trim().isEmpty ? '空' : '已填充';

    final List<_OverviewMetric> metrics = <_OverviewMetric>[
      _OverviewMetric(
        title: '用户总数',
        value: '$totalUserCount',
        subtitle: '活跃 $activeUserCount 个',
        icon: LucideIcons.users,
        color: AppColors.primary,
      ),
      _OverviewMetric(
        title: '受限用户',
        value: '$restrictedUserCount',
        subtitle: '封禁 $bannedUserCount 个',
        icon: LucideIcons.shield,
        color: AppColors.accent,
      ),
      _OverviewMetric(
        title: '视频源',
        value: '$totalSourceCount',
        subtitle: '启用 $enabledSourceCount 个',
        icon: LucideIcons.video,
        color: AppColors.secondary,
      ),
      _OverviewMetric(
        title: '自定义视频源',
        value: '$customSourceCount',
        subtitle: '配置源 $configSourceCount 个',
        icon: LucideIcons.database,
        color: AppColors.primary,
      ),
      _OverviewMetric(
        title: '直播源',
        value: '$totalLiveCount',
        subtitle: '启用 $enabledLiveCount 个',
        icon: LucideIcons.tv,
        color: AppColors.success,
      ),
      _OverviewMetric(
        title: '总频道',
        value: '$totalChannels',
        subtitle: '均值 $averageChannelsPerLive / 源',
        icon: LucideIcons.refreshCcw,
        color: AppColors.success,
      ),
      _OverviewMetric(
        title: '用户组',
        value: '$groupCount',
        subtitle: '限制组 $limitedGroupCount 个',
        icon: LucideIcons.shield,
        color: AppColors.warning,
      ),
      _OverviewMetric(
        title: '分类',
        value: '$totalCategoryCount',
        subtitle: '启用 $enabledCategoryCount 个',
        icon: LucideIcons.folderTree,
        color: AppColors.accent,
      ),
    ];
    final List<_OverviewFact> heroFacts = <_OverviewFact>[
      _OverviewFact(
        label: '启用视频源',
        value: '$enabledSourceCount',
        color: AppColors.secondary,
      ),
      _OverviewFact(
        label: '自定义视频源',
        value: '$customSourceCount',
        color: AppColors.primary,
      ),
      _OverviewFact(
        label: '启用直播源',
        value: '$enabledLiveCount',
        color: AppColors.success,
      ),
      _OverviewFact(
        label: '总频道',
        value: '$totalChannels',
        color: AppColors.success,
      ),
      _OverviewFact(
        label: '活跃用户',
        value: '$activeUserCount',
        color: AppColors.accent,
      ),
      _OverviewFact(
        label: '订阅状态',
        value: hasSubscription ? '已配置' : '未配置',
        color: hasSubscription ? AppColors.success : AppColors.warning,
      ),
    ];
    final List<_OverviewFact> snapshotFacts = <_OverviewFact>[
      _OverviewFact(
        label: '站点名称',
        value: siteName,
        color: AppColors.primary,
      ),
      _OverviewFact(
        label: '自动更新',
        value: config.configSubscription.autoUpdate ? '开启' : '关闭',
        color: config.configSubscription.autoUpdate
            ? AppColors.success
            : AppColors.warning,
      ),
      _OverviewFact(
        label: '上次检查',
        value: lastCheckText,
        color: AppColors.secondary,
      ),
      _OverviewFact(
        label: '配置大小',
        value: '${config.configFile.length} 字符',
        color: AppColors.accent,
      ),
      _OverviewFact(
        label: '搜索页数',
        value: '${config.siteConfig.searchDownstreamMaxPage}',
        color: AppColors.secondary,
      ),
      _OverviewFact(
        label: '接口缓存',
        value: '${config.siteConfig.siteInterfaceCacheTime}s',
        color: AppColors.primary,
      ),
      _OverviewFact(
        label: '流式搜索',
        value: config.siteConfig.fluidSearch ? '开启' : '关闭',
        color: config.siteConfig.fluidSearch
            ? AppColors.success
            : AppColors.warning,
      ),
      _OverviewFact(
        label: '黄源过滤',
        value: config.siteConfig.disableYellowFilter ? '开启' : '关闭',
        color: config.siteConfig.disableYellowFilter
            ? AppColors.warning
            : AppColors.success,
      ),
      _OverviewFact(
        label: '公告',
        value: announcementState,
        color:
            announcementState == '已填充' ? AppColors.success : AppColors.warning,
      ),
    ];
    final List<_OverviewFact> roleFacts = <_OverviewFact>[
      _OverviewFact(
        label: '站长',
        value: '$ownerCount 个',
        color: AppColors.accent,
      ),
      _OverviewFact(
        label: '管理员',
        value: '$adminCount 个',
        color: AppColors.secondary,
      ),
      _OverviewFact(
        label: '普通用户',
        value: '$normalUserCount 个',
        color: AppColors.primary,
      ),
      _OverviewFact(
        label: '封禁用户',
        value: '$bannedUserCount 个',
        color: AppColors.error,
      ),
      _OverviewFact(
        label: '用户组',
        value: '$groupCount 个',
        color: AppColors.warning,
      ),
      _OverviewFact(
        label: '限制来源组',
        value: '$limitedGroupCount 个',
        color: AppColors.warning,
      ),
      _OverviewFact(
        label: '受限用户',
        value: '$restrictedUserCount 个',
        color: AppColors.secondary,
      ),
      _OverviewFact(
        label: '订阅状态',
        value: hasSubscription ? '已配置' : '未配置',
        color: hasSubscription ? AppColors.success : AppColors.warning,
      ),
    ];
    final List<_OverviewFact> sourceFacts = <_OverviewFact>[
      _OverviewFact(
        label: '视频源总数',
        value: '$totalSourceCount',
        color: AppColors.secondary,
      ),
      _OverviewFact(
        label: '启用视频源',
        value: '$enabledSourceCount',
        color: AppColors.success,
      ),
      _OverviewFact(
        label: '禁用视频源',
        value: '$disabledSourceCount',
        color: AppColors.error,
      ),
      _OverviewFact(
        label: '自定义视频源',
        value: '$customSourceCount',
        color: AppColors.primary,
      ),
      _OverviewFact(
        label: '直播源总数',
        value: '$totalLiveCount',
        color: AppColors.success,
      ),
      _OverviewFact(
        label: '启用直播源',
        value: '$enabledLiveCount',
        color: AppColors.success,
      ),
      _OverviewFact(
        label: '禁用直播源',
        value: '$disabledLiveCount',
        color: AppColors.error,
      ),
      _OverviewFact(
        label: '自定义直播源',
        value: '$customLiveCount',
        color: AppColors.primary,
      ),
      _OverviewFact(
        label: '启用分类',
        value: '$enabledCategoryCount',
        color: AppColors.accent,
      ),
    ];
    final List<_OverviewFact> channelFacts = <_OverviewFact>[
      _OverviewFact(
        label: '总频道',
        value: '$totalChannels',
        color: AppColors.success,
      ),
      _OverviewFact(
        label: '平均每源',
        value: '$averageChannelsPerLive',
        color: AppColors.secondary,
      ),
      _OverviewFact(
        label: '最大单源',
        value: '$maxChannelsPerLive',
        color: AppColors.primary,
      ),
      _OverviewFact(
        label: '配置源',
        value: '$configSourceCount',
        color: AppColors.accent,
      ),
      _OverviewFact(
        label: '搜索深度',
        value: '${config.siteConfig.searchDownstreamMaxPage} 页',
        color: AppColors.warning,
      ),
      _OverviewFact(
        label: '缓存策略',
        value: '${config.siteConfig.siteInterfaceCacheTime}s',
        color: AppColors.secondary,
      ),
    ];

    return LayoutBuilder(
      key: const ValueKey<String>('overview_v3'),
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool tight = AdminPanelLayout.isTightWidth(constraints.maxWidth);
        final double panelWidth =
            tight ? constraints.maxWidth : (constraints.maxWidth - 12) / 2;

        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              AdminSectionHeader(
                  isDark: isDark, title: '总览', description: '集中查看配置、权限和来源状态。'),
              const SizedBox(height: 16),
              GlassCard(
                isDark: isDark,
                padding: EdgeInsets.all(tight ? 16 : 20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? <Color>[
                          const Color(0xFF102A43).withValues(alpha: 0.92),
                          const Color(0xFF0F172A).withValues(alpha: 0.88),
                        ]
                      : <Color>[
                          const Color(0xFFE0F2FE).withValues(alpha: 0.96),
                          const Color(0xFFF8FAFC).withValues(alpha: 0.96),
                        ],
                ),
                child: LayoutBuilder(
                  builder: (
                    BuildContext context,
                    BoxConstraints heroConstraints,
                  ) {
                    final bool compactHero = heroConstraints.maxWidth < 760;
                    final Widget heroContent = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '概览',
                          style:
                              AppTypography.displaySmallStyle(isDark: isDark),
                        ),
                      ],
                    );
                    final Widget summaryStrip = _buildOverviewFactsGrid(
                      isDark: isDark,
                      facts: heroFacts,
                    );

                    if (compactHero) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          heroContent,
                          const SizedBox(height: 16),
                          summaryStrip,
                        ],
                      );
                    }

                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: heroContent),
                        const SizedBox(width: 16),
                        Flexible(child: summaryStrip),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: metrics.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 280,
                  mainAxisExtent: 168,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemBuilder: (BuildContext context, int index) {
                  final _OverviewMetric metric = metrics[index];
                  return _buildModernStatCard(
                    isDark,
                    metric.title,
                    metric.value,
                    metric.subtitle,
                    metric.icon,
                    metric.color,
                  );
                },
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: <Widget>[
                  SizedBox(
                    width: panelWidth,
                    child: _buildOverviewDetailPanel(
                      isDark: isDark,
                      title: '配置快照',
                      description: '站点设置和订阅状态。',
                      facts: snapshotFacts,
                      footer: _buildOverviewLongValue(
                        isDark: isDark,
                        label: '配置订阅',
                        value: subscriptionUrl,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: panelWidth,
                    child: _buildOverviewDetailPanel(
                      isDark: isDark,
                      title: '角色与权限',
                      description: '用户角色和限制情况。',
                      facts: roleFacts,
                    ),
                  ),
                  SizedBox(
                    width: panelWidth,
                    child: _buildOverviewDetailPanel(
                      isDark: isDark,
                      title: '来源概况',
                      description: '视频源、直播源和分类分布。',
                      facts: sourceFacts,
                    ),
                  ),
                  SizedBox(
                    width: panelWidth,
                    child: _buildOverviewDetailPanel(
                      isDark: isDark,
                      title: '频道与策略',
                      description: '频道规模和关键开关。',
                      facts: channelFacts,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModernStatCard(
    bool isDark,
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return GlassCard(
      isDark: isDark,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: isDark ? 0.16 : 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const Spacer(),
          Text(title, style: AppTypography.labelLargeStyle(isDark: isDark)),
          const SizedBox(height: 6),
          Text(value, style: AppTypography.displaySmallStyle(isDark: isDark)),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: AppTypography.bodySmallStyle(isDark: isDark).copyWith(
              color: AppColors.textSecondary(isDark: isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewDetailPanel({
    required bool isDark,
    required String title,
    required List<_OverviewFact> facts,
    String? description,
    Widget? footer,
  }) {
    return GlassCard(
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: AppTypography.headlineSmallStyle(isDark: isDark),
          ),
          if (description != null && description.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              description,
              style: AppTypography.bodySmallStyle(isDark: isDark).copyWith(
                color: AppColors.textSecondary(isDark: isDark),
              ),
            ),
          ],
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final int columns = constraints.maxWidth < 420 ? 2 : 3;
              final double itemWidth =
                  (constraints.maxWidth - (columns - 1) * 10) / columns;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: facts
                    .map(
                      (_OverviewFact item) => SizedBox(
                        width: itemWidth,
                        child: _buildOverviewFactTile(
                          isDark: isDark,
                          item: item,
                        ),
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          if (footer != null) ...<Widget>[
            const SizedBox(height: 12),
            footer,
          ],
        ],
      ),
    );
  }

  Widget _buildOverviewFactsGrid({
    required bool isDark,
    required List<_OverviewFact> facts,
  }) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double maxWidth = constraints.maxWidth;
        final int columns = maxWidth < 420
            ? 2
            : maxWidth < 760
                ? 3
                : 2;
        final double spacing = 10;
        final double itemWidth =
            ((maxWidth - spacing * (columns - 1)) / columns).clamp(
          96.0,
          220.0,
        );

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: facts
              .map(
                (_OverviewFact item) => SizedBox(
                  width: itemWidth,
                  child: _buildOverviewChip(
                    isDark: isDark,
                    label: item.label,
                    value: item.value,
                    color: item.color,
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }

  Widget _buildOverviewFactTile({
    required bool isDark,
    required _OverviewFact item,
  }) {
    return Container(
      height: 82,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: item.color.withValues(alpha: isDark ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: item.color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            item.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelMediumStyle(isDark: isDark).copyWith(
              color: item.color,
            ),
          ),
          Text(
            item.value,
            maxLines: item.value.contains('\n') ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodyLargeStyle(isDark: isDark).copyWith(
              fontWeight: FontWeight.w600,
              height: item.value.contains('\n') ? 1.2 : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewLongValue({
    required bool isDark,
    required String label,
    required String value,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkElevated.withValues(alpha: isDark ? 0.42 : 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.border(isDark: isDark).withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: AppTypography.labelMediumStyle(isDark: isDark),
          ),
          const SizedBox(height: 6),
          SelectableText(
            value,
            style: AppTypography.bodyMediumStyle(isDark: isDark),
          ),
        ],
      ),
    );
  }

  String _formatOverviewDateTime(String value) {
    if (value.trim().isEmpty) {
      return '未检查';
    }

    final String normalized = value.trim().replaceFirst('T', ' ');
    final RegExp pattern = RegExp(
      r'(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})',
    );
    final RegExpMatch? match = pattern.firstMatch(normalized);
    if (match != null) {
      return '${match.group(1)}\n${match.group(2)}';
    }

    final List<String> segments = normalized.split(RegExp(r'\s+'));
    if (segments.length >= 2) {
      final String time = segments[1].split('.').first;
      return '${segments.first}\n$time';
    }
    return normalized;
  }

  Widget _buildOverviewChip({
    required bool isDark,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelMediumStyle(isDark: isDark).copyWith(
              color: color,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.headlineSmallStyle(isDark: isDark).copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveKeyValueRow({
    required bool isDark,
    required String label,
    required String value,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final bool compact = constraints.maxWidth < 480;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: AppTypography.labelMediumStyle(isDark: isDark),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  value,
                  style: AppTypography.bodyMediumStyle(isDark: isDark),
                ),
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 82,
                child: Text(
                  label,
                  style: AppTypography.labelMediumStyle(isDark: isDark),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SelectableText(
                  value,
                  style: AppTypography.bodyMediumStyle(isDark: isDark),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildUsersSection(bool isDark, AdminConfig config, bool isOwner) {
    return AdminUserManagementPanel(
      isDark: isDark,
      userConfig: config.userConfig,
      sources: config.sourceConfig,
      isOwner: isOwner,
      onAction: ({
        required String action,
        String? targetUsername,
        String? targetPassword,
        String? userGroup,
        List<String>? enabledApis,
        List<String>? userGroups,
        String? groupAction,
        String? groupName,
        List<String>? usernames,
      }) {
        final AdminPanelController controller =
            context.read<AdminPanelController>();
        return controller.performUserAction(
          action: action,
          targetUsername: targetUsername,
          targetPassword: targetPassword,
          userGroup: userGroup,
          enabledApis: enabledApis,
          userGroups: userGroups,
          groupAction: groupAction,
          groupName: groupName,
          usernames: usernames,
        );
      },
    );
    /*
    final List<AdminUser> users = config.userConfig.users;
    return _buildCollectionSection<AdminUser>(
      key: 'users',
      title: '用户配置',
      description: isOwner ? '站长视角：已展示用户、用户组和源权限。' : '管理员视角：先展示真实数据，后续继续补齐操作。',
      isDark: isDark,
      items: users,
      emptyText: '暂无用户数据',
      itemBuilder: (BuildContext context, AdminUser user, int index) {
        return _buildInfoTile(
          isDark: isDark,
          leadingIcon: LucideIcons.userRound,
          title: user.username,
          badges: <Widget>[
            _buildBadge(
              isDark: isDark,
              text: user.role.label,
              color: _userRoleColor(user.role),
            ),
            _buildBadge(
              isDark: isDark,
              text: user.banned ? '已封禁' : '正常',
              color: user.banned ? AppColors.error : AppColors.success,
            ),
          ],
          lines: <String>[
            '用户组：${user.tags.isEmpty ? '未分组' : user.tags.join('、')}',
            '源权限：${user.enabledApis.isEmpty ? '未限制' : '${user.enabledApis.length} 个源'}',
          ],
        );
      },
      footer: config.userConfig.groups.isEmpty
          ? null
          : GlassCard(
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '用户组',
                    style: AppTypography.headlineSmallStyle(isDark: isDark),
                  ),
                  const SizedBox(height: 10),
                  ...config.userConfig.groups.map(
                    (AdminUserGroup group) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildInfoTile(
                        isDark: isDark,
                        leadingIcon: LucideIcons.shield,
                        title: group.name,
                        lines: <String>[
                          '允许源：${group.enabledApis.isEmpty ? '未限制' : group.enabledApis.join('、')}',
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
    */
  }

  Widget _buildSourcesSection(bool isDark, AdminConfig config) {
    return AdminSourceManagementPanel(
      isDark: isDark,
      sources: config.sourceConfig,
      onAction: ({
        required String action,
        String? key,
        String? name,
        String? api,
        String? detail,
        List<String>? keys,
        List<String>? order,
      }) {
        final AdminPanelController controller =
            context.read<AdminPanelController>();
        return controller.performSourceAction(
          action: action,
          key: key,
          name: name,
          api: api,
          detail: detail,
          keys: keys,
          order: order,
        );
      },
    );
    /*
    return _buildCollectionSection<AdminSourceConfig>(
      key: 'sources',
      title: '视频源',
      description: '已接入真实源数据，后续继续补齐增删改、排序和有效性检查。',
      isDark: isDark,
      items: config.sourceConfig,
      emptyText: '暂无视频源',
      itemBuilder: (BuildContext context, AdminSourceConfig source, int index) {
        return _buildInfoTile(
          isDark: isDark,
          leadingIcon: LucideIcons.video,
          title: source.name,
          subtitle: source.key,
          badges: <Widget>[
            _buildBadge(
                isDark: isDark,
                text: source.disabled ? '已禁用' : '启用中',
                color: source.disabled ? AppColors.error : AppColors.success),
            _buildBadge(
                isDark: isDark,
                text: source.isCustom ? '自定义' : '配置文件',
                color:
                    source.isCustom ? AppColors.secondary : AppColors.primary),
          ],
          lines: <String>[
            '接口：${source.api}',
            if (source.detail.isNotEmpty) '详情：${source.detail}',
          ],
        );
      },
    );
    */
  }

  Widget _buildLiveSection(bool isDark, AdminConfig config) {
    return AdminLiveSourceManagementPanel(
      isDark: isDark,
      liveSources: config.liveConfig,
      onAction: ({
        required String action,
        String? key,
        String? name,
        String? url,
        String? ua,
        String? epg,
        List<String>? order,
      }) {
        final AdminPanelController controller =
            context.read<AdminPanelController>();
        return controller.performLiveSourceAction(
          action: action,
          key: key,
          name: name,
          url: url,
          ua: ua,
          epg: epg,
          order: order,
        );
      },
      onRefreshAll: context.read<AdminPanelController>().refreshLiveSources,
    );
    /*
    return _buildCollectionSection<AdminLiveSourceConfig>(
      key: 'live',
      title: '直播源',
      description: '已接入直播源与频道数，后续补齐刷新、启停、编辑和排序。',
      isDark: isDark,
      items: config.liveConfig,
      emptyText: '暂无直播源',
      itemBuilder:
          (BuildContext context, AdminLiveSourceConfig source, int index) {
        return _buildInfoTile(
          isDark: isDark,
          leadingIcon: LucideIcons.radio,
          title: source.name,
          subtitle: source.key,
          badges: <Widget>[
            _buildBadge(
                isDark: isDark,
                text: source.disabled ? '已禁用' : '启用中',
                color: source.disabled ? AppColors.error : AppColors.success),
            _buildBadge(
                isDark: isDark,
                text: '${source.channelNumber} 频道',
                color: AppColors.secondary),
          ],
          lines: <String>[
            '地址：${source.url}',
            if (source.epg.isNotEmpty) 'EPG：${source.epg}',
            if (source.ua.isNotEmpty) 'UA：${source.ua}',
          ],
        );
      },
    );
    */
  }

  Widget _buildCategoriesSection(bool isDark, AdminConfig config) {
    return AdminCategoryManagementPanel(
      isDark: isDark,
      categories: config.customCategories,
      onAction: ({
        required String action,
        String? name,
        String? type,
        String? query,
        List<String>? order,
      }) {
        final AdminPanelController controller =
            context.read<AdminPanelController>();
        return controller.performCategoryAction(
          action: action,
          name: name,
          type: type,
          query: query,
          order: order,
        );
      },
    );
    /*
    return _buildCollectionSection<AdminCategoryConfig>(
      key: 'categories',
      title: '分类配置',
      description: '已接入自定义分类读取，后续补齐新增、启停和拖拽排序。',
      isDark: isDark,
      items: config.customCategories,
      emptyText: '暂无自定义分类',
      itemBuilder:
          (BuildContext context, AdminCategoryConfig category, int index) {
        return _buildInfoTile(
          isDark: isDark,
          leadingIcon: LucideIcons.folderTree,
          title: category.name.isEmpty ? '未命名分类' : category.name,
          subtitle: category.query,
          badges: <Widget>[
            _buildBadge(
                isDark: isDark,
                text: category.type == 'movie' ? '电影' : '剧集',
                color: AppColors.secondary),
            _buildBadge(
                isDark: isDark,
                text: category.disabled ? '已禁用' : '启用中',
                color: category.disabled ? AppColors.error : AppColors.success),
          ],
          lines: <String>[
            '来源：${category.from == 'custom' ? '自定义' : '配置文件'}',
          ],
        );
      },
    );
    */
  }

  Widget _buildOwnerToolsSectionV2(bool isDark, AdminConfig config) {
    final AdminPanelController controller =
        context.read<AdminPanelController>();
    return AdminOwnerToolsCard(
      key: const ValueKey<String>('owner_tools_v2'),
      isDark: isDark,
      configSubscription: config.configSubscription,
      configFile: config.configFile,
      isFetching: controller.isFetchingSubscriptionConfig,
      isSaving: controller.isSavingConfigFile,
      isResetting: controller.isResettingConfig,
      errorMessage: controller.errorMessage,
      isExportingMigrationData: controller.isExportingMigrationData,
      isImportingMigrationData: controller.isImportingMigrationData,
      onFetchSubscription: controller.fetchConfigSubscription,
      onSaveConfigFile: ({
        required String configFile,
        required String subscriptionUrl,
        required bool autoUpdate,
        required String lastCheckTime,
      }) {
        return controller.saveConfigFile(
          configFile: configFile,
          subscriptionUrl: subscriptionUrl,
          autoUpdate: autoUpdate,
          lastCheckTime: lastCheckTime,
        );
      },
      onResetConfig: controller.resetConfig,
      onExportMigrationData: controller.exportMigrationData,
      onImportMigrationData: controller.importMigrationData,
    );
  }

  // ignore: unused_element
  Widget _buildOwnerToolsSection(bool isDark, AdminConfig config) {
    final String preview = config.configFile.isEmpty
        ? '暂无配置文件内容'
        : config.configFile
            .substring(0, math.min(config.configFile.length, 900));
    return Column(
      key: const ValueKey<String>('owner_tools'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '站长工具',
          style: AppTypography.headlineLargeStyle(isDark: isDark),
        ),
        const SizedBox(height: 8),
        Text(
          '这里先承接配置订阅与配置文件快照，后续继续扩展重置配置和数据迁移。',
          style: AppTypography.bodyMediumStyle(isDark: isDark).copyWith(
            color: AppColors.textSecondary(isDark: isDark),
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          isDark: isDark,
          child: SelectableText(
            preview,
            style: AppTypography.mono(
              fontSize: 12,
              color: AppColors.textPrimary(isDark: isDark),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    bool isDark,
    String title,
    String value,
    String subtitle,
    IconData icon,
    Color color,
  ) {
    return GlassCard(
      isDark: isDark,
      width: 210,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 12),
          Text(title, style: AppTypography.labelLargeStyle(isDark: isDark)),
          const SizedBox(height: 4),
          Text(value, style: AppTypography.displaySmallStyle(isDark: isDark)),
          const SizedBox(height: 4),
          Text(subtitle, style: AppTypography.bodySmallStyle(isDark: isDark)),
        ],
      ),
    );
  }

  Widget _buildBadge({
    required bool isDark,
    required String text,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: AppTypography.labelSmallStyle(isDark: isDark).copyWith(
          color: color,
        ),
      ),
    );
  }

  Widget _buildKeyValueRow({
    required bool isDark,
    required String label,
    required String value,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: AppTypography.labelMediumStyle(isDark: isDark),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              value,
              style: AppTypography.bodyMediumStyle(isDark: isDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewMetric {
  const _OverviewMetric({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;
}

class _OverviewFact {
  const _OverviewFact({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;
}

enum _AdminPanelSection {
  overview,
  site,
  users,
  sources,
  live,
  categories,
  ownerTools,
}

class _SectionMeta {
  const _SectionMeta(this.section, this.title, this.icon);

  final _AdminPanelSection section;
  final String title;
  final IconData icon;
}
