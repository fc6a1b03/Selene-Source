import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_uvc_camera/flutter_uvc_camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/services/usb_capture_channel.dart';
import 'package:selene/services/usb_capture_service.dart';

/// USB 摄像头预览页面
/// 使用 flutter_uvc_camera 插件进行应用内 UVC 预览
class UVCCameraScreen extends StatefulWidget {
  const UVCCameraScreen({super.key});

  @override
  State<UVCCameraScreen> createState() => _UVCCameraScreenState();
}

class _UVCCameraScreenState extends State<UVCCameraScreen> {
  UVCCameraController? _cameraController;
  bool _isInitializing = true;
  bool _isOpeningCamera = false;
  bool _isCameraOpen = false;
  bool _isRecording = false;
  bool _isStoppingRecording = false;
  bool _isFullscreen = false;
  Future<String?>? _recordingSessionFuture;

  String? _statusMessage;
  String? _errorMessage;

  List<PreviewSize> _previewSizes = <PreviewSize>[];
  PreviewSize? _currentResolution;

  DateTime _lastStatusUpdate = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _cameraController = UVCCameraController();
    _setupCallbacks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initializeCamera(autoOpen: true));
    });
  }

  @override
  void dispose() {
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    unawaited(SystemChrome.setPreferredOrientations(DeviceOrientation.values));
    try {
      _cameraController?.closeCamera();
      _cameraController?.dispose();
    } catch (e) {
      debugPrint('UVCCameraScreen: dispose error: $e');
    }
    super.dispose();
  }

  Future<void> _initializeCamera({required bool autoOpen}) async {
    if (!mounted) return;
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
      _statusMessage = '正在初始化 USB 摄像头...';
    });

    try {
      final Map<dynamic, dynamic>? card = await _getPrimaryCaptureCard();
      if (card == null) {
        setState(() {
          _errorMessage = '未检测到 USB 采集卡';
          _statusMessage = '请先连接采集卡';
        });
        return;
      }

      final bool runtimeReady = await _ensureRuntimePermissions();
      if (!runtimeReady) {
        setState(() {
          _errorMessage = '缺少相机或麦克风权限';
          _statusMessage = '请在系统设置中授权后重试';
        });
        return;
      }

      final bool usbReady = await _ensureUsbPermission(card);
      if (!usbReady) {
        setState(() {
          _errorMessage = '未获得 USB 权限';
          _statusMessage = '请重新插拔设备并允许访问';
        });
        return;
      }

      _updateStatusMessage('设备就绪，${autoOpen ? '正在自动打开预览...' : '点击下方打开预览'}');
      if (autoOpen) {
        await _openCamera();
      }
    } catch (e) {
      setState(() {
        _errorMessage = '初始化失败: $e';
        _statusMessage = '初始化失败';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    }
  }

  Future<Map<dynamic, dynamic>?> _getPrimaryCaptureCard() async {
    final List<Map<dynamic, dynamic>> devices =
        await UsbCaptureChannel.getAllUsbDevices();
    final List<Map<dynamic, dynamic>> cards = devices
        .where((Map<dynamic, dynamic> d) => d['isCaptureCard'] == true)
        .toList();
    if (cards.isEmpty) {
      return null;
    }
    cards.sort((Map<dynamic, dynamic> a, Map<dynamic, dynamic> b) {
      final bool ap = a['hasPermission'] as bool? ?? false;
      final bool bp = b['hasPermission'] as bool? ?? false;
      return ap == bp ? 0 : (ap ? -1 : 1);
    });
    return cards.first;
  }

  Future<bool> _ensureRuntimePermissions() async {
    final PermissionStatus cameraStatus = await Permission.camera.request();
    final PermissionStatus micStatus = await Permission.microphone.request();
    return cameraStatus.isGranted && micStatus.isGranted;
  }

  Future<bool> _ensureUsbPermission(Map<dynamic, dynamic> card) async {
    final bool hasPermission = card['hasPermission'] as bool? ?? false;
    if (hasPermission) return true;

    _updateStatusMessage('正在请求 USB 权限...');
    await UsbCaptureChannel.requestUsbPermission(
      deviceId: card['deviceId'] as int?,
    );
    return _waitUsbPermission(
      deviceId: card['deviceId'] as int?,
      timeout: const Duration(seconds: 12),
    );
  }

  Future<bool> _waitUsbPermission({
    required int? deviceId,
    required Duration timeout,
  }) async {
    final DateTime started = DateTime.now();
    while (mounted && DateTime.now().difference(started) < timeout) {
      final List<Map<dynamic, dynamic>> devices =
          await UsbCaptureChannel.getAllUsbDevices();
      final Map<dynamic, dynamic> target = devices.firstWhere(
        (Map<dynamic, dynamic> d) =>
            d['isCaptureCard'] == true &&
            (deviceId == null || d['deviceId'] == deviceId),
        orElse: () => <dynamic, dynamic>{},
      );
      if (target.isNotEmpty) {
        final bool granted = target['hasPermission'] as bool? ?? false;
        if (granted) {
          _updateStatusMessage('USB 权限已获得');
          return true;
        }
      }
      final double elapsed =
          DateTime.now().difference(started).inMilliseconds / 1000;
      _updateStatusMessage('等待 USB 授权... ${elapsed.toStringAsFixed(1)}s');
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return false;
  }

  Future<void> _openCamera() async {
    if (_isOpeningCamera) return;
    setState(() {
      _isOpeningCamera = true;
      _errorMessage = null;
      _statusMessage = '正在打开摄像头...';
    });

    try {
      final Map<dynamic, dynamic>? card = await _getPrimaryCaptureCard();
      if (card == null) {
        setState(() {
          _errorMessage = '未检测到 USB 采集卡';
          _statusMessage = '请先连接采集卡';
        });
        return;
      }

      final bool usbReady = await _ensureUsbPermission(card);
      if (!usbReady) {
        setState(() {
          _errorMessage = '未获取 USB 权限';
          _statusMessage = '无法打开摄像头';
        });
        return;
      }

      final Future<void>? openFuture = _cameraController?.openUVCCamera();
      if (openFuture != null) {
        unawaited(
          openFuture.catchError((Object e, StackTrace s) {
            debugPrint('UVCCameraScreen: openUVCCamera 异步错误: $e');
          }),
        );
      }

      bool opened = await _waitCameraOpened(
        timeout: const Duration(seconds: 12),
      );

      // 某些机型回调不稳定：二次检查分辨率列表作为“已打开”兜底信号
      if (!opened) {
        final List<PreviewSize> fallbackSizes =
            await _readPreviewSizesFromController();
        if (fallbackSizes.isNotEmpty) {
          opened = true;
          if (mounted) {
            setState(() {
              _isCameraOpen = true;
              _previewSizes = fallbackSizes;
            });
          }
        }
      }

      if (!opened) {
        throw TimeoutException('摄像头未进入 opened 状态');
      }

      await _loadPreviewSizesAndApplyPreferred();
      _updateStatusMessage('预览已开启');
    } on TimeoutException {
      setState(() {
        _errorMessage = '打开超时，设备可能未完成初始化';
        _statusMessage = '请点击“打开”重试';
      });
    } catch (e) {
      setState(() {
        _errorMessage = '打开失败: $e';
        _statusMessage = '打开失败';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('打开摄像头失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningCamera = false;
        });
      } else {
        _isOpeningCamera = false;
      }
    }
  }

  Future<bool> _waitCameraOpened({required Duration timeout}) async {
    final DateTime started = DateTime.now();
    while (DateTime.now().difference(started) < timeout) {
      if (_isCameraOpen) return true;
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    return _isCameraOpen;
  }

  Future<List<PreviewSize>> _readPreviewSizesFromController() async {
    await _cameraController?.getAllPreviewSizes();
    return List<PreviewSize>.from(
      _cameraController?.getPreviewSizes ?? <PreviewSize>[],
    );
  }

  void _closeCamera() {
    try {
      _cameraController?.closeCamera();
      setState(() {
        _isCameraOpen = false;
        _statusMessage = '摄像头已关闭';
      });
    } catch (e) {
      setState(() {
        _errorMessage = '关闭失败: $e';
      });
    }
  }

  void _setupCallbacks() {
    _cameraController?.cameraStateCallback = (UVCCameraState state) {
      if (!mounted) return;
      setState(() {
        _isCameraOpen = state == UVCCameraState.opened;
      });
      _updateStatusMessage('摄像头状态: ${_getStateText(state)}');
      if (state == UVCCameraState.opened) {
        unawaited(_loadPreviewSizesAndApplyPreferred());
      }
    };

    _cameraController?.msgCallback = (String msg) {
      _updateStatusMessage(msg);
    };

    _cameraController?.clickTakePictureButtonCallback = (String path) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('拍照完成: $path')),
      );
    };
  }

  Future<void> _loadPreviewSizesAndApplyPreferred() async {
    try {
      final List<PreviewSize> sizes = await _readPreviewSizesFromController();
      if (!mounted) return;
      if (sizes.isEmpty) {
        _updateStatusMessage('未获取到可用分辨率');
      }

      final PreviewSize? preferred = _pickPreferredResolution(sizes);
      setState(() {
        _previewSizes = sizes;
        _currentResolution = preferred;
      });

      if (preferred != null) {
        try {
          _cameraController?.updateResolution(preferred);
          _updateStatusMessage(
            '分辨率: ${preferred.width ?? 0}x${preferred.height ?? 0}',
          );
        } catch (e) {
          debugPrint('UVCCameraScreen: updateResolution failed: $e');
        }
      }
    } catch (e) {
      debugPrint('UVCCameraScreen: load sizes failed: $e');
    }
  }

  PreviewSize? _pickPreferredResolution(List<PreviewSize> sizes) {
    if (sizes.isEmpty) return null;

    PreviewSize? findExact(int width, int height) {
      for (final PreviewSize size in sizes) {
        if ((size.width ?? 0) == width && (size.height ?? 0) == height) {
          return size;
        }
      }
      return null;
    }

    return findExact(1280, 720) ??
        findExact(960, 540) ??
        findExact(854, 480) ??
        findExact(640, 480) ??
        sizes.reduce((PreviewSize a, PreviewSize b) {
          final int targetArea = 1280 * 720;
          final int aArea = (a.width ?? 0) * (a.height ?? 0);
          final int bArea = (b.width ?? 0) * (b.height ?? 0);
          final int aDiff = (aArea - targetArea).abs();
          final int bDiff = (bArea - targetArea).abs();
          return aDiff <= bDiff ? a : b;
        });
  }

  void _updateStatusMessage(
    String message, {
    Duration minInterval = const Duration(milliseconds: 300),
  }) {
    if (!mounted) return;
    if (message.isEmpty) return;
    final DateTime now = DateTime.now();
    if (_statusMessage == message) return;
    if (now.difference(_lastStatusUpdate) < minInterval) return;

    _lastStatusUpdate = now;
    setState(() {
      _statusMessage = message;
    });
  }

  Future<void> _setFullscreen(bool value) async {
    if (!mounted || _isFullscreen == value) return;
    setState(() {
      _isFullscreen = value;
    });
    if (value) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      return;
    }
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _takePicture() async {
    try {
      final String? path = await _cameraController?.takePicture();
      if (!mounted) return;
      if (path != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('照片已保存: $path')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('拍照失败: $e')),
      );
    }
  }

  Future<bool> _ensureRecordingPermissions() async {
    final PermissionStatus micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      return false;
    }

    final PermissionStatus storageStatus = await Permission.storage.request();
    final PermissionStatus videosStatus = await Permission.videos.request();
    return storageStatus.isGranted ||
        storageStatus.isLimited ||
        videosStatus.isGranted ||
        videosStatus.isLimited;
  }

  Future<void> _toggleRecording() async {
    if (_isStoppingRecording) return;
    if (_isRecording) {
      await _stopRecording();
      return;
    }
    await _startRecording();
  }

  Future<void> _startRecording() async {
    final bool permissionReady = await _ensureRecordingPermissions();
    if (!permissionReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('录像权限不足，请授予麦克风和存储权限')),
      );
      return;
    }

    setState(() {
      _isRecording = true;
      _isStoppingRecording = false;
      _errorMessage = null;
    });
    _updateStatusMessage('开始录像...');

    final Future<String?>? sessionFuture = _cameraController?.captureVideo();
    if (sessionFuture == null) {
      _handleRecordingFailure('录像失败：控制器不可用');
      return;
    }
    _recordingSessionFuture = sessionFuture;

    unawaited(
      sessionFuture.then((String? path) {
        if (!mounted) return;
        setState(() {
          _isRecording = false;
          _isStoppingRecording = false;
          if (_recordingSessionFuture == sessionFuture) {
            _recordingSessionFuture = null;
          }
        });

        if (path == null || path.isEmpty) {
          _updateStatusMessage('录像已停止');
          return;
        }
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('视频已保存: $path')));
      }).catchError((Object error) {
        final String message = '录像失败: $error';
        _handleRecordingFailure(message);
      }),
    );
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    setState(() {
      _isStoppingRecording = true;
    });
    _updateStatusMessage('正在停止录像...');

    final Future<String?>? stopFuture = _cameraController?.captureVideo();
    if (stopFuture == null) {
      if (mounted) {
        setState(() {
          _isStoppingRecording = false;
        });
      }
      return;
    }

    // 插件通过再次调用 captureVideo() 触发停止。
    // 此次 Future 可能没有返回结果，因此只做兜底错误日志。
    unawaited(
      stopFuture.catchError((Object error) {
        debugPrint('UVCCameraScreen: stop recording call failed: $error');
        return null;
      }),
    );
  }

  void _handleRecordingFailure(String message) {
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isStoppingRecording = false;
      _recordingSessionFuture = null;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
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

  void _showResolutionDialog() {
    if (_previewSizes.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _previewSizes.map((PreviewSize size) {
              final String label = '${size.width ?? 0}x${size.height ?? 0}';
              final bool selected = _currentResolution?.width == size.width &&
                  _currentResolution?.height == size.height;
              return ListTile(
                title: Text(label),
                trailing: selected ? const Icon(Icons.check) : null,
                onTap: () {
                  try {
                    _cameraController?.updateResolution(size);
                    setState(() {
                      _currentResolution = size;
                    });
                    _updateStatusMessage('分辨率: $label');
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('切换分辨率失败: $e')),
                    );
                  }
                  Navigator.of(context).pop();
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildStatusBar() {
    if (_statusMessage == null && _errorMessage == null) {
      return const SizedBox.shrink();
    }

    final bool isError = _errorMessage != null;
    final Color color = isError
        ? Colors.red.withValues(alpha: 0.12)
        : AppColors.primary.withValues(alpha: 0.12);
    final Color textColor = isError ? Colors.red : AppColors.primary;
    final String text = _errorMessage ?? _statusMessage ?? '';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: color,
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildPreviewSurface() {
    final BorderRadius borderRadius = BorderRadius.circular(12);
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: borderRadius,
        boxShadow: AppShadows.medium,
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (_cameraController != null)
              RepaintBoundary(
                child: UVCCameraView(
                  cameraController: _cameraController!,
                  width: double.infinity,
                  height: double.infinity,
                ),
              )
            else
              const SizedBox.shrink(),
            if (_isInitializing || _isOpeningCamera)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            if (!_isInitializing && !_isOpeningCamera && !_isCameraOpen)
              const Center(
                child: Text(
                  '点击“打开”开始预览',
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
            Positioned(
              right: 12,
              bottom: 12,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 4, right: 4),
                child: IconButton.filledTonal(
                  onPressed: () => unawaited(_setFullscreen(!_isFullscreen)),
                  icon: Icon(
                    _isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceInfo(bool isDark) {
    return Consumer<UsbCaptureService>(
      builder:
          (BuildContext context, UsbCaptureService service, Widget? child) {
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
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.videocam, color: AppColors.primary, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      device.productName ?? 'USB 采集卡',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
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
              const Icon(Icons.circle, color: Colors.green, size: 10),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControls() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        color: Colors.transparent,
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          alignment: WrapAlignment.center,
          children: <Widget>[
            _ActionButton(
              icon: _isCameraOpen ? Icons.videocam_off : Icons.videocam,
              label: _isCameraOpen ? '关闭' : '打开',
              color: _isCameraOpen ? Colors.red : AppColors.primary,
              onPressed: (_isInitializing || _isOpeningCamera)
                  ? null
                  : () {
                      if (_isCameraOpen) {
                        _closeCamera();
                      } else {
                        unawaited(_openCamera());
                      }
                    },
            ),
            _ActionButton(
              icon: Icons.camera_alt,
              label: '拍照',
              color: Colors.blue,
              onPressed: _isCameraOpen ? () => unawaited(_takePicture()) : null,
            ),
            _ActionButton(
              icon: _isRecording ? Icons.stop : Icons.videocam,
              label: _isRecording ? '停止' : '录像',
              color: _isRecording ? Colors.red : Colors.orange,
              onPressed: (_isCameraOpen && !_isStoppingRecording)
                  ? () => unawaited(_toggleRecording())
                  : null,
            ),
            _ActionButton(
              icon: Icons.aspect_ratio,
              label: '分辨率',
              color: Colors.teal,
              onPressed: (_isCameraOpen && _previewSizes.isNotEmpty)
                  ? _showResolutionDialog
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        title: const Text('USB 摄像头'),
        backgroundColor: AppColors.primary,
      ),
      body: Column(
        children: <Widget>[
          _buildStatusBar(),
          Expanded(
            child: KeyedSubtree(
              key: const ValueKey<String>('uvc_camera_preview'),
              child: _buildPreviewSurface(),
            ),
          ),
          _buildDeviceInfo(isDark),
          _buildControls(),
        ],
      ),
    );
  }
}

class _ActionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onPressed,
  });

  @override
  State<_ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<_ActionButton> {
  static const Duration _debounceDuration = Duration(milliseconds: 700);
  DateTime _lastTapAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _isLocked = false;

  Future<void> _handleTap() async {
    final VoidCallback? onPressed = widget.onPressed;
    if (onPressed == null || _isLocked) return;

    final DateTime now = DateTime.now();
    if (now.difference(_lastTapAt) < _debounceDuration) {
      return;
    }

    _lastTapAt = now;
    setState(() {
      _isLocked = true;
    });

    try {
      onPressed();
    } finally {
      await Future<void>.delayed(_debounceDuration);
      if (mounted) {
        setState(() {
          _isLocked = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null && !_isLocked;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: enabled ? widget.color : Colors.grey,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: enabled ? () => unawaited(_handleTap()) : null,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 56,
              height: 56,
              child: Icon(widget.icon, color: Colors.white, size: 28),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 11,
            color: enabled ? Colors.white : Colors.grey,
          ),
        ),
      ],
    );
  }
}
