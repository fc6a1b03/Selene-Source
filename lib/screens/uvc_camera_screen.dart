import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
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
  final GlobalKey _previewKey = GlobalKey();

  UVCCameraController? _cameraController;
  StreamSubscription<UsbCaptureEvent>? _usbEventSubscription;
  Future<String?>? _recordingFuture;

  bool _isInitializing = true;
  bool _isOpeningCamera = false;
  bool _isCameraOpen = false;
  bool _isRecording = false;
  bool _isStoppingRecording = false;
  bool _isOverviewExpanded = false;
  bool _isClosingPage = false;
  bool _didApplyPreferredResolution = false;

  String? _statusMessage;
  String? _errorMessage;
  DateTime _lastStatusUpdate = DateTime.fromMillisecondsSinceEpoch(0);
  PreviewSize? _activePreviewSize;
  PreviewSize? _preferredPreviewSize;

  @override
  void initState() {
    super.initState();
    _cameraController = UVCCameraController();
    _setupCallbacks();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachUsbDisconnectListener();
      unawaited(_initializeCamera(autoOpen: true));
    });
  }

  @override
  void dispose() {
    _detachUsbDisconnectListener();
    _releaseCameraResources();
    super.dispose();
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
        unawaited(_closePage());
      }
    });
  }

  void _detachUsbDisconnectListener() {
    _usbEventSubscription?.cancel();
    _usbEventSubscription = null;
  }

  void _releaseCameraResources() {
    try {
      _cameraController?.closeCamera();
      _cameraController?.dispose();
    } catch (e) {
      debugPrint('UVCCameraScreen: release error: $e');
    } finally {
      _cameraController = null;
      _recordingFuture = null;
      _activePreviewSize = null;
      _preferredPreviewSize = null;
      _didApplyPreferredResolution = false;
    }
  }

  Future<void> _closePage() async {
    if (_isClosingPage) {
      return;
    }
    _isClosingPage = true;
    _detachUsbDisconnectListener();
    _releaseCameraResources();
    if (mounted) {
      Navigator.of(context).pop();
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
      await _syncCameraDetails(applyPreferredResolution: true);
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
      if (state == UVCCameraState.opened) {
        setState(() {
          _isCameraOpen = true;
          _isOpeningCamera = false;
          _isInitializing = false;
          _errorMessage = null;
        });
        _updateStatusMessage('摄像头已打开');
        unawaited(_syncCameraDetails(applyPreferredResolution: true));
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
      setState(() {
        _isOpeningCamera = false;
        _isInitializing = false;
      });
      _updateStatusMessage('摄像头状态异常');
    };
    _cameraController?.msgCallback = (String msg) {
      final String text = msg.trim();
      if (text.isNotEmpty) _updateStatusMessage(text);
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
    } else if (preferred != null) {
      _didApplyPreferredResolution = true;
    }
    if (!mounted) return;
    setState(() {
      _preferredPreviewSize = preferred;
      _activePreviewSize = active ?? preferred;
    });
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
      _isRecording = true;
      _isStoppingRecording = false;
      _errorMessage = null;
    });
    _updateStatusMessage('开始录像...');
    final Future<String?>? session = _cameraController?.captureVideo();
    if (session == null) return _handleRecordingFailure('录像失败：控制器不可用');
    _recordingFuture = session;
    unawaited(session.then((String? path) {
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _isStoppingRecording = false;
        if (_recordingFuture == session) _recordingFuture = null;
      });
      if (path == null || path.isEmpty) return _updateStatusMessage('录像已停止');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('视频已保存: $path')));
    }).catchError((Object error) {
      _handleRecordingFailure('录像失败: $error');
    }));
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    setState(() => _isStoppingRecording = true);
    _updateStatusMessage('正在停止录像...');
    final Future<String?>? stopFuture = _cameraController?.captureVideo();
    if (stopFuture == null) {
      if (mounted) setState(() => _isStoppingRecording = false);
      return;
    }
    unawaited(stopFuture.catchError((Object error) {
      debugPrint('UVCCameraScreen: stop recording failed: $error');
      return null;
    }));
  }

  void _handleRecordingFailure(String message) {
    if (!mounted) return;
    setState(() {
      _isRecording = false;
      _isStoppingRecording = false;
      _recordingFuture = null;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildStatusBar() {
    if (_statusMessage == null && _errorMessage == null) {
      return const SizedBox.shrink();
    }
    final bool isError = _errorMessage != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isError
          ? Colors.red.withValues(alpha: 0.12)
          : AppColors.primary.withValues(alpha: 0.12),
      child: Text(
        _errorMessage ?? _statusMessage ?? '',
        style: TextStyle(
            color: isError ? Colors.red : AppColors.primary,
            fontSize: 14,
            fontWeight: FontWeight.w500),
        textAlign: TextAlign.center,
      ),
    );
  }

  double _currentAspectRatio() {
    final int width =
        (_activePreviewSize?.width ?? _preferredPreviewSize?.width) ?? 16;
    final int height =
        (_activePreviewSize?.height ?? _preferredPreviewSize?.height) ?? 9;
    if (width <= 0 || height <= 0) {
      return 16 / 9;
    }
    return width / height;
  }

  Widget _buildPlatformPreview({
    required double width,
    required double height,
  }) {
    if (_cameraController == null) {
      return const SizedBox.shrink();
    }
    return KeyedSubtree(
      key: _previewKey,
      child: RepaintBoundary(
        child: UVCCameraView(
          cameraController: _cameraController!,
          width: width,
          height: height,
        ),
      ),
    );
  }

  Widget _buildInteractivePreview(BoxConstraints constraints) {
    return ClipRect(
      child: _buildPlatformPreview(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
      ),
    );
  }

  Widget _buildPreviewSurface() {
    final double aspectRatio = _currentAspectRatio();
    final BorderRadius radius = BorderRadius.circular(12);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: radius,
          boxShadow: AppShadows.medium,
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _buildInteractivePreview(constraints),
                    if (_isInitializing || (_isOpeningCamera && !_isCameraOpen))
                      const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    if (!_isInitializing && !_isOpeningCamera && !_isCameraOpen)
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => unawaited(_openCamera()),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ),
                    if (!_isInitializing && !_isOpeningCamera && !_isCameraOpen)
                      const Center(
                        child: Text(
                          '点击“打开”开始预览',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetric(String title, String value, bool isDark,
      {bool wide = false}) {
    return Container(
      constraints: BoxConstraints(
          minWidth: wide ? 240 : 132, maxWidth: wide ? 999 : 180),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(title,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white60 : Colors.black45)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildDeviceOverview(bool isDark) {
    return Consumer<UsbCaptureService>(
      builder:
          (BuildContext context, UsbCaptureService service, Widget? child) {
        final device = service.connectedDevice;
        if (device == null) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('未检测到 USB 采集卡', style: TextStyle(color: Colors.grey)),
          );
        }
        final Widget header = InkWell(
          onTap: () =>
              setState(() => _isOverviewExpanded = !_isOverviewExpanded),
          borderRadius: BorderRadius.circular(16),
          child: Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.usb, color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      device.productName ?? 'USB 采集卡',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatPreviewSize(_activePreviewSize),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: (_isCameraOpen ? Colors.green : Colors.orange)
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _isCameraOpen ? '预览中' : '待打开',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _isCameraOpen ? Colors.green : Colors.orange,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                _isOverviewExpanded ? Icons.expand_less : Icons.expand_more,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ],
          ),
        );
        final Widget details = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                _buildMetric(
                  'VID',
                  '0x${device.vid.toRadixString(16).toUpperCase().padLeft(4, '0')}',
                  isDark,
                ),
                _buildMetric(
                  'PID',
                  '0x${device.pid.toRadixString(16).toUpperCase().padLeft(4, '0')}',
                  isDark,
                ),
                _buildMetric(
                  '当前分辨率',
                  _formatPreviewSize(_activePreviewSize),
                  isDark,
                ),
                _buildMetric(
                  '默认分辨率',
                  _formatPreviewSize(_preferredPreviewSize),
                  isDark,
                ),
              ],
            ),
          ],
        );
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: isDark ? null : AppShadows.small,
          ),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                header,
                if (_isOverviewExpanded) details,
              ],
            ),
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
              icon: Icons.camera_alt,
              label: '截屏',
              color: Colors.blue,
              onPressed: _isCameraOpen ? () => unawaited(_takePicture()) : null,
            ),
            _ActionButton(
              icon: _isRecording ? Icons.stop : Icons.videocam,
              label: _isRecording ? '停止录屏' : '录屏',
              color: _isRecording ? Colors.red : Colors.orange,
              onPressed: (_isCameraOpen && !_isStoppingRecording)
                  ? () => unawaited(_toggleRecording())
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNormalLayout(bool isDark) {
    return Scaffold(
      backgroundColor:
          isDark ? AppColors.darkBackground : AppColors.lightBackground,
      appBar: AppBar(
        leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => unawaited(_closePage())),
        title: const Text('USB 摄像头'),
        backgroundColor: AppColors.primary,
      ),
      body: Column(
        children: <Widget>[
          _buildStatusBar(),
          _buildPreviewSurface(),
          _buildDeviceOverview(isDark),
          const Spacer(),
          _buildControls(),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return _buildNormalLayout(isDark);
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
        Material(
          color: enabled ? widget.color : Colors.grey,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            onTap: enabled ? () => unawaited(_handleTap()) : null,
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
                width: 56,
                height: 56,
                child: Icon(widget.icon, color: Colors.white, size: 28)),
          ),
        ),
        const SizedBox(height: 4),
        Text(widget.label,
            style: TextStyle(
                fontSize: 11, color: enabled ? Colors.white : Colors.grey)),
      ],
    );
  }
}
