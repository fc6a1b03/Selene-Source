import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:selene/components/animations/glass_card.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/models/admin_config.dart';
import 'package:selene/models/admin_source_validation.dart';
import 'package:selene/services/admin_source_validation_service.dart';

typedef AdminSourceActionHandler = Future<bool> Function({
  required String action,
  String? key,
  String? name,
  String? api,
  String? detail,
  List<String>? keys,
  List<String>? order,
});

class AdminSourceManagementCard extends StatefulWidget {
  const AdminSourceManagementCard({
    super.key,
    required this.isDark,
    required this.sources,
    required this.onAction,
  });

  final bool isDark;
  final List<AdminSourceConfig> sources;
  final AdminSourceActionHandler onAction;

  @override
  State<AdminSourceManagementCard> createState() =>
      _AdminSourceManagementCardState();
}

class _AdminSourceManagementCardState extends State<AdminSourceManagementCard> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _apiController = TextEditingController();
  final TextEditingController _detailController = TextEditingController();
  final AdminSourceValidationService _validationService =
      AdminSourceValidationService();
  final Set<String> _loadingKeys = <String>{};
  final Set<String> _selectedSourceKeys = <String>{};

  StreamSubscription<AdminSourceValidationEvent>? _validationSubscription;
  List<AdminSourceConfig> _sources = <AdminSourceConfig>[];
  Map<String, AdminSourceValidationItem> _validationResults =
      <String, AdminSourceValidationItem>{};
  bool _showAddForm = false;
  bool _orderDirty = false;
  bool _isValidating = false;
  String _validationKeyword = '';
  int _completedSources = 0;
  int _totalSources = 0;

  @override
  void initState() {
    super.initState();
    _syncSources();
  }

  @override
  void didUpdateWidget(covariant AdminSourceManagementCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sources != widget.sources) {
      _syncSources();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _keyController.dispose();
    _apiController.dispose();
    _detailController.dispose();
    _validationSubscription?.cancel();
    _validationService.stopValidation();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '视频源',
                    style: AppTypography.headlineLargeStyle(
                      isDark: widget.isDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '已接入添加、启用/禁用、删除、有效性检查和排序保存。',
                    style: AppTypography.bodyMediumStyle(
                      isDark: widget.isDark,
                    ).copyWith(
                      color: AppColors.textSecondary(isDark: widget.isDark),
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: _isValidating ? null : _handleStartValidation,
              icon: Icon(
                _isValidating
                    ? LucideIcons.loaderCircle
                    : LucideIcons.badgeCheck,
                size: 16,
              ),
              label: Text(_isValidating ? '校验中...' : '有效性检查'),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: !_orderDirty || _loadingKeys.contains('save_order')
                  ? null
                  : _handleSaveOrder,
              child: Text(
                _loadingKeys.contains('save_order') ? '保存中...' : '保存排序',
              ),
            ),
            if (_selectedSourceKeys.isNotEmpty) ...<Widget>[
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _loadingKeys.contains('batch_enable')
                    ? null
                    : () => _handleBatchAction('batch_enable'),
                child: Text(
                  _loadingKeys.contains('batch_enable') ? '处理中...' : '批量启用',
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _loadingKeys.contains('batch_disable')
                    ? null
                    : () => _handleBatchAction('batch_disable'),
                child: Text(
                  _loadingKeys.contains('batch_disable') ? '处理中...' : '批量禁用',
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _loadingKeys.contains('batch_delete')
                    ? null
                    : () => _handleBatchDelete(),
                child: Text(
                  _loadingKeys.contains('batch_delete') ? '处理中...' : '批量删除',
                ),
              ),
            ],
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _handleToggleSelectAllSources,
              child: Text(
                _selectedSourceKeys.length == _sources.length &&
                        _sources.isNotEmpty
                    ? '清空选择'
                    : '全选',
              ),
            ),
            const SizedBox(width: 8),
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
              label: Text(_showAddForm ? '取消' : '添加源'),
            ),
          ],
        ),
        if (_showAddForm) ...<Widget>[
          const SizedBox(height: 16),
          GlassCard(
            isDark: widget.isDark,
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(hintText: '源名称'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _keyController,
                  decoration: const InputDecoration(hintText: '源 Key'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiController,
                  decoration: const InputDecoration(hintText: 'API 地址'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _detailController,
                  decoration: const InputDecoration(hintText: '详情（可选）'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _loadingKeys.contains('add_source')
                        ? null
                        : _handleAddSource,
                    child: Text(
                      _loadingKeys.contains('add_source') ? '添加中...' : '确认添加',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (_validationResults.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          _buildValidationCard(),
        ],
        const SizedBox(height: 16),
        GlassCard(
          isDark: widget.isDark,
          child: _sources.isEmpty
              ? Text(
                  '暂无视频源',
                  style: AppTypography.bodyMediumStyle(isDark: widget.isDark),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _sources.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (BuildContext context, int index) {
                    final AdminSourceConfig source = _sources[index];
                    return _buildSourceCard(source, index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildValidationCard() {
    final List<AdminSourceValidationItem> items = _validationResults.values
        .toList(growable: false)
      ..sort((a, b) => a.name.compareTo(b.name));
    final List<String> validKeys = items
        .where((item) => item.status == AdminSourceValidationStatus.valid)
        .map((item) => item.key)
        .toList(growable: false);
    final List<String> invalidKeys = items
        .where(
          (item) =>
              item.status == AdminSourceValidationStatus.invalid ||
              item.status == AdminSourceValidationStatus.noResults,
        )
        .map((item) => item.key)
        .toList(growable: false);

    return GlassCard(
      isDark: widget.isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '校验结果',
                      style: AppTypography.headlineSmallStyle(
                        isDark: widget.isDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _validationKeyword.isEmpty
                          ? '暂无关键字'
                          : '关键字：$_validationKeyword · $_completedSources / $_totalSources',
                      style: AppTypography.bodySmallStyle(
                        isDark: widget.isDark,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: _loadingKeys.contains('apply_validation') ||
                        (validKeys.isEmpty && invalidKeys.isEmpty)
                    ? null
                    : () =>
                        _handleApplyValidationResult(validKeys, invalidKeys),
                child: Text(
                  _loadingKeys.contains('apply_validation')
                      ? '应用中...'
                      : '自动应用结果',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...items.map((item) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      item.name,
                      style: AppTypography.bodyMediumStyle(
                        isDark: widget.isDark,
                      ),
                    ),
                  ),
                  _buildBadge(
                    _statusText(item.status),
                    _statusColor(item.status),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSourceCard(AdminSourceConfig source, int index) {
    final AdminSourceValidationStatus? validationStatus =
        _validationResults[source.key]?.status;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: widget.isDark
            ? AppColors.darkElevated.withValues(alpha: 0.55)
            : AppColors.lightElevated.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color:
              AppColors.border(isDark: widget.isDark).withValues(alpha: 0.32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Checkbox(
                value: _selectedSourceKeys.contains(source.key),
                onChanged: (bool? value) {
                  setState(() {
                    if (value == true) {
                      _selectedSourceKeys.add(source.key);
                    } else {
                      _selectedSourceKeys.remove(source.key);
                    }
                  });
                },
              ),
              Text(
                source.name,
                style: AppTypography.labelLargeStyle(isDark: widget.isDark),
              ),
              _buildBadge(
                source.disabled ? '已禁用' : '启用中',
                source.disabled ? AppColors.error : AppColors.success,
              ),
              _buildBadge(
                source.isCustom ? '自定义' : '配置文件',
                source.isCustom ? AppColors.secondary : AppColors.primary,
              ),
              if (validationStatus != null)
                _buildBadge(
                  _statusText(validationStatus),
                  _statusColor(validationStatus),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            'Key：${source.key}',
            style: AppTypography.bodySmallStyle(isDark: widget.isDark),
          ),
          const SizedBox(height: 4),
          SelectableText(
            '接口：${source.api}',
            style: AppTypography.bodySmallStyle(isDark: widget.isDark),
          ),
          if (source.detail.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              '详情：${source.detail}',
              style: AppTypography.bodySmallStyle(isDark: widget.isDark),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton(
                onPressed:
                    index == 0 ? null : () => _moveSource(index, index - 1),
                child: const Text('上移'),
              ),
              OutlinedButton(
                onPressed: index == _sources.length - 1
                    ? null
                    : () => _moveSource(index, index + 1),
                child: const Text('下移'),
              ),
              OutlinedButton(
                onPressed: _loadingKeys.contains('toggle_${source.key}')
                    ? null
                    : () => _runAction(
                          loadingKey: 'toggle_${source.key}',
                          successMessage: source.disabled ? '已启用视频源' : '已禁用视频源',
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
                      : () => _handleDeleteSource(source),
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

  Future<void> _handleAddSource() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String name = _nameController.text.trim();
    final String key = _keyController.text.trim();
    final String api = _apiController.text.trim();
    final String detail = _detailController.text.trim();

    if (name.isEmpty || key.isEmpty || api.isEmpty) {
      _showSnackBar(messenger, '源名称、Key 和 API 地址不能为空', false);
      return;
    }

    final bool success = await _runAction(
      loadingKey: 'add_source',
      successMessage: '视频源已添加',
      action: () => widget.onAction(
        action: 'add',
        key: key,
        name: name,
        api: api,
        detail: detail,
      ),
    );

    if (!mounted || !success) {
      return;
    }

    _nameController.clear();
    _keyController.clear();
    _apiController.clear();
    _detailController.clear();
    setState(() {
      _showAddForm = false;
    });
  }

  Future<void> _handleDeleteSource(AdminSourceConfig source) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认删除视频源'),
          content: Text('确定要删除视频源 ${source.name} 吗？此操作不可撤销。'),
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
      successMessage: '视频源已删除',
      action: () => widget.onAction(
        action: 'delete',
        key: source.key,
      ),
    );
  }

  Future<void> _handleStartValidation() async {
    final TextEditingController controller = TextEditingController(
      text: _validationKeyword.isEmpty ? '斗罗' : _validationKeyword,
    );
    final String? keyword = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('视频源有效性检查'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '输入搜索关键字'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('开始'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (keyword == null || keyword.isEmpty) {
      return;
    }

    await _validationSubscription?.cancel();
    setState(() {
      _validationKeyword = keyword;
      _isValidating = true;
      _completedSources = 0;
      _totalSources = _sources.length;
      _validationResults = <String, AdminSourceValidationItem>{
        for (final AdminSourceConfig source in _sources)
          source.key: AdminSourceValidationItem(
            key: source.key,
            name: source.name,
            status: AdminSourceValidationStatus.validating,
          ),
      };
    });

    _validationSubscription =
        _validationService.eventStream.listen(_handleValidationEvent);

    try {
      await _validationService.startValidation(keyword);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isValidating = false;
      });
      _showSnackBar(
        ScaffoldMessenger.of(context),
        '校验启动失败: ${error.toString()}',
        false,
      );
    }
  }

  Future<void> _handleApplyValidationResult(
    List<String> validKeys,
    List<String> invalidKeys,
  ) async {
    final bool success = await _runAction(
      loadingKey: 'apply_validation',
      successMessage: '已按校验结果更新视频源状态',
      action: () async {
        bool result = true;
        if (validKeys.isNotEmpty) {
          result = result &&
              await widget.onAction(
                action: 'batch_enable',
                keys: validKeys,
              );
        }
        if (invalidKeys.isNotEmpty) {
          result = result &&
              await widget.onAction(
                action: 'batch_disable',
                keys: invalidKeys,
              );
        }
        return result;
      },
    );

    if (!mounted || !success) {
      return;
    }
  }

  Future<void> _handleSaveOrder() async {
    final bool success = await _runAction(
      loadingKey: 'save_order',
      successMessage: '视频源排序已保存',
      action: () => widget.onAction(
        action: 'sort',
        order: _sources.map((source) => source.key).toList(growable: false),
      ),
    );

    if (!mounted || !success) {
      return;
    }

    setState(() {
      _orderDirty = false;
    });
  }

  Future<void> _handleBatchAction(String action) async {
    final bool success = await _runAction(
      loadingKey: action,
      successMessage: '批量操作已完成',
      action: () => widget.onAction(
        action: action,
        keys: _selectedSourceKeys.toList(growable: false),
      ),
    );

    if (!mounted || !success) {
      return;
    }

    setState(() {
      _selectedSourceKeys.clear();
    });
  }

  Future<void> _handleBatchDelete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认批量删除视频源'),
          content: Text('确定要删除已选择的 ${_selectedSourceKeys.length} 个视频源吗？'),
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

    await _handleBatchAction('batch_delete');
  }

  void _handleValidationEvent(AdminSourceValidationEvent event) {
    if (!mounted) {
      return;
    }

    setState(() {
      switch (event.type) {
        case AdminSourceValidationEventType.start:
          _totalSources = event.totalSources ?? _totalSources;
        case AdminSourceValidationEventType.sourceResult:
        case AdminSourceValidationEventType.sourceError:
          final String key = event.sourceKey ?? '';
          final String name = _findSourceName(key);
          if (key.isNotEmpty && event.status != null) {
            _validationResults[key] = AdminSourceValidationItem(
              key: key,
              name: name,
              status: event.status!,
            );
            _completedSources = _validationResults.values
                .where(
                  (item) =>
                      item.status != AdminSourceValidationStatus.validating,
                )
                .length;
          }
        case AdminSourceValidationEventType.complete:
          _isValidating = false;
      }
    });
  }

  String _findSourceName(String key) {
    for (final AdminSourceConfig source in _sources) {
      if (source.key == key) {
        return source.name;
      }
    }
    return key;
  }

  String _statusText(AdminSourceValidationStatus status) {
    switch (status) {
      case AdminSourceValidationStatus.validating:
        return '校验中';
      case AdminSourceValidationStatus.valid:
        return '有效';
      case AdminSourceValidationStatus.noResults:
        return '无结果';
      case AdminSourceValidationStatus.invalid:
        return '无效';
    }
  }

  Color _statusColor(AdminSourceValidationStatus status) {
    switch (status) {
      case AdminSourceValidationStatus.validating:
        return AppColors.secondary;
      case AdminSourceValidationStatus.valid:
        return AppColors.success;
      case AdminSourceValidationStatus.noResults:
        return AppColors.warning;
      case AdminSourceValidationStatus.invalid:
        return AppColors.error;
    }
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

  void _moveSource(int oldIndex, int newIndex) {
    final List<AdminSourceConfig> next = List<AdminSourceConfig>.from(_sources);
    final AdminSourceConfig item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    setState(() {
      _sources = next;
      _orderDirty = true;
    });
  }

  void _handleToggleSelectAllSources() {
    setState(() {
      if (_selectedSourceKeys.length == _sources.length &&
          _sources.isNotEmpty) {
        _selectedSourceKeys.clear();
      } else {
        _selectedSourceKeys
          ..clear()
          ..addAll(_sources.map((source) => source.key));
      }
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

  void _syncSources() {
    _sources = List<AdminSourceConfig>.from(widget.sources);
    _orderDirty = false;
    final Set<String> currentKeys =
        _sources.map((source) => source.key).toSet();
    _selectedSourceKeys.removeWhere((key) => !currentKeys.contains(key));
  }
}
