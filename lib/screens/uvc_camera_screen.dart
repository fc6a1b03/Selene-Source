import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:selene/design/design_system.dart';
import 'package:selene/services/usb_capture_channel.dart';
import 'package:selene/services/usb_capture_service.dart';
import 'package:selene/services/uvc_camera_channel.dart';

class UVCCameraScreen extends StatefulWidget {
  const UVCCameraScreen({super.key});

  @override
  State<UVCCameraScreen> createState() => _UVCCameraScreenState();
}

class _UVCCameraScreenState extends State<UVCCameraScreen> {
  UVCCameraController? _cameraController;
  StreamSubscription<UsbCaptureEvent>? _usbEventSubscription;
  int _previewRevision = 0;

  bool _isInitializing = true;
  bool _isOpeningCamera = false;
  bool _isCameraOpen = false;
  bool _isRecording = false;
  bool _isStoppingRecording = false;
  bool _isOverviewExpanded = false;
  bool _isInfoPanelMinimized = true;
  bool _isControlPanelMinimized = false;
  bool _isClosingPage = false;
  bool _didApplyPreferredResolution = false;
  bool _areOverlaysVisible = true;
  bool _isChromeManuallyHidden = false;

  String? _statusMessage;
  String? _errorMessage;
  DateTime _lastStatusUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  PreviewSize? _activePreviewSize;
  PreviewSize? _preferredPreviewSize;

  @override
  void initState() {
    super.initState();
    unawaited(_enterImmersiveMode());
    unawaited(_applyLandscapeOrientation());
    _cameraController = UVCCameraController();
    _setupCallbacks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachUsbDisconnectListener();
      unawaited(_initializeCamera(autoOpen: true));
    });
  }

  @override
  void dispose() {
    debugPrint('UVCCameraScreen: disposing...');
    unawaited(_exitImmersiveMode());
    unawaited(_restoreSystemOrientation());
    _detachUsbDisconnectListener();
    _releaseCameraResources();
    // 清理状态变量
    _activePreviewSize = null;
    _preferredPreviewSize = null;
    _didApplyPreferredResolution = false;
    debugPrint('UVCCameraScreen: disposed');
    super.dispose();
  }

  Future<void> _enterImmersiveMode() {
    return SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  Future<void> _exitImmersiveMode() {
    return SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  }

  Future<void> _applyLandscapeOrientation() {
    return SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  Future<void> _restoreSystemOrientation() {
    return SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  void _attachUsbDisconnectListener() {
    _usbEventSubscription?.cancel();
    _usbEventSubscription = UsbCaptureChannel.eventStream.listen((
      UsbCaptureEvent event,
    ) {
      if (!mounted || _isClosingPage) {
        return;
      }
      if (event.type == UsbCaptureEventType.detached) {
        unawaited(_closePage(returnToHome: true));
      }
    });
  }

  void _detachUsbDisconnectListener() {
    _usbEventSubscription?.cancel();
    _usbEventSubscription = null;
  }

  Future<void> _releaseCameraResourcesAsync() async {
    final UVCCameraController? controller = _cameraController;
    try {
      if (controller != null) {
        await controller.closeCamera();
        await controller.disposePlatformView();
        controller.dispose();
      }
    } catch (e) {
      debugPrint('UVCCameraScreen: release error: $e');
    } finally {
      _cameraController = null;
      _resetScreenState();
    }
  }

  void _releaseCameraResources() {
    final UVCCameraController? controller = _cameraController;
    try {
      controller?.closeCamera();
      unawaited(controller?.disposePlatformView() ?? Future<void>.value());
      controller?.dispose();
    } catch (e) {
      debugPrint('UVCCameraScreen: release error: $e');
    } finally {
      _cameraController = null;
      _resetScreenState();
    }
  }

  void _resetScreenState() {
    _activePreviewSize = null;
    _preferredPreviewSize = null;
    _didApplyPreferredResolution = false;
    _isCameraOpen = false;
    _isOpeningCamera = false;
    _isInitializing = false;
    _isRecording = false;
    _isStoppingRecording = false;
    _isOverviewExpanded = false;
    _isInfoPanelMinimized = true;
    _isControlPanelMinimized = false;
    _areOverlaysVisible = true;
    _isChromeManuallyHidden = false;
    _statusMessage = null;
    _errorMessage = null;
  }

  Future<void> _waitForNextFrame() {
    final Completer<void> completer = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });
    return completer.future;
  }

  void _showOverlays({bool force = false}) {
    if (!mounted) {
      return;
    }
    if (_isChromeManuallyHidden && !force) {
      return;
    }
    if (!_areOverlaysVisible) {
      setState(() => _areOverlaysVisible = true);
    }
  }

  void _toggleOverlays() {
    if (_isChromeManuallyHidden) {
      setState(() {
        _isChromeManuallyHidden = false;
        _areOverlaysVisible = true;
      });
      return;
    }
    _showOverlays();
  }

  void _toggleFloatingWindowsVisibility() {
    setState(() {
      _isChromeManuallyHidden = !_isChromeManuallyHidden;
      _areOverlaysVisible = !_isChromeManuallyHidden;
    });
  }

  Future<void> _closePage({bool returnToHome = false}) async {
    if (_isClosingPage) {
      return;
    }
    _isClosingPage = true;
    _detachUsbDisconnectListener();
    await _releaseCameraResourcesAsync();

    if (mounted) {
      if (returnToHome) {
        Navigator.of(context, rootNavigator: true)
            .popUntil((Route<dynamic> route) => route.isFirst);
      } else {
        Navigator.of(context).pop();
      }
    }
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
      if (card == null) return _setErrorMessage('未检测到 USB 采集卡');
      final bool runtimeReady = await _ensureRuntimePermissions();
      if (!runtimeReady) return _setErrorMessage('缺少相机或麦克风权限');
      final bool usbReady = await _ensureUsbPermission(card);
      if (!usbReady) return _setErrorMessage('未获得 USB 权限');
      _updateStatusMessage(autoOpen ? '设备就绪，正在自动打开预览...' : '设备就绪，请点击打开预览');
      if (autoOpen) await _openCamera();
    } catch (e) {
      _setErrorMessage('初始化失败: $e');
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<Map<dynamic, dynamic>?> _getPrimaryCaptureCard() async {
    final List<Map<dynamic, dynamic>> devices =
        await UsbCaptureChannel.getAllUsbDevices();
    final List<Map<dynamic, dynamic>> cards = devices
        .where((Map<dynamic, dynamic> d) => d['isCaptureCard'] == true)
        .toList();
    if (cards.isEmpty) return null;
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
        deviceId: card['deviceId'] as int?);
    return _waitUsbPermission(
        deviceId: card['deviceId'] as int?,
        timeout: const Duration(seconds: 12));
  }

  Future<bool> _waitUsbPermission(
      {required int? deviceId, required Duration timeout}) async {
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
      if (target.isNotEmpty && (target['hasPermission'] as bool? ?? false)) {
        _updateStatusMessage('USB 权限已获得');
        return true;
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
      if (card == null) return _setErrorMessage('未检测到 USB 采集卡');
      final bool usbReady = await _ensureUsbPermission(card);
      if (!usbReady) return _setErrorMessage('未获得 USB 权限');
      await _cameraController?.openUVCCamera();
      final bool ready =
          await _waitCameraReady(timeout: const Duration(seconds: 15));
      if (!ready) return _setErrorMessage('摄像头初始化较慢，请稍后重试');
      await _syncCameraDetails(applyPreferredResolution: false);
      _updateStatusMessage('预览已开启');
    } catch (e) {
      _setErrorMessage(_normalizeOpenError(e));
    } finally {
      if (mounted) {
        setState(() {
          _isOpeningCamera = false;
          _isInitializing = false;
        });
      }
    }
  }

  Future<void> _reconnectCamera() async {
    if (_isOpeningCamera) {
      return;
    }
    setState(() {
      _isOpeningCamera = true;
      _isInitializing = true;
      _errorMessage = null;
      _statusMessage = '正在重建 USB 预览...';
    });

    await _releaseCameraResourcesAsync();
    if (!mounted) {
      return;
    }

    _cameraController = UVCCameraController();
    _setupCallbacks();
    setState(() {
      _previewRevision += 1;
      _isCameraOpen = false;
      _isRecording = false;
      _isStoppingRecording = false;
      _isOpeningCamera = false;
      _isInitializing = true;
    });

    await _waitForNextFrame();
    if (!mounted) {
      return;
    }
    await _initializeCamera(autoOpen: true);
  }

  Future<bool> _waitCameraReady({required Duration timeout}) async {
    final DateTime started = DateTime.now();
    while (mounted && DateTime.now().difference(started) < timeout) {
      if (_isCameraOpen) return true;
      final Map<String, dynamic>? info = await _readCameraRequestInfo();
      final PreviewSize? size = _extractPreviewSize(info);
      if (info != null && size != null) {
        if (mounted) {
          setState(() {
            _activePreviewSize = size;
            _isCameraOpen = true;
          });
        }
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return _isCameraOpen;
  }

  String _normalizeOpenError(Object error) {
    final String message = error.toString();
    if (message.contains("type 'Null' is not a subtype of type 'String'")) {
      return '摄像头初始化中，请稍后重试';
    }
    return '打开失败: $message';
  }

  void _setupCallbacks() {
    _cameraController?.cameraStateCallback = (UVCCameraState state) {
      if (!mounted) return;
      debugPrint('UVCCameraScreen: Camera state changed: $state');
      if (state == UVCCameraState.opened) {
        setState(() {
          _isCameraOpen = true;
          _isOpeningCamera = false;
          _isInitializing = false;
          _errorMessage = null;
        });
        _updateStatusMessage('摄像头已打开');
        _showOverlays();
        unawaited(_syncCameraDetails(applyPreferredResolution: false));
        return;
      }
      if (state == UVCCameraState.closed) {
        setState(() {
          _isCameraOpen = false;
          _isOpeningCamera = false;
          _isInitializing = false;
        });
        _updateStatusMessage('摄像头已关闭');
        return;
      }
      if (state == UVCCameraState.error) {
        setState(() {
          _isCameraOpen = false;
          _isOpeningCamera = false;
          _isInitializing = false;
        });
        _updateStatusMessage('摄像头出错');
        return;
      }
      setState(() {
        _isOpeningCamera = false;
        _isInitializing = false;
      });
      _updateStatusMessage('摄像头状态异常');
    };
    _cameraController?.msgCallback = (String msg) {
      final String text = msg.trim();
      debugPrint('UVCCameraScreen: Camera message: $text');
      if (text.isEmpty) {
        return;
      }
      if (text.contains('预览首帧已到达') && !_didApplyPreferredResolution) {
        _updateStatusMessage('正在切换到设备最佳分辨率...');
        _showOverlays();
        unawaited(_syncCameraDetails(applyPreferredResolution: true));
        return;
      }
      _updateStatusMessage(text);
    };
    _cameraController?.previewTapCallback = _toggleOverlays;
    _cameraController?.videoRecordingCompletedCallback = (String path) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecording = false;
        _isStoppingRecording = false;
      });
      if (path.isEmpty) {
        _updateStatusMessage('录像已停止');
        return;
      }
      _updateStatusMessage('录像已保存');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('视频已保存: $path')));
    };
    _cameraController?.videoRecordingErrorCallback = (String message) {
      _handleRecordingFailure('录像失败: $message');
    };
    _cameraController?.clickTakePictureButtonCallback = (String path) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('拍照完成: $path')));
    };
  }

  Future<Map<String, dynamic>?> _readCameraRequestInfo() async {
    try {
      final String? raw =
          await _cameraController?.getCurrentCameraRequestParameters();
      if (raw == null || raw.isEmpty) {
        return null;
      }
      final dynamic decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((dynamic k, dynamic v) => MapEntry(k.toString(), v));
      }
    } catch (e) {
      debugPrint('UVCCameraScreen: read request failed: $e');
    }
    return null;
  }

  Future<List<PreviewSize>> _readSupportedPreviewSizes() async {
    try {
      await _cameraController?.getAllPreviewSizes();
      return List<PreviewSize>.from(
          _cameraController?.previewSizes ?? <PreviewSize>[]);
    } catch (e) {
      debugPrint('UVCCameraScreen: read preview sizes failed: $e');
      return <PreviewSize>[];
    }
  }

  Future<void> _syncCameraDetails(
      {required bool applyPreferredResolution}) async {
    final Map<String, dynamic>? info = await _readCameraRequestInfo();
    final List<PreviewSize> sizes = await _readSupportedPreviewSizes();
    final PreviewSize? preferred = _pickPreferredPreviewSize(sizes);
    PreviewSize? active = _extractPreviewSize(info);
    if (applyPreferredResolution &&
        !_didApplyPreferredResolution &&
        preferred != null &&
        !_samePreviewSize(active, preferred)) {
      try {
        await _cameraController?.updateResolution(preferred);
        _didApplyPreferredResolution = true;
        await Future<void>.delayed(const Duration(milliseconds: 450));
        final Map<String, dynamic>? refreshed = await _readCameraRequestInfo();
        active = _extractPreviewSize(refreshed) ?? preferred;
        if (mounted && refreshed != null) {
          _activePreviewSize = _extractPreviewSize(refreshed) ?? preferred;
        }
      } catch (e) {
        debugPrint('UVCCameraScreen: apply preferred resolution failed: $e');
      }
    } else if (applyPreferredResolution && preferred != null) {
      _didApplyPreferredResolution = true;
    }
    if (!mounted) return;
    setState(() {
      _preferredPreviewSize = preferred;
      _activePreviewSize = active ?? preferred;
    });
    if (applyPreferredResolution && active != null) {
      _updateStatusMessage(
        '已切换至设备最佳分辨率',
        minInterval: Duration.zero,
      );
      _showOverlays();
    }
  }

  PreviewSize? _pickPreferredPreviewSize(List<PreviewSize> sizes) {
    if (sizes.isEmpty) return null;
    return sizes.reduce((PreviewSize a, PreviewSize b) {
      final int aArea = (a.width ?? 0) * (a.height ?? 0);
      final int bArea = (b.width ?? 0) * (b.height ?? 0);
      return bArea > aArea ? b : a;
    });
  }

  PreviewSize? _extractPreviewSize(Map<String, dynamic>? info) {
    if (info == null) {
      return null;
    }
    final int? width = _toInt(info['previewWidth']);
    final int? height = _toInt(info['previewHeight']);
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    return PreviewSize(width: width, height: height);
  }

  int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  bool _samePreviewSize(PreviewSize? a, PreviewSize? b) {
    if (a == null || b == null) return false;
    return a.width == b.width && a.height == b.height;
  }

  String _formatPreviewSize(PreviewSize? size) {
    final int width = size?.width ?? 0;
    final int height = size?.height ?? 0;
    if (width <= 0 || height <= 0) return '--';
    return '${width}x$height';
  }

  String _buildResolutionStatusText(
      PreviewSize? active, PreviewSize? preferred) {
    final String activeText = _formatPreviewSize(active);
    if (activeText == '--') {
      return '分辨率自动匹配中';
    }
    final String preferredText = _formatPreviewSize(preferred);
    if (preferredText != '--' && activeText != preferredText) {
      return '当前输出 $activeText · 优选 $preferredText';
    }
    return '当前输出 $activeText';
  }

  String _normalizeDeviceName(UsbCaptureDevice? device) {
    final String rawName = (device?.productName ?? '').trim();
    if (rawName.isEmpty) {
      return 'USB 采集卡';
    }
    final String lower = rawName.toLowerCase();
    if (lower == 'usb video' ||
        lower == 'usb camera' ||
        lower == 'camera' ||
        lower == 'uvc camera' ||
        lower == 'usb 2.0 camera') {
      return 'USB 采集卡';
    }
    return rawName;
  }

  void _updateStatusMessage(String message,
      {Duration minInterval = const Duration(milliseconds: 300)}) {
    if (!mounted || message.isEmpty) return;
    final DateTime now = DateTime.now();
    if (_statusMessage == message) return;
    if (now.difference(_lastStatusUpdate) < minInterval) return;
    _lastStatusUpdate = now;
    setState(() => _statusMessage = message);
  }

  void _setErrorMessage(String message) {
    if (!mounted) return;
    setState(() {
      _errorMessage = message;
      _statusMessage = message;
      _isOpeningCamera = false;
      _isInitializing = false;
    });
  }

  Future<void> _takePicture() async {
    try {
      final String? path = await _cameraController?.takePicture();
      if (!mounted || path == null || path.isEmpty) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('照片已保存: $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('拍照失败: $e')));
    }
  }

  Future<bool> _ensureRecordingPermissions() async {
    final PermissionStatus micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) return false;
    final PermissionStatus storageStatus = await Permission.storage.request();
    final PermissionStatus videosStatus = await Permission.videos.request();
    return storageStatus.isGranted ||
        storageStatus.isLimited ||
        videosStatus.isGranted ||
        videosStatus.isLimited;
  }

  Future<void> _toggleRecording() async {
    if (_isStoppingRecording) return;
    if (_isRecording) return _stopRecording();
    return _startRecording();
  }

  Future<void> _startRecording() async {
    final bool permissionReady = await _ensureRecordingPermissions();
    if (!permissionReady) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('录像权限不足，请授予麦克风和存储权限')));
      }
      return;
    }
    setState(() {
      _isStoppingRecording = false;
      _errorMessage = null;
    });
    _updateStatusMessage('开始录像...');
    try {
      await _cameraController?.startVideoRecording();
      if (!mounted) {
        return;
      }
      setState(() {
        _isRecording = true;
        _isStoppingRecording = false;
      });
      _updateStatusMessage('录像进行中...');
    } catch (e) {
      _handleRecordingFailure('录像失败: $e');
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    setState(() => _isStoppingRecording = true);
    _updateStatusMessage('正在停止录像...');
    try {
      await _cameraController?.stopVideoRecording();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() => _isStoppingRecording = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('停止录像失败: $e')));
    }
  }

  void _handleRecordingFailure(String message) {
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isStoppingRecording = false;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildPlatformPreview({
    required double width,
    required double height,
  }) {
    if (_cameraController == null) {
      return const SizedBox.shrink();
    }
    return KeyedSubtree(
      key: ValueKey<int>(_previewRevision),
      child: UVCCameraView(
        cameraController: _cameraController!,
        width: width,
        height: height,
      ),
    );
  }

  Widget _buildInteractivePreview(BoxConstraints constraints) {
    return _buildPlatformPreview(
      width: constraints.maxWidth,
      height: constraints.maxHeight,
    );
  }

  Widget _buildPreviewSurface() {
    return ColoredBox(
      color: Colors.black,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _buildInteractivePreview(constraints),
              IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.black.withValues(alpha: 0.28),
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.42),
                      ],
                      stops: const <double>[0.0, 0.45, 1.0],
                    ),
                  ),
                ),
              ),
              if (_isInitializing || (_isOpeningCamera && !_isCameraOpen))
                _buildLoadingOverlay(),
              if (!_isInitializing && !_isOpeningCamera && !_isCameraOpen)
                _buildOpenPreviewOverlay(),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Center(
      child: _OverlayPanel(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2.2,
              ),
            ),
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 240),
              child: Text(
                _statusMessage ?? '正在连接 USB 画面...',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpenPreviewOverlay() {
    final bool isError = _errorMessage != null;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: _OverlayPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                isError ? Icons.warning_amber_rounded : Icons.usb_rounded,
                size: 42,
                color: isError ? Colors.orangeAccent : AppColors.primary,
              ),
              const SizedBox(height: 12),
              Text(
                isError ? '预览暂未就绪' : '进入单通道监看',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage ?? '打开后画面会直接铺满窗口，双指即可放大查看细节。',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.76),
                  fontSize: 13,
                  height: 1.45,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed:
                    _isOpeningCamera ? null : () => unawaited(_openCamera()),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded),
                label: const Text('打开预览'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetric(String title, String value, {bool wide = false}) {
    return Container(
      constraints: BoxConstraints(
          minWidth: wide ? 240 : 132, maxWidth: wide ? 999 : 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white60)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ],
      ),
    );
  }

  Widget _buildFloatingHeader() {
    final String resolution = _formatPreviewSize(_activePreviewSize);
    final String subtitle = resolution == '--' ? 'USB 输入' : resolution;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _FloatingIconButton(
          icon: Icons.close_rounded,
          tooltip: '关闭预览',
          onPressed: () => unawaited(_closePage()),
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 210),
          child: _OverlayPanel(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  'USB 摄像头',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.66),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLiveBadge() {
    final bool isReady = _isCameraOpen && !_isRecording;
    final bool isBusy = _isOpeningCamera || _isInitializing;
    final Color badgeColor = _isRecording
        ? Colors.redAccent
        : isReady
            ? Colors.greenAccent
            : isBusy
                ? AppColors.primary
                : Colors.orangeAccent;
    final String badgeLabel = _isRecording
        ? 'REC'
        : isReady
            ? 'LIVE'
            : isBusy
                ? '连接中'
                : '待打开';

    return _OverlayPanel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: badgeColor.withValues(alpha: 0.32),
                  blurRadius: 10,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            badgeLabel,
            style: TextStyle(
              color: badgeColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlaySection({
    required Widget child,
    Duration duration = const Duration(milliseconds: 180),
  }) {
    return IgnorePointer(
      ignoring: !_areOverlaysVisible,
      child: AnimatedOpacity(
        duration: duration,
        opacity: _areOverlaysVisible ? 1 : 0,
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }

  Widget _buildFloatingInfoPanel() {
    return Selector<UsbCaptureService, UsbCaptureDevice?>(
      selector: (BuildContext context, UsbCaptureService service) =>
          service.connectedDevice,
      builder: (BuildContext context, UsbCaptureDevice? device, Widget? child) {
        if (_isInfoPanelMinimized) {
          return const SizedBox.shrink();
        }

        final bool isError = _errorMessage != null;
        final bool isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        final double screenHeight = MediaQuery.of(context).size.height;
        final double maxPanelHeight =
            screenHeight * (isLandscape ? 0.62 : 0.68);
        final Color accentColor = isError
            ? Colors.redAccent
            : _isRecording
                ? Colors.orangeAccent
                : AppColors.primary;
        final String statusText = _errorMessage ??
            _statusMessage ??
            (_isCameraOpen ? '画面已就绪，可直接双指缩放查看细节。' : '等待打开预览。');

        final String deviceName = _normalizeDeviceName(device);
        final String activeSize = _formatPreviewSize(_activePreviewSize);
        final String preferredSize = _formatPreviewSize(_preferredPreviewSize);

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: isLandscape ? 420 : 360,
            maxHeight: maxPanelHeight,
          ),
          child: _OverlayPanel(
            padding: const EdgeInsets.all(16),
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.dashboard_customize_rounded,
                            color: accentColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '画面概览',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () =>
                              setState(() => _isInfoPanelMinimized = true),
                          tooltip: '隐藏概览',
                          splashRadius: 18,
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withValues(alpha: 0.72),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.22),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Icon(
                            isError
                                ? Icons.priority_high_rounded
                                : Icons.chat_bubble_outline_rounded,
                            color: accentColor,
                            size: 18,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              statusText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                height: 1.45,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.usb_rounded,
                            color: AppColors.primary,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                deviceName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _buildResolutionStatusText(
                                  _activePreviewSize,
                                  _preferredPreviewSize,
                                ),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.64),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: (_isCameraOpen
                                    ? Colors.greenAccent
                                    : Colors.orangeAccent)
                                .withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _isCameraOpen ? '预览中' : '待打开',
                            style: TextStyle(
                              color: _isCameraOpen
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        _OverlayHintChip(
                          icon: Icons.zoom_in_map_rounded,
                          label: '双指缩放',
                        ),
                        _OverlayHintChip(
                          icon: Icons.touch_app_rounded,
                          label: '双击复位',
                        ),
                        _OverlayHintChip(
                          icon: Icons.hd_rounded,
                          label: activeSize == '--' ? '自动分辨率' : activeSize,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => setState(
                          () => _isOverviewExpanded = !_isOverviewExpanded),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white70,
                        padding: EdgeInsets.zero,
                      ),
                      icon: Icon(_isOverviewExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded),
                      label: Text(
                        _isOverviewExpanded ? '收起设备详情' : '展开硬件详情',
                      ),
                    ),
                    if (_isOverviewExpanded) ...<Widget>[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: <Widget>[
                          _buildMetric(
                            'VID',
                            device == null
                                ? '--'
                                : '0x${device.vid.toRadixString(16).toUpperCase().padLeft(4, '0')}',
                          ),
                          _buildMetric(
                            'PID',
                            device == null
                                ? '--'
                                : '0x${device.pid.toRadixString(16).toUpperCase().padLeft(4, '0')}',
                          ),
                          _buildMetric('当前分辨率', activeSize),
                          _buildMetric('优选分辨率', preferredSize),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingControls() {
    if (_isControlPanelMinimized) {
      return Align(
        alignment: Alignment.bottomRight,
        child: _OverlayPanel(
          padding: const EdgeInsets.all(6),
          child: IconButton(
            onPressed: () => setState(() => _isControlPanelMinimized = false),
            tooltip: '展开操作',
            splashRadius: 20,
            icon: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
            ),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: _OverlayPanel(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.control_camera_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '操作浮窗',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_isRecording)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.redAccent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        '录制中',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  IconButton(
                    onPressed: () =>
                        setState(() => _isControlPanelMinimized = true),
                    tooltip: '最小化操作',
                    splashRadius: 18,
                    icon: Icon(
                      Icons.minimize_rounded,
                      color: Colors.white.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 18,
                runSpacing: 18,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  _ActionButton(
                    icon: _isInfoPanelMinimized
                        ? Icons.dashboard_customize_rounded
                        : Icons.visibility_off_rounded,
                    label: _isInfoPanelMinimized ? '概览' : '隐藏概览',
                    color: const Color(0xFF64748B),
                    onPressed: () {
                      _showOverlays();
                      setState(
                        () => _isInfoPanelMinimized = !_isInfoPanelMinimized,
                      );
                    },
                  ),
                  _ActionButton(
                    icon: _isChromeManuallyHidden
                        ? Icons.layers_rounded
                        : Icons.visibility_rounded,
                    label: _isChromeManuallyHidden ? '恢复界面' : '隐藏界面',
                    color: const Color(0xFF8B5CF6),
                    onPressed: () {
                      _toggleFloatingWindowsVisibility();
                    },
                  ),
                  _ActionButton(
                    icon: _isCameraOpen
                        ? Icons.camera_alt_rounded
                        : Icons.play_arrow_rounded,
                    label: _isCameraOpen ? '截图' : '打开预览',
                    color: _isCameraOpen
                        ? const Color(0xFF2997FF)
                        : AppColors.primary,
                    onPressed: _isCameraOpen
                        ? () {
                            _showOverlays();
                            unawaited(_takePicture());
                          }
                        : (_isOpeningCamera
                            ? null
                            : () {
                                _showOverlays();
                                unawaited(_openCamera());
                              }),
                  ),
                  _ActionButton(
                    icon: _isRecording
                        ? Icons.stop_circle_rounded
                        : Icons.videocam_rounded,
                    label: _isRecording ? '停止录制' : '录制',
                    color: _isRecording
                        ? Colors.redAccent
                        : const Color(0xFFFFA726),
                    onPressed: (_isCameraOpen && !_isStoppingRecording)
                        ? () {
                            _showOverlays();
                            unawaited(_toggleRecording());
                          }
                        : null,
                  ),
                  _ActionButton(
                    icon: Icons.refresh_rounded,
                    label: '重连',
                    color: const Color(0xFF14B8A6),
                    onPressed: _isOpeningCamera
                        ? null
                        : () {
                            _showOverlays();
                            unawaited(_reconnectCamera());
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImmersiveLayout() {
    final bool isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final double infoPanelBottomOffset =
        _isControlPanelMinimized ? 96 : (isLandscape ? 168 : 208);

    return Scaffold(
      backgroundColor: Colors.black,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              _buildPreviewSurface(),
              Positioned(
                top: 16,
                left: 16,
                child: _buildOverlaySection(
                  child: _buildFloatingHeader(),
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: _buildOverlaySection(
                  child: _buildLiveBadge(),
                ),
              ),
              if (!_isInfoPanelMinimized)
                Positioned(
                  left: 16,
                  right: isLandscape ? null : 16,
                  bottom: infoPanelBottomOffset,
                  child: _buildOverlaySection(
                    child: Align(
                      alignment: Alignment.bottomLeft,
                      child: _buildFloatingInfoPanel(),
                    ),
                  ),
                ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: _buildOverlaySection(
                  child: _buildFloatingControls(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildImmersiveLayout();
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
    if (now.difference(_lastTapAt) < _debounceDuration) return;
    _lastTapAt = now;
    setState(() => _isLocked = true);
    try {
      onPressed();
    } finally {
      await Future<void>.delayed(_debounceDuration);
      if (mounted) setState(() => _isLocked = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool enabled = widget.onPressed != null && !_isLocked;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 66,
          height: 66,
          decoration: BoxDecoration(
            color: enabled
                ? widget.color.withValues(alpha: 0.94)
                : Colors.white.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withValues(alpha: enabled ? 0.16 : 0.08),
            ),
            boxShadow: enabled
                ? <BoxShadow>[
                    BoxShadow(
                      color: widget.color.withValues(alpha: 0.2),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: enabled ? () => unawaited(_handleTap()) : null,
              borderRadius: BorderRadius.circular(18),
              child: Icon(widget.icon, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: enabled ? Colors.white : Colors.white54,
            )),
      ],
    );
  }
}

class _OverlayPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _OverlayPanel({
    required this.child,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB8141A1F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: padding,
        child: child,
      ),
    );
  }
}

class _FloatingIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _FloatingIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return _OverlayPanel(
      padding: const EdgeInsets.all(6),
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        splashRadius: 20,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _OverlayHintChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _OverlayHintChip({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: Colors.white70),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
