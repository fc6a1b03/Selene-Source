import 'package:flutter/material.dart';
import 'package:selene/components/animations/glass_card.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/models/admin_config.dart';
import 'package:selene/models/admin_data_migration.dart';

class AdminOwnerToolsCard extends StatefulWidget {
  const AdminOwnerToolsCard({
    super.key,
    required this.isDark,
    required this.configSubscription,
    required this.configFile,
    required this.isFetching,
    required this.isSaving,
    required this.isResetting,
    required this.onFetchSubscription,
    required this.onSaveConfigFile,
    required this.onResetConfig,
    required this.errorMessage,
    required this.isExportingMigrationData,
    required this.isImportingMigrationData,
    required this.onExportMigrationData,
    required this.onImportMigrationData,
  });

  final bool isDark;
  final AdminConfigSubscription configSubscription;
  final String configFile;
  final bool isFetching;
  final bool isSaving;
  final bool isResetting;
  final Future<String?> Function(String url) onFetchSubscription;
  final Future<bool> Function({
    required String configFile,
    required String subscriptionUrl,
    required bool autoUpdate,
    required String lastCheckTime,
  }) onSaveConfigFile;
  final Future<bool> Function() onResetConfig;
  final String? errorMessage;
  final bool isExportingMigrationData;
  final bool isImportingMigrationData;
  final Future<bool> Function(String password) onExportMigrationData;
  final Future<DataMigrationImportResult?> Function(String password)
      onImportMigrationData;

  @override
  State<AdminOwnerToolsCard> createState() => _AdminOwnerToolsCardState();
}

class _AdminOwnerToolsCardState extends State<AdminOwnerToolsCard> {
  late final TextEditingController _subscriptionUrlController;
  late final TextEditingController _configContentController;

  late bool _autoUpdate;
  String _lastCheckTime = '';

  @override
  void initState() {
    super.initState();
    _subscriptionUrlController = TextEditingController();
    _configContentController = TextEditingController();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(covariant AdminOwnerToolsCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.configSubscription != widget.configSubscription ||
        oldWidget.configFile != widget.configFile) {
      _syncFromWidget();
    }
  }

  @override
  void dispose() {
    _subscriptionUrlController.dispose();
    _configContentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '站长工具',
          style: AppTypography.headlineLargeStyle(isDark: widget.isDark),
        ),
        const SizedBox(height: 8),
        Text(
          '已接入配置订阅拉取、配置文件保存和重置配置。',
          style: AppTypography.bodyMediumStyle(isDark: widget.isDark).copyWith(
            color: AppColors.textSecondary(isDark: widget.isDark),
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          isDark: widget.isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '配置订阅',
                style: AppTypography.headlineSmallStyle(isDark: widget.isDark),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _subscriptionUrlController,
                decoration: const InputDecoration(hintText: '订阅 URL'),
              ),
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _autoUpdate,
                onChanged: (bool value) {
                  setState(() {
                    _autoUpdate = value;
                  });
                },
                title: const Text('自动更新'),
                subtitle: Text(
                  _lastCheckTime.isEmpty ? '暂无拉取记录' : '上次检查：$_lastCheckTime',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed:
                      widget.isFetching ? null : _handleFetchSubscription,
                  child: Text(widget.isFetching ? '拉取中...' : '拉取配置'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          isDark: widget.isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '配置文件',
                style: AppTypography.headlineSmallStyle(isDark: widget.isDark),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _configContentController,
                minLines: 16,
                maxLines: 24,
                style: AppTypography.mono(
                  fontSize: 12,
                  color: AppColors.textPrimary(isDark: widget.isDark),
                ),
                decoration: const InputDecoration(
                  hintText: '输入配置文件内容（JSON）',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.isResetting ? null : _handleResetConfig,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: BorderSide(
                          color: AppColors.error.withValues(alpha: 0.45),
                        ),
                      ),
                      child: Text(widget.isResetting ? '重置中...' : '重置配置'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.isSaving ? null : _handleSaveConfigFile,
                      child: Text(widget.isSaving ? '保存中...' : '保存配置'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          isDark: widget.isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '数据迁移',
                style: AppTypography.headlineSmallStyle(isDark: widget.isDark),
              ),
              const SizedBox(height: 12),
              Text(
                '导出会弹系统保存窗口，导入会弹系统文件选择窗口。',
                style: AppTypography.bodySmallStyle(isDark: widget.isDark),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.isExportingMigrationData
                          ? null
                          : _handleExportMigration,
                      child: Text(
                        widget.isExportingMigrationData ? '导出中...' : '导出数据',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.isImportingMigrationData
                          ? null
                          : _handleImportMigration,
                      child: Text(
                        widget.isImportingMigrationData ? '导入中...' : '导入数据',
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _handleFetchSubscription() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String url = _subscriptionUrlController.text.trim();
    if (url.isEmpty) {
      _showSnackBar(messenger, '订阅地址不能为空', false);
      return;
    }

    final String? configContent = await widget.onFetchSubscription(url);
    if (!mounted) {
      return;
    }

    if (configContent == null || configContent.isEmpty) {
      _showSnackBar(messenger, '拉取配置失败', false);
      return;
    }

    setState(() {
      _configContentController.text = configContent;
      _lastCheckTime = DateTime.now().toIso8601String();
    });
    _showSnackBar(messenger, '已拉取最新配置', true);
  }

  Future<void> _handleSaveConfigFile() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool success = await widget.onSaveConfigFile(
      configFile: _configContentController.text,
      subscriptionUrl: _subscriptionUrlController.text.trim(),
      autoUpdate: _autoUpdate,
      lastCheckTime: _lastCheckTime,
    );

    if (!mounted) {
      return;
    }
    _showSnackBar(messenger, success ? '配置已保存' : '保存配置失败', success);
  }

  Future<void> _handleResetConfig() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('确认重置配置'),
          content: const Text('确定要重置当前管理配置吗？此操作会覆盖现有后台配置。'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('重置'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    final bool success = await widget.onResetConfig();
    if (!mounted) {
      return;
    }
    _showSnackBar(messenger, success ? '配置已重置' : '重置配置失败', success);
  }

  Future<void> _handleExportMigration() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? password = await _showPasswordDialog(
      title: '导出数据',
      hintText: '输入导出加密密码',
    );
    if (password == null || password.isEmpty) {
      return;
    }

    final bool success = await widget.onExportMigrationData(password);
    if (!mounted) {
      return;
    }
    if (!success && widget.errorMessage == null) {
      return;
    }
    _showSnackBar(
      messenger,
      success ? '导出成功' : (widget.errorMessage ?? '导出失败'),
      success,
    );
  }

  Future<void> _handleImportMigration() async {
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final String? password = await _showPasswordDialog(
      title: '导入数据',
      hintText: '输入备份解密密码',
    );
    if (password == null || password.isEmpty) {
      return;
    }

    final DataMigrationImportResult? result =
        await widget.onImportMigrationData(password);
    if (!mounted) {
      return;
    }

    if (result == null) {
      if (widget.errorMessage == null) {
        return;
      }
      _showSnackBar(messenger, widget.errorMessage!, false);
      return;
    }

    _showSnackBar(
      messenger,
      '导入成功：${result.importedUsers} 个用户',
      true,
    );
  }

  Future<String?> _showPasswordDialog({
    required String title,
    required String hintText,
  }) {
    final TextEditingController controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            obscureText: true,
            decoration: InputDecoration(hintText: hintText),
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
    ).whenComplete(controller.dispose);
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

  void _syncFromWidget() {
    _subscriptionUrlController.text = widget.configSubscription.url;
    _configContentController.text = widget.configFile;
    _autoUpdate = widget.configSubscription.autoUpdate;
    _lastCheckTime = widget.configSubscription.lastCheck;
  }
}
