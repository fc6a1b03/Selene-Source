import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:selene/components/animations/glass_card.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/models/admin_config.dart';

class AdminSiteSettingsCard extends StatefulWidget {
  const AdminSiteSettingsCard({
    super.key,
    required this.isDark,
    required this.siteConfig,
    required this.isSaving,
    required this.onSave,
  });

  final bool isDark;
  final AdminSiteConfig siteConfig;
  final bool isSaving;
  final Future<bool> Function(AdminSiteConfig siteConfig) onSave;

  @override
  State<AdminSiteSettingsCard> createState() => _AdminSiteSettingsCardState();
}

class _AdminSiteSettingsCardState extends State<AdminSiteSettingsCard> {
  static const List<_OptionItem> _doubanDataOptions = <_OptionItem>[
    _OptionItem('direct', '直连'),
    _OptionItem('cors-proxy-zwei', 'Cors Proxy By Zwei'),
    _OptionItem('cmliussss-cdn-tencent', '豆瓣 CDN By CMLiussss（腾讯云）'),
    _OptionItem('cmliussss-cdn-ali', '豆瓣 CDN By CMLiussss（阿里云）'),
    _OptionItem('custom', '自定义代理'),
  ];

  static const List<_OptionItem> _doubanImageOptions = <_OptionItem>[
    _OptionItem('direct', '直连'),
    _OptionItem('server', '服务器代理'),
    _OptionItem('img3', '豆瓣官方精品 CDN'),
    _OptionItem('cmliussss-cdn-tencent', '豆瓣 CDN By CMLiussss（腾讯云）'),
    _OptionItem('cmliussss-cdn-ali', '豆瓣 CDN By CMLiussss（阿里云）'),
    _OptionItem('custom', '自定义代理'),
  ];

  late final TextEditingController _siteNameController;
  late final TextEditingController _announcementController;
  late final TextEditingController _searchMaxPageController;
  late final TextEditingController _cacheTimeController;
  late final TextEditingController _doubanProxyController;
  late final TextEditingController _doubanImageProxyController;

  late String _doubanProxyType;
  late String _doubanImageProxyType;
  late bool _disableYellowFilter;
  late bool _fluidSearch;

  @override
  void initState() {
    super.initState();
    _siteNameController = TextEditingController();
    _announcementController = TextEditingController();
    _searchMaxPageController = TextEditingController();
    _cacheTimeController = TextEditingController();
    _doubanProxyController = TextEditingController();
    _doubanImageProxyController = TextEditingController();
    _syncFromConfig();
  }

  @override
  void didUpdateWidget(covariant AdminSiteSettingsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.siteConfig != widget.siteConfig) {
      _syncFromConfig();
    }
  }

  @override
  void dispose() {
    _siteNameController.dispose();
    _announcementController.dispose();
    _searchMaxPageController.dispose();
    _cacheTimeController.dispose();
    _doubanProxyController.dispose();
    _doubanImageProxyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '站点设置',
          style: AppTypography.headlineLargeStyle(isDark: widget.isDark),
        ),
        const SizedBox(height: 8),
        Text(
          '这一部分已经接入真实保存接口，对应 LunaTV 的 `/api/admin/site`。',
          style: AppTypography.bodyMediumStyle(isDark: widget.isDark).copyWith(
            color: AppColors.textSecondary(isDark: widget.isDark),
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          isDark: widget.isDark,
          child: Column(
            children: <Widget>[
              _FieldBlock(
                label: '站点名称',
                child: TextField(
                  controller: _siteNameController,
                  decoration: const InputDecoration(hintText: '输入站点名称'),
                ),
              ),
              _FieldBlock(
                label: '公告',
                child: TextField(
                  controller: _announcementController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(hintText: '输入公告内容'),
                ),
              ),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _FieldBlock(
                      label: '搜索最大页数',
                      child: TextField(
                        controller: _searchMaxPageController,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(hintText: '例如 1'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FieldBlock(
                      label: '接口缓存秒数',
                      child: TextField(
                        controller: _cacheTimeController,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: const InputDecoration(hintText: '例如 7200'),
                      ),
                    ),
                  ),
                ],
              ),
              _FieldBlock(
                label: '豆瓣数据源',
                child: DropdownButtonFormField<String>(
                  initialValue: _doubanProxyType,
                  items: _doubanDataOptions
                      .map(
                        (_OptionItem item) => DropdownMenuItem<String>(
                          value: item.value,
                          child: Text(item.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (String? value) {
                    if (value == null) return;
                    setState(() {
                      _doubanProxyType = value;
                    });
                  },
                ),
              ),
              _FieldBlock(
                label: '豆瓣图片源',
                child: DropdownButtonFormField<String>(
                  initialValue: _doubanImageProxyType,
                  items: _doubanImageOptions
                      .map(
                        (_OptionItem item) => DropdownMenuItem<String>(
                          value: item.value,
                          child: Text(item.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (String? value) {
                    if (value == null) return;
                    setState(() {
                      _doubanImageProxyType = value;
                    });
                  },
                ),
              ),
              _FieldBlock(
                label: '豆瓣数据代理地址',
                child: TextField(
                  controller: _doubanProxyController,
                  decoration: const InputDecoration(hintText: '可留空'),
                ),
              ),
              _FieldBlock(
                label: '豆瓣图片代理地址',
                child: TextField(
                  controller: _doubanImageProxyController,
                  decoration: const InputDecoration(hintText: '可留空'),
                ),
              ),
              SwitchListTile.adaptive(
                value: _disableYellowFilter,
                onChanged: (bool value) {
                  setState(() {
                    _disableYellowFilter = value;
                  });
                },
                title: const Text('关闭黄源过滤'),
                subtitle: const Text('按后端固定站点策略保存'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile.adaptive(
                value: _fluidSearch,
                onChanged: (bool value) {
                  setState(() {
                    _fluidSearch = value;
                  });
                },
                title: const Text('启用流式搜索'),
                subtitle: const Text('控制后台全局流式搜索策略'),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed:
                      widget.isSaving ? null : () => _handleSave(context),
                  child: Text(widget.isSaving ? '保存中...' : '保存设置'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleSave(BuildContext context) async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final int? searchMaxPage =
        int.tryParse(_searchMaxPageController.text.trim());
    final int? cacheTime = int.tryParse(_cacheTimeController.text.trim());

    if (searchMaxPage == null || searchMaxPage <= 0) {
      _showSnackBar(messenger, '搜索最大页数必须是大于 0 的整数', false);
      return;
    }
    if (cacheTime == null || cacheTime < 0) {
      _showSnackBar(messenger, '接口缓存秒数必须是 0 或更大的整数', false);
      return;
    }

    final bool success = await widget.onSave(
      widget.siteConfig.copyWith(
        siteName: _siteNameController.text.trim(),
        announcement: _announcementController.text.trim(),
        searchDownstreamMaxPage: searchMaxPage,
        siteInterfaceCacheTime: cacheTime,
        doubanProxyType: _doubanProxyType,
        doubanProxy: _doubanProxyController.text.trim(),
        doubanImageProxyType: _doubanImageProxyType,
        doubanImageProxy: _doubanImageProxyController.text.trim(),
        disableYellowFilter: _disableYellowFilter,
        fluidSearch: _fluidSearch,
      ),
    );
    if (!mounted) return;
    _showSnackBar(
      messenger,
      success ? '站点设置已保存' : '站点设置保存失败',
      success,
    );
  }

  void _showSnackBar(
    ScaffoldMessengerState messenger,
    String message,
    bool success,
  ) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: success ? AppColors.success : AppColors.error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _syncFromConfig() {
    _siteNameController.text = widget.siteConfig.siteName;
    _announcementController.text = widget.siteConfig.announcement;
    _searchMaxPageController.text =
        widget.siteConfig.searchDownstreamMaxPage.toString();
    _cacheTimeController.text =
        widget.siteConfig.siteInterfaceCacheTime.toString();
    _doubanProxyController.text = widget.siteConfig.doubanProxy;
    _doubanImageProxyController.text = widget.siteConfig.doubanImageProxy;
    _doubanProxyType =
        _normalize(widget.siteConfig.doubanProxyType, _doubanDataOptions);
    _doubanImageProxyType =
        _normalize(widget.siteConfig.doubanImageProxyType, _doubanImageOptions);
    _disableYellowFilter = widget.siteConfig.disableYellowFilter;
    _fluidSearch = widget.siteConfig.fluidSearch;
  }

  String _normalize(String value, List<_OptionItem> options) {
    return options.any((_OptionItem item) => item.value == value)
        ? value
        : 'custom';
  }
}

class _FieldBlock extends StatelessWidget {
  const _FieldBlock({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _OptionItem {
  const _OptionItem(this.value, this.label);

  final String value;
  final String label;
}
