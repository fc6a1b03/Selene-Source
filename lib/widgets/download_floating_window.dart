import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/main.dart';
import 'package:selene/models/download_task_persistent.dart';
import 'package:selene/screens/download_manager_screen.dart';
import 'package:selene/services/advanced_download_manager.dart';
import 'package:selene/services/background_download_service.dart';
import 'package:selene/utils/font_utils.dart';

/// 下载进度浮窗
///
/// 显示在应用界面上方，展示当前下载进度
/// 支持功能：
/// - 单击：显示/隐藏详情
/// - 双击：进入下载管理页面
/// - 暂停/继续：控制所有下载任务
/// - 隐藏：临时隐藏浮窗（可从下载管理页面重新打开）
class DownloadFloatingWindow extends StatefulWidget {
  final Widget child;

  const DownloadFloatingWindow({
    super.key,
    required this.child,
  });

  @override
  State<DownloadFloatingWindow> createState() => _DownloadFloatingWindowState();
}

class _DownloadFloatingWindowState extends State<DownloadFloatingWindow>
    with SingleTickerProviderStateMixin {
  late final DownloadFloatingWindowController _controller;

  @override
  void initState() {
    super.initState();
    _controller = DownloadFloatingWindowController();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _controller,
      child: Stack(
        children: [
          widget.child,
          const _FloatingWindowWidget(),
        ],
      ),
    );
  }
}

/// 浮窗部件
///
/// 两种显示模式：
/// 1. 完整浮窗 - 显示下载详情和控制按钮
/// 2. 侧边栏指示器 - 用户手动隐藏后显示的小图标
class _FloatingWindowWidget extends StatelessWidget {
  const _FloatingWindowWidget();

  @override
  Widget build(BuildContext context) {
    return Consumer<DownloadFloatingWindowController>(
      builder: (context, controller, _) {
        // 没有活动任务，什么都不显示
        if (controller.activeTasks.isEmpty) {
          return const SizedBox.shrink();
        }

        // 用户手动隐藏了，显示侧边栏小指示器
        if (controller.isManuallyHidden && !controller.isVisible) {
          return _buildSideIndicator(context, controller);
        }

        // 正常显示完整浮窗
        if (controller.isVisible) {
          return _buildMainWindow(context, controller);
        }

        return const SizedBox.shrink();
      },
    );
  }

  /// 构建侧边栏小指示器
  Widget _buildSideIndicator(
    BuildContext context,
    DownloadFloatingWindowController controller,
  ) {
    return Positioned(
      right: 0,
      bottom: 100 + MediaQuery.of(context).padding.bottom,
      child: GestureDetector(
        onTap: () => controller.showFromIndicator(),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: AppAnimations.normal,
            curve: Curves.easeInOut,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
            decoration: BoxDecoration(
              gradient: AppColors.primaryGradient,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                bottomLeft: Radius.circular(12),
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 8,
                  offset: const Offset(-2, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 下载图标
                const Icon(
                  LucideIcons.download,
                  size: 16,
                  color: Colors.white,
                ),
                const SizedBox(height: 4),
                // 任务数量
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${controller.activeTasks.length}',
                    style: FontUtils.poppins(
                      fontSize: 10,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建完整浮窗
  Widget _buildMainWindow(
    BuildContext context,
    DownloadFloatingWindowController controller,
  ) {
    return Positioned(
      right: 16,
      bottom: 100 + MediaQuery.of(context).padding.bottom,
      child: GestureDetector(
        onDoubleTap: _openDownloadManager,
        child: AnimatedContainer(
          duration: AppAnimations.normal,
          curve: Curves.easeInOut,
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => controller.toggleExpanded(),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 主行 - 进度和信息
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 进度指示器
                        SizedBox(
                          width: 28,
                          height: 28,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: controller.activeTasks.length == 1
                                    ? controller.activeTasks.first.progress
                                    : null,
                                strokeWidth: 2.5,
                                backgroundColor:
                                    Colors.white.withValues(alpha: 0.2),
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                              if (controller.activeTasks.length > 1)
                                Text(
                                  '${controller.activeTasks.length}',
                                  style: FontUtils.poppins(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        // 信息
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              controller.activeTasks.length == 1
                                  ? _getShortTitle(controller.activeTasks.first)
                                  : '${controller.activeTasks.length} 个任务下载中',
                              style: FontUtils.poppins(
                                fontSize: 13,
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              controller.statistics.formattedCurrentSpeed,
                              style: FontUtils.poppins(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 12),
                        // 控制按钮组
                        _buildControlButtons(context, controller),
                      ],
                    ),
                    // 展开时显示的任务列表
                    if (controller.isExpanded &&
                        controller.activeTasks.length > 1)
                      _buildExpandedTaskList(context, controller),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControlButtons(
    BuildContext context,
    DownloadFloatingWindowController controller,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 暂停/继续所有任务按钮
        _buildIconButton(
          icon: controller.isAllPaused ? LucideIcons.play : LucideIcons.pause,
          onTap: () => controller.toggleAllDownloads(),
          tooltip: controller.isAllPaused ? '继续所有' : '暂停所有',
        ),
        const SizedBox(width: 6),
        // 最小化到侧边栏按钮
        _buildIconButton(
          icon: LucideIcons.panelRightOpen,
          onTap: () => controller.hide(),
          tooltip: '最小化到侧边栏',
        ),
        const SizedBox(width: 6),
        // 进入下载管理按钮
        _buildIconButton(
          icon: LucideIcons.externalLink,
          onTap: _openDownloadManager,
          tooltip: '打开下载管理',
        ),
      ],
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    // 使用 InkWell 替代 Tooltip + GestureDetector
    // 避免 Overlay 问题，同时保留 tooltip 功能
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 14,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildExpandedTaskList(
    BuildContext context,
    DownloadFloatingWindowController controller,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: Colors.white.withValues(alpha: 0.2),
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: controller.activeTasks.take(3).map((task) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    value: task.progress > 0 ? task.progress : null,
                    strokeWidth: 2,
                    backgroundColor: Colors.white.withValues(alpha: 0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 180),
                  child: Text(
                    task.videoTitle ?? task.fileName,
                    style: FontUtils.poppins(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(task.progress * 100).toStringAsFixed(0)}%',
                  style: FontUtils.poppins(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  String _getShortTitle(DownloadTaskPersistent task) {
    final title = task.videoTitle ?? task.fileName;
    if (title.length <= 15) return title;
    return '${title.substring(0, 12)}...';
  }

  void _openDownloadManager() {
    // 隐藏浮窗
    final controller = Provider.of<DownloadFloatingWindowController>(
      navigatorKey.currentContext!,
      listen: false,
    );
    controller.hide();

    // 使用全局 navigatorKey 打开下载管理页面
    navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (context) => const DownloadManagerScreen(),
      ),
    );
  }
}

/// 下载进度浮窗控制器
class DownloadFloatingWindowController extends ChangeNotifier {
  bool _isVisible = false;
  bool _isExpanded = false;
  bool _isManuallyHidden = false; // 用户是否手动隐藏
  DownloadStatistics _statistics = const DownloadStatistics();
  List<DownloadTaskPersistent> _activeTasks = [];

  bool get isVisible => _isVisible;
  bool get isExpanded => _isExpanded;
  bool get isManuallyHidden => _isManuallyHidden;
  DownloadStatistics get statistics => _statistics;
  List<DownloadTaskPersistent> get activeTasks => _activeTasks;
  bool get hasActiveTasks => _activeTasks.isNotEmpty;

  /// 检查所有活动任务是否都已暂停
  bool get isAllPaused {
    if (_activeTasks.isEmpty) return false;
    // 所有任务都是暂停状态才算全部暂停
    return _activeTasks
        .every((t) => t.status == DownloadTaskPersistentStatus.paused);
  }

  StreamSubscription<DownloadStatistics>? _statsSubscription;
  Timer? _updateTimer;

  void initialize() {
    final manager = AdvancedDownloadManager();

    _statsSubscription = manager.statisticsStream.listen((stats) {
      _statistics = stats;
      _updateActiveTasks();
    });

    // 定期更新活动任务列表
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateActiveTasks();
    });

    // 初始化后台下载服务
    BackgroundDownloadService().initialize();
  }

  void _updateActiveTasks() {
    final manager = AdvancedDownloadManager();
    final allTasks = manager.getAllTasks();

    // 修复：包含下载中和暂停的任务
    _activeTasks = allTasks.where((task) {
      return task.status == DownloadTaskPersistentStatus.downloading ||
          task.status == DownloadTaskPersistentStatus.paused;
    }).toList();

    // 自动显示/隐藏（但尊重用户手动隐藏的选择）
    if (_activeTasks.isNotEmpty && !_isVisible && !_isManuallyHidden) {
      // 有新任务且不是手动隐藏，自动显示
      show();
    } else if (_activeTasks.isEmpty && _isVisible) {
      // 没有任务了，自动隐藏并重置手动隐藏标志
      Future.delayed(const Duration(seconds: 3), () {
        if (_activeTasks.isEmpty) {
          hide();
          _isManuallyHidden = false; // 重置手动隐藏标志
        }
      });
    }

    notifyListeners();
  }

  void show() {
    if (_isVisible) return;
    _isVisible = true;
    notifyListeners();
  }

  void hide() {
    if (!_isVisible) return;
    _isVisible = false;
    _isExpanded = false;
    _isManuallyHidden = true; // 标记为手动隐藏
    notifyListeners();
  }

  /// 从侧边栏指示器恢复显示
  void showFromIndicator() {
    _isManuallyHidden = false; // 清除手动隐藏标志
    show();
  }

  void toggle() {
    _isVisible = !_isVisible;
    if (!_isVisible) _isExpanded = false;
    notifyListeners();
  }

  void toggleExpanded() {
    _isExpanded = !_isExpanded;
    notifyListeners();
  }

  /// 暂停/继续所有下载任务
  Future<void> toggleAllDownloads() async {
    final manager = AdvancedDownloadManager();

    debugPrint(
        '[浮窗] toggleAllDownloads: isAllPaused=$isAllPaused, 任务数=${_activeTasks.length}');

    if (isAllPaused) {
      // 继续所有暂停的任务
      for (final task in _activeTasks) {
        if (task.canResume) {
          debugPrint('[浮窗] 恢复任务: ${task.id} - ${task.fileName}');
          await manager.resumeDownload(task.id);
        }
      }
    } else {
      // 暂停所有下载中的任务
      for (final task in _activeTasks) {
        if (task.canPause) {
          debugPrint('[浮窗] 暂停任务: ${task.id} - ${task.fileName}');
          await manager.pauseDownload(task.id);
        }
      }
    }

    // 延迟刷新任务列表，等待 Isolate 处理完成并更新状态
    // 避免状态竞争导致 UI 显示错误
    Future.delayed(const Duration(milliseconds: 500), () {
      _updateActiveTasks();
    });
  }

  @override
  void dispose() {
    _statsSubscription?.cancel();
    _updateTimer?.cancel();
    super.dispose();
  }
}

/// 迷你下载进度条
///
/// 可嵌入到其他页面的紧凑版本
class MiniDownloadProgress extends StatelessWidget {
  final String? taskId;

  const MiniDownloadProgress({
    super.key,
    this.taskId,
  });

  @override
  Widget build(BuildContext context) {
    if (taskId == null) {
      return _buildGlobalProgress();
    }

    return _buildTaskProgress(taskId!);
  }

  Widget _buildGlobalProgress() {
    return StreamBuilder<DownloadStatistics>(
      stream: AdvancedDownloadManager().statisticsStream,
      initialData: const DownloadStatistics(),
      builder: (context, snapshot) {
        final stats = snapshot.data!;

        if (stats.downloadingTasks == 0) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface(isDark: true),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${stats.downloadingTasks} 个下载',
                style: FontUtils.poppins(
                  fontSize: 12,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${stats.formattedCurrentSpeed})',
                style: FontUtils.poppins(
                  fontSize: 11,
                  color: AppColors.textSecondary(isDark: true),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTaskProgress(String taskId) {
    return StreamBuilder<DownloadTaskProgressEvent>(
      stream: AdvancedDownloadManager().getTaskProgressStream(taskId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final progress = snapshot.data!;

        if (progress.status != DownloadTaskPersistentStatus.downloading) {
          return const SizedBox.shrink();
        }

        return Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface(isDark: true),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress.progress,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(progress.progress * 100).toStringAsFixed(0)}%',
                style: FontUtils.poppins(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '(${DownloadTaskPersistent.formatSpeed(progress.speed)})',
                style: FontUtils.poppins(
                  fontSize: 11,
                  color: AppColors.textSecondary(isDark: true),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
