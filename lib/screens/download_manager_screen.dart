import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/models/download_task_persistent.dart';
import 'package:selene/services/advanced_download_manager.dart';
import 'package:selene/services/background_download_service.dart';
import 'package:selene/utils/font_utils.dart';
import 'package:selene/widgets/windows_title_bar.dart';

/// 下载管理页面
class DownloadManagerScreen extends StatefulWidget {
  const DownloadManagerScreen({super.key});

  @override
  State<DownloadManagerScreen> createState() => _DownloadManagerScreenState();
}

class _DownloadManagerScreenState extends State<DownloadManagerScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['全部', '下载中', '已完成'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(isDark: true),
      body: Stack(
        children: [
          Column(
            children: [
              _buildAppBar(),
              _buildTabBar(),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTaskList(filter: DownloadFilter.all),
                    _buildTaskList(filter: DownloadFilter.downloading),
                    _buildTaskList(filter: DownloadFilter.completed),
                  ],
                ),
              ),
              _buildBottomStats(),
            ],
          ),
          if (Platform.isWindows)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: WindowsTitleBar(),
            ),
        ],
      ),
    );
  }

  Widget _buildAppBar() {
    return Container(
      padding: EdgeInsets.only(
        top: Platform.isWindows
            ? 36 + MediaQuery.of(context).padding.top
            : MediaQuery.of(context).padding.top + 16,
        left: 16,
        right: 16,
        bottom: 16,
      ),
      decoration: BoxDecoration(
        gradient: AppColors.backgroundGradient(isDark: true),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(
              LucideIcons.arrowLeft,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '下载管理',
                  style: AppTypography.headlineSmallStyle(isDark: true),
                ),
                const SizedBox(height: 2),
                _buildStatsText(),
              ],
            ),
          ),
          _buildClearButton(),
        ],
      ),
    );
  }

  Widget _buildStatsText() {
    return StreamBuilder<DownloadStatistics>(
      stream: AdvancedDownloadManager().statisticsStream,
      initialData: const DownloadStatistics(),
      builder: (context, snapshot) {
        final stats = snapshot.data!;
        return Text(
          '${stats.totalTasks} 个任务 • ${stats.formattedTotalDownloaded}',
          style: AppTypography.bodySmallStyle(isDark: true).copyWith(
            color: AppColors.textSecondary(isDark: true),
          ),
        );
      },
    );
  }

  Widget _buildClearButton() {
    return Consumer<AdvancedDownloadManager>(
      builder: (context, manager, _) {
        final hasCompleted = manager.getAllTasks().any((t) => t.isFinished);

        if (!hasCompleted) return const SizedBox(width: 0);

        return Flexible(
          child: TextButton.icon(
            onPressed: () => _showClearConfirmDialog(context),
            icon: const Icon(
              LucideIcons.trash2,
              size: 16,
              color: Colors.red,
            ),
            label: Text(
              '清空已完成',
              style: FontUtils.poppins(
                fontSize: 12,
                color: Colors.red,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        );
      },
    );
  }

  Future<void> _showClearConfirmDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.surface(isDark: true),
        title: Text(
          '清空已完成任务',
          style: AppTypography.headlineSmallStyle(isDark: true),
        ),
        content: Text(
          '确定要清空所有已完成的下载任务吗？此操作不会删除已下载的文件。',
          style: AppTypography.bodyMediumStyle(isDark: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              '取消',
              style: AppTypography.bodyMediumStyle(isDark: true).copyWith(
                color: AppColors.textSecondary(isDark: true),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              '确定',
              style: AppTypography.bodyMediumStyle(isDark: true).copyWith(
                color: Colors.red,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final count = await AdvancedDownloadManager().clearCompletedTasks();
      if (mounted) {
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已清空 $count 个任务'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    }
  }

  Widget _buildTabBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.background(isDark: true),
        border: Border(
          bottom: BorderSide(
            color: Colors.white.withValues(alpha: 0.06),
          ),
        ),
      ),
      child: Consumer<AdvancedDownloadManager>(
        builder: (context, manager, _) {
          return Row(
            children: _tabs.asMap().entries.map((entry) {
              final index = entry.key;
              final label = entry.value;
              return _buildCleanTabItem(
                index: index,
                label: label,
                count: _getTaskCountForTab(index, manager),
              );
            }).toList(),
          );
        },
      ),
    );
  }

  /// 极简线条风格 - 类似 Chrome/Safari 标签页
  Widget _buildCleanTabItem({
    required int index,
    required String label,
    required int count,
  }) {
    return AnimatedBuilder(
      animation: _tabController,
      builder: (context, child) {
        final isSelected = _tabController.index == index;
        final displayText = count > 0 ? '$label ($count)' : label;

        return GestureDetector(
          onTap: () => _tabController.animateTo(index),
          child: Container(
            margin: const EdgeInsets.only(right: 24),
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isSelected ? AppColors.primary : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              displayText,
              style: FontUtils.poppins(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected
                    ? Colors.white
                    : AppColors.textSecondary(isDark: true),
              ),
            ),
          ),
        );
      },
    );
  }

  int _getTaskCountForTab(int index, AdvancedDownloadManager manager) {
    final tasks = manager.getAllTasks();
    switch (index) {
      case 0: // 全部
        return tasks.length;
      case 1: // 下载中
        return tasks
            .where((t) =>
                t.status == DownloadTaskPersistentStatus.downloading ||
                t.status == DownloadTaskPersistentStatus.paused ||
                t.status == DownloadTaskPersistentStatus.waiting)
            .length;
      case 2: // 已完成
        return tasks
            .where((t) =>
                t.status == DownloadTaskPersistentStatus.completed ||
                t.status == DownloadTaskPersistentStatus.saved ||
                t.status == DownloadTaskPersistentStatus.failed ||
                t.status == DownloadTaskPersistentStatus.cancelled)
            .length;
      default:
        return 0;
    }
  }

  Widget _buildTaskList({required DownloadFilter filter}) {
    return Consumer<AdvancedDownloadManager>(
      builder: (context, manager, _) {
        final tasks = _filterTasks(manager.getAllTasks(), filter);

        if (tasks.isEmpty) {
          return _buildEmptyState(filter);
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];
            // 使用 ValueKey 确保 Flutter 正确识别每个任务卡片
            // 避免 widget 重用导致操作错误的任务
            return _DownloadTaskCard(
              key: ValueKey(task.id),
              task: task,
              onPause: () {
                debugPrint('[UI] 暂停任务: ${task.id} - ${task.fileName}');
                manager.pauseDownload(task.id);
              },
              onResume: () {
                debugPrint('[UI] 恢复任务: ${task.id} - ${task.fileName}');
                manager.resumeDownload(task.id);
              },
              onCancel: () {
                debugPrint('[UI] 取消任务: ${task.id} - ${task.fileName}');
                manager.cancelDownload(task.id);
              },
              onDelete: () {
                debugPrint('[UI] 删除任务: ${task.id} - ${task.fileName}');
                manager.deleteTask(task.id);
              },
              onRetry: () {
                debugPrint('[UI] 重试任务: ${task.id} - ${task.fileName}');
                manager.retryTask(task.id);
              },
              onSave: task.isLiveStream
                  ? () {
                      debugPrint('[UI] 保存直播: ${task.id} - ${task.fileName}');
                      manager.saveLiveStream(task.id);
                    }
                  : null,
            );
          },
        );
      },
    );
  }

  List<DownloadTaskPersistent> _filterTasks(
    List<DownloadTaskPersistent> tasks,
    DownloadFilter filter,
  ) {
    switch (filter) {
      case DownloadFilter.all:
        return tasks..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case DownloadFilter.downloading:
        return tasks
            .where((t) =>
                t.status == DownloadTaskPersistentStatus.downloading ||
                t.status == DownloadTaskPersistentStatus.paused ||
                t.status == DownloadTaskPersistentStatus.waiting)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case DownloadFilter.completed:
        return tasks
            .where((t) =>
                t.status == DownloadTaskPersistentStatus.completed ||
                t.status == DownloadTaskPersistentStatus.saved ||
                t.status == DownloadTaskPersistentStatus.failed ||
                t.status == DownloadTaskPersistentStatus.cancelled)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
  }

  Widget _buildEmptyState(DownloadFilter filter) {
    String message;
    IconData icon;

    switch (filter) {
      case DownloadFilter.all:
        message = '暂无下载任务';
        icon = LucideIcons.download;
      case DownloadFilter.downloading:
        message = '没有正在下载的任务';
        icon = LucideIcons.loader;
      case DownloadFilter.completed:
        message = '没有已完成的任务';
        icon = LucideIcons.circleCheck;
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 64,
            color: AppColors.textTertiary(isDark: true),
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: AppTypography.bodyLargeStyle(isDark: true).copyWith(
              color: AppColors.textSecondary(isDark: true),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStats() {
    return StreamBuilder<DownloadStatistics>(
      stream: AdvancedDownloadManager().statisticsStream,
      initialData: const DownloadStatistics(),
      builder: (context, snapshot) {
        final stats = snapshot.data!;

        if (stats.downloadingTasks == 0) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: MediaQuery.of(context).padding.bottom + 12,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface(isDark: true),
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${stats.downloadingTasks} 个任务下载中',
                      style:
                          AppTypography.bodyMediumStyle(isDark: true).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '总速度: ${stats.formattedCurrentSpeed}',
                      style:
                          AppTypography.bodySmallStyle(isDark: true).copyWith(
                        color: AppColors.textSecondary(isDark: true),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 下载过滤器枚举
enum DownloadFilter {
  all,
  downloading,
  completed,
}

/// 下载任务卡片
///
/// 注意：必须使用 ValueKey(task.id) 来确保 Flutter 正确识别每个卡片
/// 避免在列表变化时出现 widget 重用导致操作错误任务的问题
class _DownloadTaskCard extends StatefulWidget {
  final DownloadTaskPersistent task;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onCancel;
  final VoidCallback onDelete;
  final VoidCallback onRetry;
  final VoidCallback? onSave;

  const _DownloadTaskCard({
    super.key,
    required this.task,
    required this.onPause,
    required this.onResume,
    required this.onCancel,
    required this.onDelete,
    required this.onRetry,
    this.onSave,
  });

  @override
  State<_DownloadTaskCard> createState() => _DownloadTaskCardState();
}

class _DownloadTaskCardState extends State<_DownloadTaskCard> {
  StreamSubscription<DownloadTaskProgressEvent>? _progressSubscription;
  DownloadTaskProgressEvent? _latestProgress;
  bool _isProcessing = false; // 防重复点击标志

  @override
  void initState() {
    super.initState();
    debugPrint(
        '[DownloadTaskCard] initState: ${widget.task.id} - ${widget.task.fileName}');
    _subscribeToProgress();
    // 初始化后台下载服务并显示通知
    _initBackgroundService();
  }

  Future<void> _initBackgroundService() async {
    // Windows/Linux 平台不支持本地通知
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      return;
    }
    final service = BackgroundDownloadService();
    await service.initialize();
    await service.showDownloadProgress(widget.task);
  }

  @override
  void didUpdateWidget(_DownloadTaskCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 只有当任务ID变化时才重新订阅
    if (oldWidget.task.id != widget.task.id) {
      debugPrint(
          '[DownloadTaskCard] didUpdateWidget: 任务ID变化 ${oldWidget.task.id} -> ${widget.task.id}');
      debugPrint(
          '[DownloadTaskCard] 新任务: ${widget.task.fileName}, 状态: ${widget.task.status}');
      _progressSubscription?.cancel();
      _subscribeToProgress();
    }
    // 状态变化时更新通知
    if (oldWidget.task.status != widget.task.status) {
      _updateNotification();
    }
  }

  Future<void> _updateNotification() async {
    // Windows/Linux 平台不支持本地通知
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
      return;
    }
    final service = BackgroundDownloadService();
    if (widget.task.isFinished) {
      await service.showDownloadComplete(widget.task);
    } else if (widget.task.status == DownloadTaskPersistentStatus.failed) {
      await service.showDownloadFailed(
        widget.task,
        widget.task.errorMessage ?? '未知错误',
      );
    } else {
      await service.showDownloadProgress(widget.task);
    }
  }

  void _subscribeToProgress() {
    _progressSubscription?.cancel();
    _progressSubscription = AdvancedDownloadManager()
        .getTaskProgressStream(widget.task.id)
        ?.listen((event) {
      if (mounted) {
        setState(() {
          _latestProgress = event;
        });
      }
    });
  }

  /// 包装回调，防止重复点击和越权操作
  /// 责任单一：每个按钮只做一件事
  VoidCallback? _wrapCallback(VoidCallback? callback,
      {required String action}) {
    if (callback == null) return null;
    return () {
      debugPrint(
          '[DownloadTaskCard] 按钮点击: $action, 任务: ${widget.task.id} - ${widget.task.fileName}');

      // 防重复点击
      if (_isProcessing) {
        debugPrint('[DownloadTaskCard] 操作过于频繁，忽略: $action');
        return;
      }

      // 根据当前状态验证操作是否合法
      if (!_isActionValid(action)) {
        debugPrint(
            '[DownloadTaskCard] 操作不被允许: $action, 当前状态: ${widget.task.status}');
        return;
      }

      setState(() => _isProcessing = true);

      // 执行操作
      debugPrint('[DownloadTaskCard] 执行回调: $action');
      callback();

      // 延迟重置处理标志
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() => _isProcessing = false);
        }
      });
    };
  }

  /// 验证操作是否合法
  bool _isActionValid(String action) {
    switch (action) {
      case 'pause':
        return widget.task.canPause;
      case 'resume':
        return widget.task.canResume;
      case 'cancel':
        return widget.task.status == DownloadTaskPersistentStatus.downloading;
      case 'delete':
        return widget.task.canDelete;
      case 'retry':
        return widget.task.status == DownloadTaskPersistentStatus.failed;
      case 'save':
        return widget.task.isLiveStream && widget.task.isDownloading;
      default:
        return true;
    }
  }

  @override
  void dispose() {
    debugPrint(
        '[DownloadTaskCard] dispose: ${widget.task.id} - ${widget.task.fileName}');
    _progressSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final progress = _latestProgress;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surface(isDark: true),
            AppColors.surface(isDark: true).withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // 进度条（仅在下载中显示）
            if (task.isDownloading && !task.isLiveStream)
              LinearProgressIndicator(
                value: progress?.progress ?? task.progress,
                backgroundColor: Colors.white.withValues(alpha: 0.1),
                valueColor: AlwaysStoppedAnimation<Color>(
                  Color(task.statusColor),
                ),
                minHeight: 3,
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 缩略图或图标
                  _buildThumbnail(task),
                  const SizedBox(width: 12),
                  // 信息区域
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 标题
                        Text(
                          task.videoTitle ?? task.fileName,
                          style: AppTypography.bodyLargeStyle(isDark: true)
                              .copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        // 状态信息
                        _buildStatusInfo(task, progress),
                        const SizedBox(height: 8),
                        // 操作按钮
                        _buildActionButtons(task),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(DownloadTaskPersistent task) {
    final Widget placeholder = Container(
      width: 80,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        task.isLiveStream ? LucideIcons.radio : LucideIcons.video,
        color: AppColors.textTertiary(isDark: true),
        size: 24,
      ),
    );

    if (task.videoCover == null || task.videoCover!.isEmpty) {
      return placeholder;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 80,
        height: 60,
        child: Image.network(
          task.videoCover!,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
        ),
      ),
    );
  }

  Widget _buildStatusInfo(
    DownloadTaskPersistent task,
    DownloadTaskProgressEvent? progress,
  ) {
    final isLiveStream = task.isLiveStream;
    final isDownloading = task.isDownloading;

    final List<Widget> children = [
      Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 2,
        ),
        decoration: BoxDecoration(
          color: Color(task.statusColor).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          task.statusText,
          style: FontUtils.poppins(
            fontSize: 10,
            color: Color(task.statusColor),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ];

    if (isLiveStream) {
      // 直播流显示录制时长和大小
      if (isDownloading) {
        children.addAll([
          const SizedBox(width: 8),
          Icon(
            LucideIcons.circle,
            size: 8,
            color: Colors.red,
          ),
          const SizedBox(width: 4),
          Text(
            '录制中',
            style: AppTypography.bodySmallStyle(isDark: true).copyWith(
              color: Colors.red,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            progress != null
                ? '${task.formattedDownloadedSize} • ${task.formattedSpeed}'
                : '${task.formattedDownloadedSize} • ${task.formattedSpeed}',
            style: AppTypography.bodySmallStyle(isDark: true).copyWith(
              color: AppColors.textSecondary(isDark: true),
            ),
          ),
        ]);
      } else {
        children.addAll([
          const SizedBox(width: 8),
          Text(
            task.formattedDownloadedSize,
            style: AppTypography.bodySmallStyle(isDark: true).copyWith(
              color: AppColors.textSecondary(isDark: true),
            ),
          ),
        ]);
      }
    } else {
      // 普通视频显示进度信息
      if (isDownloading && progress != null) {
        children.addAll([
          const SizedBox(width: 8),
          Text(
            '${(progress.progress * 100).toStringAsFixed(1)}%',
            style: AppTypography.bodySmallStyle(isDark: true).copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${task.formattedDownloadedSize} / ${task.formattedTotalSize}',
            style: AppTypography.bodySmallStyle(isDark: true).copyWith(
              color: AppColors.textSecondary(isDark: true),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '• ${task.formattedSpeed}',
            style: AppTypography.bodySmallStyle(isDark: true).copyWith(
              color: AppColors.textTertiary(isDark: true),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '• 剩余 ${task.formattedRemainingTime}',
            style: AppTypography.bodySmallStyle(isDark: true).copyWith(
              color: AppColors.textTertiary(isDark: true),
            ),
          ),
        ]);
      } else if (task.status == DownloadTaskPersistentStatus.completed) {
        children.addAll([
          const SizedBox(width: 8),
          Text(
            task.formattedTotalSize,
            style: AppTypography.bodySmallStyle(isDark: true).copyWith(
              color: AppColors.textSecondary(isDark: true),
            ),
          ),
        ]);
      } else if (task.errorMessage != null) {
        children.addAll([
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              task.errorMessage!,
              style: AppTypography.bodySmallStyle(isDark: true).copyWith(
                color: Colors.red,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]);
      }
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }

  Widget _buildActionButtons(DownloadTaskPersistent task) {
    final List<Widget> buttons = [];

    // 主操作按钮 - 根据状态显示不同的操作
    // 责任单一：每个按钮只做一件事，不做多余的操作
    if (task.isLiveStream && task.isDownloading) {
      // 直播流录制中 - 显示终止并保存按钮
      buttons.add(
        _ActionButton(
          icon: LucideIcons.square,
          label: '终止并保存',
          color: Colors.orange,
          onTap: _wrapCallback(widget.onSave, action: 'save'),
          isEnabled: !_isProcessing,
        ),
      );
    } else if (task.canPause) {
      // 可以暂停
      buttons.add(
        _ActionButton(
          icon: LucideIcons.pause,
          label: '暂停',
          color: AppColors.primary,
          onTap: _wrapCallback(widget.onPause, action: 'pause'),
          isEnabled: !_isProcessing,
        ),
      );
    } else if (task.canResume) {
      // 可以恢复
      buttons.add(
        _ActionButton(
          icon: LucideIcons.play,
          label: '继续',
          color: AppColors.primary,
          onTap: _wrapCallback(widget.onResume, action: 'resume'),
          isEnabled: !_isProcessing,
        ),
      );
    } else if (task.status == DownloadTaskPersistentStatus.failed) {
      // 失败 - 显示重试
      buttons.add(
        _ActionButton(
          icon: LucideIcons.refreshCw,
          label: '重试',
          color: Colors.orange,
          onTap: _wrapCallback(widget.onRetry, action: 'retry'),
          isEnabled: !_isProcessing,
        ),
      );
    }

    // 次要操作按钮
    if (task.status == DownloadTaskPersistentStatus.downloading) {
      // 下载中 - 显示取消（取消只停止下载，不删除记录）
      buttons.add(
        _ActionButton(
          icon: LucideIcons.x,
          label: '取消',
          color: Colors.red,
          onTap: _wrapCallback(widget.onCancel, action: 'cancel'),
          isEnabled: !_isProcessing,
        ),
      );
    } else if (task.canDelete) {
      // 可以删除（删除 = 停止 + 清理资源 + 移除记录）
      // 删除操作不会触发其他任务的任何操作
      buttons.add(
        _ActionButton(
          icon: LucideIcons.trash2,
          label: '删除',
          color: Colors.red,
          onTap: _wrapCallback(widget.onDelete, action: 'delete'),
          isEnabled: !_isProcessing,
        ),
      );
    }

    return Row(
      children: buttons
          .expand((button) => [
                button,
                const SizedBox(width: 12),
              ])
          .toList()
        ..removeLast(),
    );
  }
}

/// 操作按钮
///
/// 责任单一：每个按钮只执行一个操作
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;
  final bool isEnabled;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.isEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = isEnabled ? color : color.withValues(alpha: 0.4);

    return GestureDetector(
      onTap: isEnabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: effectiveColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: effectiveColor,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: FontUtils.poppins(
                fontSize: 12,
                color: effectiveColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
