import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:selene/components/animations/glass_card.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/models/admin_config.dart';
import 'package:selene/widgets/admin_panel_responsive.dart';

typedef AdminCategoryActionHandler = Future<bool> Function({
  required String action,
  String? name,
  String? type,
  String? query,
  List<String>? order,
});

class AdminCategoryManagementPanel extends StatefulWidget {
  const AdminCategoryManagementPanel({
    super.key,
    required this.isDark,
    required this.categories,
    required this.onAction,
  });

  final bool isDark;
  final List<AdminCategoryConfig> categories;
  final AdminCategoryActionHandler onAction;

  @override
  State<AdminCategoryManagementPanel> createState() =>
      _AdminCategoryManagementPanelState();
}

class _AdminCategoryManagementPanelState
    extends State<AdminCategoryManagementPanel> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _queryController = TextEditingController();
  final Set<String> _loadingKeys = <String>{};

  List<AdminCategoryConfig> _categories = <AdminCategoryConfig>[];
  bool _showAddForm = false;
  bool _orderDirty = false;
  String _selectedType = 'movie';

  @override
  void initState() {
    super.initState();
    _syncCategories();
  }

  @override
  void didUpdateWidget(covariant AdminCategoryManagementPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.categories != widget.categories) {
      _syncCategories();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _queryController.dispose();
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
              title: '分类配置',
              description: '支持新增、启停、删除和排序保存，保持与其他管理页一致的窄屏/宽屏体验。',
              actions: <Widget>[
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
                  label: Text(_showAddForm ? '取消' : '添加分类'),
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
                child: _categories.isEmpty
                    ? Center(
                        child: Text(
                          '暂无自定义分类',
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
                            maxCrossAxisExtent: 420,
                            mainAxisExtent: 280,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                          ),
                          itemCount: _categories.length,
                          addAutomaticKeepAlives: false,
                          itemBuilder: (BuildContext context, int index) {
                            final AdminCategoryConfig category =
                                _categories[index];
                            return _buildCategoryCard(category, index);
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
            decoration: const InputDecoration(hintText: '分类名称'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedType,
            items: const <DropdownMenuItem<String>>[
              DropdownMenuItem<String>(
                value: 'movie',
                child: Text('电影'),
              ),
              DropdownMenuItem<String>(
                value: 'tv',
                child: Text('剧集'),
              ),
            ],
            onChanged: (String? value) {
              setState(() {
                _selectedType = value ?? 'movie';
              });
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _queryController,
            decoration: const InputDecoration(hintText: '搜索关键字'),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _loadingKeys.contains('add_category')
                  ? null
                  : _handleAddCategory,
              child: Text(
                _loadingKeys.contains('add_category') ? '添加中...' : '确认添加',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryCard(AdminCategoryConfig category, int index) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            category.name.isEmpty ? '未命名分类' : category.name,
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
                category.type == 'movie' ? '电影' : '剧集',
                AppColors.secondary,
              ),
              _buildBadge(
                category.disabled ? '已禁用' : '启用中',
                category.disabled ? AppColors.error : AppColors.success,
              ),
              _buildBadge(
                category.from == 'custom' ? '自定义' : '配置文件',
                category.from == 'custom'
                    ? AppColors.primary
                    : AppColors.accent,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '查询：${category.query}',
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmallStyle(isDark: widget.isDark),
          ),
          const Spacer(),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton(
                onPressed:
                    index == 0 ? null : () => _moveCategory(index, index - 1),
                child: const Text('上移'),
              ),
              OutlinedButton(
                onPressed: index == _categories.length - 1
                    ? null
                    : () => _moveCategory(index, index + 1),
                child: const Text('下移'),
              ),
              OutlinedButton(
                onPressed: _loadingKeys.contains('toggle_${category.name}')
                    ? null
                    : () => _runAction(
                          loadingKey: 'toggle_${category.name}',
                          successMessage: category.disabled ? '已启用分类' : '已禁用分类',
                          action: () => widget.onAction(
                            action: category.disabled ? 'enable' : 'disable',
                            name: category.name,
                          ),
                        ),
                child: Text(
                  _loadingKeys.contains('toggle_${category.name}')
                      ? '处理中...'
                      : (category.disabled ? '启用' : '禁用'),
                ),
              ),
              if (category.from == 'custom')
                OutlinedButton(
                  onPressed: _loadingKeys.contains('delete_${category.name}')
                      ? null
                      : () => _handleDeleteCategory(category),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(
                      color: AppColors.error.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    _loadingKeys.contains('delete_${category.name}')
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

  Future<void> _handleAddCategory() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String name = _nameController.text.trim();
    final String query = _queryController.text.trim();

    if (name.isEmpty || query.isEmpty) {
      _showSnackBar(messenger, '分类名称和搜索关键字不能为空', false);
      return;
    }

    final bool success = await _runAction(
      loadingKey: 'add_category',
      successMessage: '分类已添加',
      action: () => widget.onAction(
        action: 'add',
        name: name,
        type: _selectedType,
        query: query,
      ),
    );

    if (!mounted || !success) {
      return;
    }

    _nameController.clear();
    _queryController.clear();
    setState(() {
      _selectedType = 'movie';
      _showAddForm = false;
    });
  }

  Future<void> _handleDeleteCategory(AdminCategoryConfig category) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认删除分类'),
          content: Text('确定要删除分类 ${category.name} 吗？此操作不可撤销。'),
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
      loadingKey: 'delete_${category.name}',
      successMessage: '分类已删除',
      action: () => widget.onAction(
        action: 'delete',
        name: category.name,
      ),
    );
  }

  Future<void> _handleSaveOrder() async {
    final bool success = await _runAction(
      loadingKey: 'save_order',
      successMessage: '分类排序已保存',
      action: () => widget.onAction(
        action: 'sort',
        order: _categories
            .map((AdminCategoryConfig item) => item.name)
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

  void _moveCategory(int oldIndex, int newIndex) {
    final List<AdminCategoryConfig> next =
        List<AdminCategoryConfig>.from(_categories);
    final AdminCategoryConfig item = next.removeAt(oldIndex);
    next.insert(newIndex, item);
    setState(() {
      _categories = next;
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

  void _syncCategories() {
    _categories = List<AdminCategoryConfig>.from(widget.categories);
    _orderDirty = false;
  }
}
