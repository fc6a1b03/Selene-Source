import 'package:flutter/material.dart';
import 'package:flutter_uvc_camera/flutter_uvc_camera.dart';
import 'package:provider/provider.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/services/usb_capture_channel.dart';
import 'package:selene/services/usb_capture_service.dart';

/// USB 摄像头预览页面
/// 使用 flutter_uvc_camera 插件 v0.0.4 (基于 AndroidUSBCamera 3.x)
///
/// 功能：
/// - 实时预览
/// - 拍照/录像
/// - 视频流采集
/// - 分辨率切换
class UVCCameraScreen extends StatefulWidget {
  const UVCCameraScreen({super.key});

  @override
  State<UVCCameraScreen> createState() => _UVCCameraScreenState();
}

class _UVCCameraScreenState extends State<UVCCameraScreen> {
  UVCCameraController? _cameraController;
  bool _isCameraOpen = false;
  bool _isRecording = false;
  bool _isStreaming = false;
  String? _statusMessage;
  bool _isInitializing = true;
  String? _errorMessage;

  // 可用分辨率
  List<PreviewSize> _previewSizes = [];
  PreviewSize? _currentResolution;

  @override
  void initState() {
    super.initState();
    // 延迟初始化，确保页面已构建完成
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _safeInitialize();
    });
  }

  /// 安全初始化
  void _safeInitialize() {
    if (!mounted) return;

    try {
      _cameraController = UVCCameraController();
      _setupCallbacks();
      _initializeCamera();
    } catch (e) {
      debugPrint('UVCCameraScreen: 初始化失败: $e');
      if (mounted) {
        setState(() {
          _errorMessage = '初始化失败: $e';
          _statusMessage = '初始化失败';
          _isInitializing = false;
        });
      }
    }
  }

  /// 初始化摄像头
  Future<void> _initializeCamera() async {
    if (!mounted) return;

    setState(() {
      _isInitializing = true;
      _statusMessage = '正在初始化...';
    });

    try {
      // 检查是否有 USB 设备
      final devices = await UsbCaptureChannel.getAllUsbDevices();
      final captureCards =
          devices.where((d) => d['isCaptureCard'] == true).toList();

      if (!mounted) return;

      if (captureCards.isEmpty) {
        setState(() {
          _errorMessage = '未检测到 USB 采集卡';
          _statusMessage = '未检测到 USB 采集卡';
          _isInitializing = false;
        });
        return;
      }

      // 显示检测到的设备
      final device = captureCards.first;
      final hasPermission = device['hasPermission'] as bool? ?? false;

      setState(() {
        _statusMessage =
            '检测到: ${device['productName']}\n权限状态: ${hasPermission ? '已授权' : '未授权'}';
      });

      // 如果没有权限，先请求权限
      if (!hasPermission) {
        setState(() {
          _statusMessage = '正在请求 USB 权限...';
        });

        final permissionGranted = await UsbCaptureChannel.requestUsbPermission(
          deviceId: device['deviceId'] as int?,
        );

        if (!mounted) return;

        if (!permissionGranted) {
          setState(() {
            _errorMessage = '需要 USB 权限才能访问摄像头\n请重新插拔设备并授权';
            _statusMessage = '等待 USB 权限授权...';
            _isInitializing = false;
          });

          // 显示权限提示
          if (mounted) {
            _showPermissionDialog();
          }
          return;
        }
      }

      // 延迟一下确保权限已生效
      await Future<void>.delayed(const Duration(milliseconds: 500));

      // 自动打开摄像头
      if (mounted) {
        await _openCamera();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '初始化失败: $e';
        _statusMessage = '初始化失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  /// 显示权限提示对话框
  void _showPermissionDialog() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('需要 USB 权限'),
        content: const Text(
          '访问 USB 摄像头需要您的授权。\n\n'
          '方法一（推荐）:\n'
          '1. 完全退出应用\n'
          '2. 重新插拔 USB 采集卡\n'
          '3. 在系统弹出的对话框中选择本应用\n'
          '4. 勾选"默认使用此应用"\n\n'
          '方法二:\n'
          '点击下方"尝试获取权限"按钮',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _waitForPermission();
            },
            child: const Text('尝试获取权限'),
          ),
        ],
      ),
    );
  }

  /// 等待用户授权（轮询检查）
  Future<void> _waitForPermission() async {
    setState(() {
      _statusMessage = '等待授权中...';
      _isInitializing = true;
    });

    // 轮询检查权限，最多等待 10 秒
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));

      final devices = await UsbCaptureChannel.getAllUsbDevices();
      final captureCards =
          devices.where((d) => d['isCaptureCard'] == true).toList();

      if (captureCards.isNotEmpty) {
        final device = captureCards.first;
        final hasPermission = device['hasPermission'] as bool? ?? false;

        if (hasPermission) {
          // 已获得权限
          if (mounted) {
            await _initializeCamera();
          }
          return;
        }
      }

      setState(() {
        _statusMessage = '等待授权中... (${(i + 1) * 0.5}s)';
      });
    }

    // 超时
    setState(() {
      _errorMessage = '等待权限超时\n请确保已点击系统弹出的权限对话框';
      _statusMessage = '等待权限超时';
      _isInitializing = false;
    });

    if (mounted) {
      _showTimeoutDialog();
    }
  }

  /// 显示超时对话框
  void _showTimeoutDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('权限获取失败'),
        content: const Text(
          '未能获取 USB 权限。可能的原因:\n\n'
          '1. 系统没有弹出权限对话框\n'
          '2. 用户拒绝了权限请求\n\n'
          '建议:\n'
          '• 重新插拔 USB 设备\n'
          '• 检查应用是否有 USB 权限\n'
          '• 尝试重启应用',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  /// 打开摄像头
  Future<void> _openCamera() async {
    setState(() {
      _statusMessage = '正在打开摄像头...';
    });

    try {
      // 检查 USB 权限
      final devices = await UsbCaptureChannel.getAllUsbDevices();
      final captureCards =
          devices.where((d) => d['isCaptureCard'] == true).toList();

      if (captureCards.isEmpty) {
        setState(() {
          _errorMessage = '未检测到 USB 采集卡';
          _statusMessage = '未检测到 USB 采集卡';
        });
        return;
      }

      // 尝试打开摄像头
      debugPrint('UVCCameraScreen: 正在打开 UVCCamera...');
      await _cameraController?.openUVCCamera();
      debugPrint('UVCCameraScreen: UVCCamera 打开成功');
    } catch (e) {
      debugPrint('UVCCameraScreen: 打开摄像头失败: $e');
      setState(() {
        _errorMessage = '打开摄像头失败: $e';
        _statusMessage = '打开失败: $e';
      });

      // 显示错误提示
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('打开摄像头失败: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: '重试',
              onPressed: _openCamera,
              textColor: Colors.white,
            ),
          ),
        );
      }
    }
  }

  /// 设置回调
  void _setupCallbacks() {
    // 摄像头状态回调
    _cameraController?.cameraStateCallback = (state) {
      if (!mounted) return;
      setState(() {
        _isCameraOpen = state == UVCCameraState.opened;
        _statusMessage = '摄像头状态: ${_getStateText(state)}';
      });

      // 摄像头打开后获取分辨率列表
      if (state == UVCCameraState.opened) {
        _loadPreviewSizes();
      }
    };

    // 消息回调
    _cameraController?.msgCallback = (msg) {
      if (!mounted) return;
      setState(() {
        _statusMessage = msg;
      });
    };

    // 物理拍照按钮回调 (部分摄像头支持)
    _cameraController?.clickTakePictureButtonCallback = (String path) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('通过物理按钮拍照: $path')),
      );
    };
  }

  String _getStateText(UVCCameraState state) {
    switch (state) {
      case UVCCameraState.opened:
        return '已打开';
      case UVCCameraState.closed:
        return '已关闭';
      case UVCCameraState.error:
        return '错误';
    }
  }

  /// 获取可用的预览分辨率
  Future<void> _loadPreviewSizes() async {
    try {
      final sizes =
          await _cameraController?.getAllPreviewSizes() ?? <PreviewSize>[];
      if (!mounted) return;
      setState(() {
        _previewSizes = sizes;
        if (sizes.isNotEmpty) {
          _currentResolution = sizes.first;
        }
      });
    } catch (e) {
      debugPrint('获取分辨率列表失败: $e');
    }
  }

  @override
  void dispose() {
    try {
      _cameraController?.closeCamera();
      _cameraController?.dispose();
    } catch (e) {
      debugPrint('UVCCameraScreen: dispose 错误: $e');
    }
    super.dispose();
  }

  /// 拍照
  Future<void> _takePicture() async {
    try {
      final path = await _cameraController?.takePicture();
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('照片已保存: $path')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('拍照失败: $e')),
        );
      }
    }
  }

  /// 切换录像
  Future<void> _toggleRecording() async {
    try {
      if (_isRecording) {
        final path = await _cameraController?.captureVideo();
        setState(() => _isRecording = false);
        if (path != null && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('视频已保存: $path')),
          );
        }
      } else {
        await _cameraController?.captureVideo();
        setState(() => _isRecording = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('录像失败: $e')),
        );
      }
    }
  }

  /// 切换推流
  void _toggleStreaming() {
    try {
      if (_isStreaming) {
        _cameraController?.captureStreamStop();
        setState(() => _isStreaming = false);
      } else {
        _cameraController?.captureStreamStart();
        setState(() => _isStreaming = true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('推流失败: $e')),
        );
      }
    }
  }

  /// 更新分辨率
  void _updateResolution(PreviewSize size) {
    try {
      _cameraController?.updateResolution(size);
      setState(() => _currentResolution = size);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('切换分辨率失败: $e')),
      );
    }
  }

  /// 显示分辨率选择对话框
  void _showResolutionDialog() {
    if (_previewSizes.isEmpty) return;

    showModalBottomSheet<void>(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '选择分辨率',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ..._previewSizes.map((size) => ListTile(
                  title: Text('${size.width}x${size.height}'),
                  trailing: _currentResolution?.width == size.width &&
                          _currentResolution?.height == size.height
                      ? const Icon(Icons.check, color: Colors.green)
                      : null,
                  onTap: () {
                    _updateResolution(size);
                    Navigator.pop(context);
                  },
                )),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('USB 摄像头'),
        backgroundColor: AppColors.primary,
        actions: [
          // 刷新按钮
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isInitializing ? null : _initializeCamera,
            tooltip: '刷新',
          ),
          // 分辨率切换按钮
          IconButton(
            icon: const Icon(Icons.aspect_ratio),
            onPressed: (_isCameraOpen && _previewSizes.isNotEmpty)
                ? _showResolutionDialog
                : null,
            tooltip: '分辨率',
          ),
        ],
      ),
      body: Column(
        children: [
          // 状态栏
          if (_statusMessage != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              color: AppColors.primary.withValues(alpha: 0.1),
              child: Text(
                _statusMessage!,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // 录像/推流状态
          if (_isRecording || _isStreaming)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              color: _isRecording
                  ? Colors.red.withValues(alpha: 0.2)
                  : Colors.blue.withValues(alpha: 0.2),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isRecording) ...[
                    const Icon(Icons.fiber_manual_record,
                        color: Colors.red, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      '录制中',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  if (_isStreaming) ...[
                    const Icon(Icons.wifi_tethering,
                        color: Colors.blue, size: 16),
                    const SizedBox(width: 8),
                    const Text(
                      '推流中',
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // 当前分辨率显示
          if (_currentResolution != null)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '分辨率: ${_currentResolution!.width}x${_currentResolution!.height}',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ),

          // 摄像头预览区域
          Expanded(
            child: Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(12),
                boxShadow: AppShadows.medium,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: _isCameraOpen && _cameraController != null
                    ? UVCCameraView(
                        cameraController: _cameraController!,
                        width: double.infinity,
                        height: double.infinity,
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_isInitializing)
                              const CircularProgressIndicator(
                                color: Colors.white,
                              )
                            else
                              const Icon(
                                Icons.videocam_off,
                                size: 64,
                                color: Colors.white54,
                              ),
                            const SizedBox(height: 16),
                            Text(
                              _isInitializing
                                  ? '正在初始化...'
                                  : (_errorMessage ?? '摄像头未打开'),
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 16,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (_errorMessage != null) ...[
                              const SizedBox(height: 16),
                              ElevatedButton.icon(
                                onPressed: _initializeCamera,
                                icon: const Icon(Icons.refresh),
                                label: const Text('重新初始化'),
                              ),
                            ],
                          ],
                        ),
                      ),
              ),
            ),
          ),

          // 设备信息
          Consumer<UsbCaptureService>(
            builder: (context, service, child) {
              final device = service.connectedDevice;
              if (device == null) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    '未检测到 USB 采集卡',
                    style: TextStyle(color: Colors.grey),
                  ),
                );
              }
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color:
                      isDark ? AppColors.darkSurface : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.videocam,
                      color: AppColors.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            device.productName ?? 'USB 采集卡',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'VID: 0x${device.vid.toRadixString(16).toUpperCase().padLeft(4, '0')} | '
                            'PID: 0x${device.pid.toRadixString(16).toUpperCase().padLeft(4, '0')}',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          // 控制按钮
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                // 打开/关闭摄像头
                _ControlButton(
                  icon: _isCameraOpen ? Icons.videocam_off : Icons.videocam,
                  label: _isCameraOpen ? '关闭' : '打开',
                  color: _isCameraOpen ? Colors.red : AppColors.primary,
                  onPressed: _isInitializing
                      ? null
                      : () {
                          if (_isCameraOpen) {
                            _cameraController?.closeCamera();
                          } else {
                            _openCamera();
                          }
                        },
                ),

                // 拍照
                _ControlButton(
                  icon: Icons.camera_alt,
                  label: '拍照',
                  color: Colors.blue,
                  onPressed: _isCameraOpen ? _takePicture : null,
                ),

                // 录像
                _ControlButton(
                  icon: _isRecording ? Icons.stop : Icons.videocam,
                  label: _isRecording ? '停止' : '录像',
                  color: _isRecording ? Colors.red : Colors.orange,
                  onPressed: _isCameraOpen ? _toggleRecording : null,
                ),

                // 推流
                _ControlButton(
                  icon: _isStreaming
                      ? Icons.wifi_tethering_off
                      : Icons.wifi_tethering,
                  label: _isStreaming ? '停止推流' : '开始推流',
                  color: _isStreaming ? Colors.purple : Colors.indigo,
                  onPressed: _isCameraOpen ? _toggleStreaming : null,
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ControlButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: onPressed != null ? color : Colors.grey,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: onPressed != null ? Colors.white : Colors.grey,
          ),
        ),
      ],
    );
  }
}
