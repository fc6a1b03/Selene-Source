import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:selene/components/animations/glass_card.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/models/admin_config.dart';
import 'package:selene/widgets/admin_panel_responsive.dart';

typedef AdminLiveSourceActionHandler = Future<bool> Function({
  required String action,
  String? key,
  String? name,
  String? url,
  String? ua,
  String? epg,
  List<String>? order,
});

class AdminLiveSourceManagementPanel extends StatefulWidget {
  const AdminLiveSourceManagementPanel({
    super.key,
    required this.isDark,
    required this.liveSources,
    required this.onAction,
    required this.onRefreshAll,
  });

  final bool isDark;
  final List<AdminLiveSourceConfig> liveSources;
  final AdminLiveSourceActionHandler onAction;
  final Future<bool> Function() onRefreshAll;

  @override
  State<AdminLiveSourceManagementPanel> createState() =>
      _AdminLiveSourceManagementPanelState();
}

class _AdminLiveSourceManagementPanelState
    extends State<AdminLiveSourceManagementPanel> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _epgController = TextEditingController();
  final TextEditingController _uaController = TextEditingController();
  final Set<String> _loadingKeys = <String>{};

  List<AdminLiveSourceConfig> _liveSources = <AdminLiveSourceConfig>[];
  bool _showAddForm = false;
  bool _orderDirty = false;

  @override
  void initState() {
    super.initState();
    _syncLiveSources();
  }

  @override
  void didUpdateWidget(covariant AdminLiveSourceManagementPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.liveSources != widget.liveSources) {
      _syncLiveSources();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _keyController.dispose();
    _urlController.dispose();
    _epgController.dispose();
    _uaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AdminSectionHeader(
              isDark: widget.isDark,
              title: '直播源',
              description: '支持新增、编辑、启停、刷新频道和排序保存，桌面端自动扩列，移动端保持单列易读。',
              actions: <Widget>[
                FilledButton.icon(
                  onPressed: _loadingKeys.contains('refresh_all')
                      ? null
                      : _handleRefreshAll,
                  icon: const Icon(LucideIcons.refreshCcw, size: 16),
                  label: Text(
                    _loadingKeys.contains('refresh_all') ? '刷新中...' : '刷新频道',
                  ),
                ),
                FilledButton.tonal(
                  onPressed: !_orderDirty || _loadingKeys.contains('save_order')
                      ? null
                      : _handleSaveOrder,
                  child: Text(
                    _loadingKeys.contains('save_order') ? '保存中...' : '保存排序',
                  ),
                ),
                FilledButton.icon(
                  onPressed: () {
                    setState(() {
                      _showAddForm = !_showAddForm;
                    });
                  },
                  icon: Icon(
                    _showAddForm ? LucideIcons.x : LucideIcons.plus,
                    size: 16,
                  ),
                  label: Text(_showAddForm ? '取消' : '添加直播源'),
                ),
              ],
            ),
            if (_showAddForm) ...<Widget>[
              const SizedBox(height: 16),
              _buildAddForm(),
            ],
            const SizedBox(height: 16),
            Expanded(
              child: GlassCard(
                isDark: widget.isDark,
                padding: const EdgeInsets.all(12),
                child: _liveSources.isEmpty
                    ? Center(
                        child: Text(
                          '暂无直播源',
                          style: AppTypography.bodyMediumStyle(
                            isDark: widget.isDark,
                          ),
                        ),
                      )
                    : Scrollbar(
                        child: GridView.builder(
                          padding: EdgeInsets.zero,
                          cacheExtent: constraints.maxHeight * 1.5,
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 500,
                            mainAxisExtent: 340,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                          ),
                          itemCount: _liveSources.length,
                          addAutomaticKeepAlives: false,
                          itemBuilder: (BuildContext context, int index) {
                            final AdminLiveSourceConfig source =
                                _liveSources[index];
                            return _buildLiveSourceCard(source, index);
                          },
                        ),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAddForm() {
    return GlassCard(
      isDark: widget.isDark,
      child: Column(
        children: <Widget>[
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(hintText: '直播源名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _keyController,
            decoration: const InputDecoration(hintText: '直播源 Key'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _urlController,
            decoration: const InputDecoration(hintText: 'M3U 地址'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _epgController,
            decoration: const InputDecoration(hintText: 'EPG 地址（可选）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _uaController,
            decoration: const InputDecoration(hintText: 'UA（可选）'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _loadingKeys.contains('add_live')
                  ? null
                  : _handleAddLiveSource,
              child: Text(
                _loadingKeys.contains('add_live') ? '添加中...' : '确认添加',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLiveSourceCard(AdminLiveSourceConfig source, int index) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            source.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.labelLargeStyle(isDark: widget.isDark),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _buildBadge(
                source.disabled ? '已禁用' : '启用中',
                source.disabled ? AppColors.error : AppColors.success,
              ),
              _buildBadge('${source.channelNumber} 个频道', AppColors.secondary),
              _buildBadge(
                source.isCustom ? '自定义' : '配置文件',
                source.isCustom ? AppColors.secondary : AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildSelectableLine('Key', source.key),
          const SizedBox(height: 6),
          _buildSelectableLine('地址', source.url, maxLines: 2),
          if (source.epg.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            _buildSelectableLine('EPG', source.epg, maxLines: 2),
          ],
          if (source.ua.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'UA：${source.ua}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmallStyle(isDark: widget.isDark),
            ),
          ],
          const Spacer(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton(
                onPressed:
                    index == 0 ? null : () => _moveItem(index, index - 1),
                child: const Text('上移'),
              ),
              OutlinedButton(
                onPressed: index == _liveSources.length - 1
                    ? null
                    : () => _moveItem(index, index + 1),
                child: const Text('下移'),
              ),
              if (source.isCustom)
                OutlinedButton(
                  onPressed: _loadingKeys.contains('edit_${source.key}')
                      ? null
                      : () => _handleEditLiveSource(source),
                  child: Text(
                    _loadingKeys.contains('edit_${source.key}')
                        ? '处理中...'
                        : '编辑',
                  ),
                ),
              OutlinedButton(
                onPressed: _loadingKeys.contains('toggle_${source.key}')
                    ? null
                    : () => _runAction(
                          loadingKey: 'toggle_${source.key}',
                          successMessage: source.disabled ? '已启用直播源' : '已禁用直播源',
                          action: () => widget.onAction(
                            action: source.disabled ? 'enable' : 'disable',
                            key: source.key,
                          ),
                        ),
                child: Text(
                  _loadingKeys.contains('toggle_${source.key}')
                      ? '处理中...'
                      : (source.disabled ? '启用' : '禁用'),
                ),
              ),
              if (source.isCustom)
                OutlinedButton(
                  onPressed: _loadingKeys.contains('delete_${source.key}')
                      ? null
                      : () => _handleDeleteLiveSource(source),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(
                      color: AppColors.error.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    _loadingKeys.contains('delete_${source.key}')
                        ? '删除中...'
                        : '删除',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSelectableLine(
    String label,
    String value, {
    int maxLines = 1,
  }) {
    return SelectableText(
      '$label：$value',
      maxLines: maxLines,
      style: AppTypography.bodySmallStyle(isDark: widget.isDark),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: widget.isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: AppTypography.labelSmallStyle(isDark: widget.isDark).copyWith(
          color: color,
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: widget.isDark
          ? AppColors.darkElevated.withValues(alpha: 0.55)
          : AppColors.lightElevated.withValues(alpha: 0.92),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: AppColors.border(isDark: widget.isDark).withValues(alpha: 0.32),
      ),
    );
  }

  Future<void> _handleAddLiveSource() async {
    final String name = _nameController.text.trim();
    final String key = _keyController.text.trim();
    final String url = _urlController.text.trim();
    final String epg = _epgController.text.trim();
    final String ua = _uaController.text.trim();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

    if (name.isEmpty || key.isEmpty || url.isEmpty) {
      _showSnackBar(messenger, '名称、Key 和地址不能为空', false);
      return;
    }

    final bool success = await _runAction(
      loadingKey: 'add_live',
      successMessage: '直播源已添加',
      action: () => widget.onAction(
        action: 'add',
        key: key,
        name: name,
        url: url,
        epg: epg,
        ua: ua,
      ),
    );

    if (!mounted || !success) {
      return;
    }

    _nameController.clear();
    _keyController.clear();
    _urlController.clear();
    _epgController.clear();
    _uaController.clear();
    setState(() {
      _showAddForm = false;
    });
  }

  Future<void> _handleEditLiveSource(AdminLiveSourceConfig source) async {
    final TextEditingController nameController =
        TextEditingController(text: source.name);
    final TextEditingController urlController =
        TextEditingController(text: source.url);
    final TextEditingController epgController =
        TextEditingController(text: source.epg);
    final TextEditingController uaController =
        TextEditingController(text: source.ua);

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('编辑直播源 · ${source.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(hintText: '直播源名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlController,
                  decoration: const InputDecoration(hintText: 'M3U 地址'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: epgController,
                  decoration: const InputDecoration(hintText: 'EPG 地址'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: uaController,
                  decoration: const InputDecoration(hintText: 'UA'),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    final String name = nameController.text.trim();
    final String url = urlController.text.trim();
    final String epg = epgController.text.trim();
    final String ua = uaController.text.trim();
    nameController.dispose();
    urlController.dispose();
    epgController.dispose();
    uaController.dispose();

    if (confirmed != true || name.isEmpty || url.isEmpty) {
      return;
    }

    await _runAction(
      loadingKey: 'edit_${source.key}',
      successMessage: '直播源已更新',
      action: () => widget.onAction(
        action: 'edit',
        key: source.key,
        name: name,
        url: url,
        epg: epg,
        ua: ua,
      ),
    );
  }

  Future<void> _handleDeleteLiveSource(AdminLiveSourceConfig source) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认删除直播源'),
          content: Text('确定要删除直播源 ${source.name} 吗？此操作不可撤销。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await _runAction(
      loadingKey: 'delete_${source.key}',
      successMessage: '直播源已删除',
      action: () => widget.onAction(action: 'delete', key: source.key),
    );
  }

  Future<void> _handleRefreshAll() async {
    await _runAction(
      loadingKey: 'refresh_all',
      successMessage: '直播源已刷新',
      action: widget.onRefreshAll,
    );
  }

  Future<void> _handleSaveOrder() async {
    final bool success = await _runAction(
      loadingKey: 'save_order',
      successMessage: '直播源排序已保存',
      action: () => widget.onAction(
        action: 'sort',
        order: _liveSources
            .map((AdminLiveSourceConfig item) => item.key)
            .toList(growable: false),
      ),
    );

    if (!mounted || !success) {
      return;
    }

    setState(() {
      _orderDirty = false;
    });
  }

  Future<bool> _runAction({
    required String loadingKey,
    required String successMessage,
    required Future<bool> Function() action,
  }) async {
    if (_loadingKeys.contains(loadingKey)) {
      return false;
    }

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    setState(() {
      _loadingKeys.add(loadingKey);
    });

    final bool success = await action();

    if (!mounted) {
      return false;
    }

    setState(() {
      _loadingKeys.remove(loadingKey);
    });

    _showSnackBar(
      messenger,
      success ? successMessage : '操作失败，请稍后重试',
      success,
    );
    return success;
  }

  void _moveItem(int oldIndex, int newIndex) {
    final List<AdminLiveSourceConfig> next =
        List<AdminLiveSourceConfig>.from(_liveSources);
    final AdminLiveSourceConfig item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    setState(() {
      _liveSources = next;
      _orderDirty = true;
    });
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

  void _syncLiveSources() {
    _liveSources = List<AdminLiveSourceConfig>.from(widget.liveSources);
    _orderDirty = false;
  }
}
