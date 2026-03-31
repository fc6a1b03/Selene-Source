import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:selene/components/animations/glass_card.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/models/admin_config.dart';
import 'package:selene/services/user_data_service.dart';

typedef AdminUserActionHandler = Future<bool> Function({
  required String action,
  String? targetUsername,
  String? targetPassword,
  String? userGroup,
  List<String>? enabledApis,
  List<String>? userGroups,
  String? groupAction,
  String? groupName,
  List<String>? usernames,
});

class AdminUserManagementCard extends StatefulWidget {
  const AdminUserManagementCard({
    super.key,
    required this.isDark,
    required this.userConfig,
    required this.sources,
    required this.isOwner,
    required this.onAction,
  });

  final bool isDark;
  final AdminUserConfig userConfig;
  final List<AdminSourceConfig> sources;
  final bool isOwner;
  final AdminUserActionHandler onAction;

  @override
  State<AdminUserManagementCard> createState() =>
      _AdminUserManagementCardState();
}

class _AdminUserManagementCardState extends State<AdminUserManagementCard> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final Set<String> _loadingKeys = <String>{};
  final Set<String> _selectedUsernames = <String>{};

  bool _showAddUserForm = false;
  String _selectedUserGroup = '';
  String? _currentUsername;

  @override
  void initState() {
    super.initState();
    _loadCurrentUsername();
  }

  @override
  void didUpdateWidget(covariant AdminUserManagementCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final Set<String> existing =
        widget.userConfig.users.map((user) => user.username).toSet();
    _selectedUsernames.removeWhere((name) => !existing.contains(name));
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
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
                    '用户配置',
                    style: AppTypography.headlineLargeStyle(
                      isDark: widget.isDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '已接入用户、用户组、来源权限与批量设置用户组。',
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
              onPressed: _handleCreateGroup,
              icon: const Icon(LucideIcons.shieldPlus, size: 16),
              label: const Text('新增用户组'),
            ),
            if (_selectedUsernames.isNotEmpty) ...<Widget>[
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _loadingKeys.contains('batch_groups')
                    ? null
                    : _handleBatchConfigureUserGroups,
                child: Text(
                  _loadingKeys.contains('batch_groups')
                      ? '处理中...'
                      : '批量设置用户组(${_selectedUsernames.length})',
                ),
              ),
            ],
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: _handleToggleSelectAllUsers,
              child: Text(
                _areAllAllowedUsersSelected ? '清空选择' : '全选可操作用户',
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: () {
                setState(() {
                  _showAddUserForm = !_showAddUserForm;
                });
              },
              icon: Icon(
                _showAddUserForm ? LucideIcons.x : LucideIcons.userPlus,
                size: 16,
              ),
              label: Text(_showAddUserForm ? '取消' : '添加用户'),
            ),
          ],
        ),
        if (_showAddUserForm) ...<Widget>[
          const SizedBox(height: 16),
          GlassCard(
            isDark: widget.isDark,
            child: Column(
              children: <Widget>[
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(hintText: '用户名'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(hintText: '密码'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedUserGroup,
                  items: <DropdownMenuItem<String>>[
                    const DropdownMenuItem<String>(
                      value: '',
                      child: Text('不设置用户组'),
                    ),
                    ...widget.userConfig.groups.map(
                      (group) => DropdownMenuItem<String>(
                        value: group.name,
                        child: Text(group.name),
                      ),
                    ),
                  ],
                  onChanged: (String? value) {
                    setState(() {
                      _selectedUserGroup = value ?? '';
                    });
                  },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(
                    onPressed: _loadingKeys.contains('add_user')
                        ? null
                        : _handleAddUser,
                    child: Text(
                      _loadingKeys.contains('add_user') ? '添加中...' : '确认添加',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _buildGroupsSection(),
        const SizedBox(height: 16),
        _buildUsersSection(),
      ],
    );
  }

  Widget _buildGroupsSection() {
    return GlassCard(
      isDark: widget.isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '用户组',
            style: AppTypography.headlineSmallStyle(isDark: widget.isDark),
          ),
          const SizedBox(height: 12),
          if (widget.userConfig.groups.isEmpty)
            Text(
              '暂无用户组，默认代表用户不受来源限制。',
              style: AppTypography.bodySmallStyle(isDark: widget.isDark),
            )
          else
            ...widget.userConfig.groups.map((group) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: _cardDecoration(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            group.name,
                            style: AppTypography.labelLargeStyle(
                              isDark: widget.isDark,
                            ),
                          ),
                        ),
                        _buildBadge(
                          group.enabledApis.isEmpty
                              ? '未限制来源'
                              : '${group.enabledApis.length} 个来源',
                          AppColors.secondary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      group.enabledApis.isEmpty
                          ? '当前用户组没有来源限制'
                          : '允许来源：${group.enabledApis.join('、')}',
                      style:
                          AppTypography.bodySmallStyle(isDark: widget.isDark),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        OutlinedButton(
                          onPressed:
                              _loadingKeys.contains('edit_group_${group.name}')
                                  ? null
                                  : () => _handleEditGroup(group),
                          child: Text(
                            _loadingKeys.contains('edit_group_${group.name}')
                                ? '处理中...'
                                : '编辑来源',
                          ),
                        ),
                        OutlinedButton(
                          onPressed: _loadingKeys
                                  .contains('delete_group_${group.name}')
                              ? null
                              : () => _handleDeleteGroup(group),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.error,
                            side: BorderSide(
                              color: AppColors.error.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            _loadingKeys.contains('delete_group_${group.name}')
                                ? '删除中...'
                                : '删除',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildUsersSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (_selectedUsernames.isNotEmpty) ...<Widget>[
          Text(
            '已选择 ${_selectedUsernames.length} 个用户，可批量设置用户组。',
            style: AppTypography.bodySmallStyle(isDark: widget.isDark),
          ),
          const SizedBox(height: 12),
        ],
        GlassCard(
          isDark: widget.isDark,
          child: widget.userConfig.users.isEmpty
              ? Text(
                  '暂无用户数据',
                  style: AppTypography.bodyMediumStyle(isDark: widget.isDark),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: widget.userConfig.users.length,
                  separatorBuilder: (BuildContext context, int index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (BuildContext context, int index) =>
                      _buildUserCard(widget.userConfig.users[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildUserCard(AdminUser user) {
    final bool canChangePassword = _canChangePassword(user);
    final bool canPromote = widget.isOwner &&
        user.role == AdminUserRole.user &&
        user.username != _currentUsername;
    final bool canDemote = widget.isOwner &&
        user.role == AdminUserRole.admin &&
        user.username != _currentUsername;
    final bool canBan = user.role != AdminUserRole.owner &&
        user.username != _currentUsername &&
        (widget.isOwner || user.role == AdminUserRole.user);
    final bool canDelete = user.role != AdminUserRole.owner &&
        user.username != _currentUsername &&
        (widget.isOwner || user.role == AdminUserRole.user);
    final bool canConfigureAccess = widget.isOwner ||
        user.role == AdminUserRole.user ||
        user.username == _currentUsername;
    final bool canSelectForBatch = widget.isOwner ||
        user.role == AdminUserRole.user ||
        user.username == _currentUsername;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              if (canSelectForBatch)
                Checkbox(
                  value: _selectedUsernames.contains(user.username),
                  onChanged: (bool? value) {
                    setState(() {
                      if (value == true) {
                        _selectedUsernames.add(user.username);
                      } else {
                        _selectedUsernames.remove(user.username);
                      }
                    });
                  },
                ),
              Text(
                user.username,
                style: AppTypography.labelLargeStyle(isDark: widget.isDark),
              ),
              _buildBadge(user.role.label, _roleColor(user.role)),
              _buildBadge(
                user.banned ? '已封禁' : '正常',
                user.banned ? AppColors.error : AppColors.success,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '用户组：${user.tags.isEmpty ? '未分组' : user.tags.join('、')}',
            style: AppTypography.bodySmallStyle(isDark: widget.isDark),
          ),
          const SizedBox(height: 4),
          Text(
            '源权限：${user.enabledApis.isEmpty ? '未限制' : '${user.enabledApis.length} 个来源'}',
            style: AppTypography.bodySmallStyle(isDark: widget.isDark),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (canConfigureAccess)
                OutlinedButton(
                  onPressed: _loadingKeys.contains('groups_${user.username}')
                      ? null
                      : () => _handleConfigureUserGroups(user),
                  child: Text(
                    _loadingKeys.contains('groups_${user.username}')
                        ? '处理中...'
                        : '配置用户组',
                  ),
                ),
              if (canConfigureAccess)
                OutlinedButton(
                  onPressed: _loadingKeys.contains('apis_${user.username}')
                      ? null
                      : () => _handleConfigureUserApis(user),
                  child: Text(
                    _loadingKeys.contains('apis_${user.username}')
                        ? '处理中...'
                        : '配置来源',
                  ),
                ),
              if (canChangePassword)
                _actionButton(
                  label: '改密码',
                  color: AppColors.secondary,
                  loading: _loadingKeys.contains('password_${user.username}'),
                  onTap: () => _handleChangePassword(user),
                ),
              if (canPromote)
                _actionButton(
                  label: '设为管理员',
                  color: AppColors.accent,
                  loading: _loadingKeys.contains('promote_${user.username}'),
                  onTap: () => _runAction(
                    loadingKey: 'promote_${user.username}',
                    successMessage: '已设为管理员',
                    action: () => widget.onAction(
                      action: 'setAdmin',
                      targetUsername: user.username,
                    ),
                  ),
                ),
              if (canDemote)
                _actionButton(
                  label: '取消管理员',
                  color: AppColors.warning,
                  loading: _loadingKeys.contains('demote_${user.username}'),
                  onTap: () => _runAction(
                    loadingKey: 'demote_${user.username}',
                    successMessage: '已取消管理员',
                    action: () => widget.onAction(
                      action: 'cancelAdmin',
                      targetUsername: user.username,
                    ),
                  ),
                ),
              if (canBan && !user.banned)
                _actionButton(
                  label: '封禁',
                  color: AppColors.error,
                  loading: _loadingKeys.contains('ban_${user.username}'),
                  onTap: () => _runAction(
                    loadingKey: 'ban_${user.username}',
                    successMessage: '已封禁用户',
                    action: () => widget.onAction(
                      action: 'ban',
                      targetUsername: user.username,
                    ),
                  ),
                ),
              if (canBan && user.banned)
                _actionButton(
                  label: '解封',
                  color: AppColors.success,
                  loading: _loadingKeys.contains('unban_${user.username}'),
                  onTap: () => _runAction(
                    loadingKey: 'unban_${user.username}',
                    successMessage: '已解封用户',
                    action: () => widget.onAction(
                      action: 'unban',
                      targetUsername: user.username,
                    ),
                  ),
                ),
              if (canDelete)
                _actionButton(
                  label: '删除',
                  color: AppColors.error,
                  loading: _loadingKeys.contains('delete_${user.username}'),
                  onTap: () => _handleDeleteUser(user),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required String label,
    required Color color,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      onPressed: loading ? null : onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(loading ? '处理中...' : label),
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

  bool _canChangePassword(AdminUser user) {
    if (user.role == AdminUserRole.owner) {
      return false;
    }
    if (widget.isOwner) {
      return true;
    }
    return user.role == AdminUserRole.user || user.username == _currentUsername;
  }

  Color _roleColor(AdminUserRole role) {
    switch (role) {
      case AdminUserRole.owner:
        return AppColors.accent;
      case AdminUserRole.admin:
        return AppColors.secondary;
      case AdminUserRole.user:
        return AppColors.primary;
    }
  }

  Future<void> _loadCurrentUsername() async {
    final String? username = await UserDataService.getUsername();
    if (!mounted) {
      return;
    }
    setState(() {
      _currentUsername = username;
    });
  }

  bool get _areAllAllowedUsersSelected {
    final List<String> usernames = _allowedBatchUsernames;
    return usernames.isNotEmpty &&
        usernames.every(_selectedUsernames.contains) &&
        _selectedUsernames.length == usernames.length;
  }

  List<String> get _allowedBatchUsernames {
    return widget.userConfig.users
        .where(
          (user) =>
              widget.isOwner ||
              user.role == AdminUserRole.user ||
              user.username == _currentUsername,
        )
        .map((user) => user.username)
        .toList(growable: false);
  }

  void _handleToggleSelectAllUsers() {
    final List<String> usernames = _allowedBatchUsernames;
    setState(() {
      if (_areAllAllowedUsersSelected) {
        _selectedUsernames.clear();
      } else {
        _selectedUsernames
          ..clear()
          ..addAll(usernames);
      }
    });
  }

  Future<void> _handleAddUser() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String username = _usernameController.text.trim();
    final String password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) {
      _showSnackBar(messenger, '用户名和密码不能为空', false);
      return;
    }

    final bool success = await _runAction(
      loadingKey: 'add_user',
      successMessage: '用户已添加',
      action: () => widget.onAction(
        action: 'add',
        targetUsername: username,
        targetPassword: password,
        userGroup: _selectedUserGroup,
      ),
    );

    if (!mounted || !success) {
      return;
    }

    _usernameController.clear();
    _passwordController.clear();
    setState(() {
      _selectedUserGroup = '';
      _showAddUserForm = false;
    });
  }

  Future<void> _handleCreateGroup() async {
    final TextEditingController controller = TextEditingController();
    final String? groupName = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('新增用户组'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(hintText: '输入用户组名称'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('下一步'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (groupName == null || groupName.isEmpty) {
      return;
    }

    final List<String>? selectedApis = await _showSourceSelectionDialog(
      title: '选择允许来源 · $groupName',
      initialSelection: const <String>[],
    );
    if (selectedApis == null) {
      return;
    }

    await _runAction(
      loadingKey: 'create_group_$groupName',
      successMessage: '用户组已创建',
      action: () => widget.onAction(
        action: 'userGroup',
        groupAction: 'add',
        groupName: groupName,
        enabledApis: selectedApis,
      ),
    );
  }

  Future<void> _handleEditGroup(AdminUserGroup group) async {
    final List<String>? selectedApis = await _showSourceSelectionDialog(
      title: '编辑用户组来源 · ${group.name}',
      initialSelection: group.enabledApis,
    );
    if (selectedApis == null) {
      return;
    }

    await _runAction(
      loadingKey: 'edit_group_${group.name}',
      successMessage: '用户组已更新',
      action: () => widget.onAction(
        action: 'userGroup',
        groupAction: 'edit',
        groupName: group.name,
        enabledApis: selectedApis,
      ),
    );
  }

  Future<void> _handleDeleteGroup(AdminUserGroup group) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认删除用户组'),
          content: Text('确定要删除用户组 ${group.name} 吗？关联用户会失去该组。'),
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
      loadingKey: 'delete_group_${group.name}',
      successMessage: '用户组已删除',
      action: () => widget.onAction(
        action: 'userGroup',
        groupAction: 'delete',
        groupName: group.name,
      ),
    );
  }

  Future<void> _handleConfigureUserGroups(AdminUser user) async {
    final List<String>? selectedGroups = await _showGroupSelectionDialog(
      title: '配置用户组 · ${user.username}',
      initialSelection: user.tags,
    );
    if (selectedGroups == null) {
      return;
    }

    await _runAction(
      loadingKey: 'groups_${user.username}',
      successMessage: '用户组已更新',
      action: () => widget.onAction(
        action: 'updateUserGroups',
        targetUsername: user.username,
        userGroups: selectedGroups,
      ),
    );
  }

  Future<void> _handleBatchConfigureUserGroups() async {
    final List<String>? selectedGroups = await _showGroupSelectionDialog(
      title: '批量设置用户组',
      initialSelection: const <String>[],
    );
    if (selectedGroups == null) {
      return;
    }

    final bool success = await _runAction(
      loadingKey: 'batch_groups',
      successMessage: '已批量更新用户组',
      action: () => widget.onAction(
        action: 'batchUpdateUserGroups',
        usernames: _selectedUsernames.toList(growable: false),
        userGroups: selectedGroups,
      ),
    );

    if (!mounted || !success) {
      return;
    }
    setState(() {
      _selectedUsernames.clear();
    });
  }

  Future<void> _handleConfigureUserApis(AdminUser user) async {
    final List<String>? selectedApis = await _showSourceSelectionDialog(
      title: '配置来源权限 · ${user.username}',
      initialSelection: user.enabledApis,
    );
    if (selectedApis == null) {
      return;
    }

    await _runAction(
      loadingKey: 'apis_${user.username}',
      successMessage: '用户来源权限已更新',
      action: () => widget.onAction(
        action: 'updateUserApis',
        targetUsername: user.username,
        enabledApis: selectedApis,
      ),
    );
  }

  Future<void> _handleChangePassword(AdminUser user) async {
    final TextEditingController controller = TextEditingController();
    final String? password = await showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('修改密码 · ${user.username}'),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: const InputDecoration(hintText: '输入新密码'),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('确认'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    if (password == null || password.isEmpty) {
      return;
    }

    await _runAction(
      loadingKey: 'password_${user.username}',
      successMessage: '密码已更新',
      action: () => widget.onAction(
        action: 'changePassword',
        targetUsername: user.username,
        targetPassword: password,
      ),
    );
  }

  Future<void> _handleDeleteUser(AdminUser user) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认删除用户'),
          content: Text('确定要删除用户 ${user.username} 吗？此操作不可撤销。'),
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
      loadingKey: 'delete_${user.username}',
      successMessage: '用户已删除',
      action: () => widget.onAction(
        action: 'deleteUser',
        targetUsername: user.username,
      ),
    );
  }

  Future<List<String>?> _showGroupSelectionDialog({
    required String title,
    required List<String> initialSelection,
  }) {
    final Set<String> selected = initialSelection.toSet();
    return showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 420,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: widget.userConfig.groups.isEmpty
                      ? const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('暂无用户组，可先创建用户组。'),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: widget.userConfig.groups.map((group) {
                            final bool checked = selected.contains(group.name);
                            return CheckboxListTile(
                              value: checked,
                              title: Text(group.name),
                              subtitle: Text(
                                group.enabledApis.isEmpty
                                    ? '未限制来源'
                                    : '${group.enabledApis.length} 个来源',
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (bool? value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selected.add(group.name);
                                  } else {
                                    selected.remove(group.name);
                                  }
                                });
                              },
                            );
                          }).toList(growable: false),
                        ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context)
                      .pop(selected.toList(growable: false)),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<List<String>?> _showSourceSelectionDialog({
    required String title,
    required List<String> initialSelection,
  }) {
    final Set<String> selected = initialSelection.toSet();
    return showDialog<List<String>>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 460,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: widget.sources.isEmpty
                      ? const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('暂无可配置来源。'),
                        )
                      : ListView(
                          shrinkWrap: true,
                          children: widget.sources.map((source) {
                            final bool checked = selected.contains(source.key);
                            return CheckboxListTile(
                              value: checked,
                              title: Text(source.name),
                              subtitle: Text(source.key),
                              controlAffinity: ListTileControlAffinity.leading,
                              contentPadding: EdgeInsets.zero,
                              onChanged: (bool? value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selected.add(source.key);
                                  } else {
                                    selected.remove(source.key);
                                  }
                                });
                              },
                            );
                          }).toList(growable: false),
                        ),
                ),
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context)
                      .pop(selected.toList(growable: false)),
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
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
}
