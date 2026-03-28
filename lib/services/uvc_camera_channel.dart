import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PreviewSize {
  final int? width;
  final int? height;

  const PreviewSize({this.width, this.height});

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'width': width,
      'height': height,
    };
  }

  factory PreviewSize.fromJson(dynamic json) {
    if (json is Map<dynamic, dynamic>) {
      return PreviewSize(
        width: json['width'] as int?,
        height: json['height'] as int?,
      );
    }
    return const PreviewSize();
  }
}

enum UVCCameraState { opened, closed, error }

class UVCCameraViewParamsEntity {
  final int? minFps;
  final int? maxFps;
  final int? frameFormat;
  final double? bandwidthFactor;
  final int? preferredWidth;
  final int? preferredHeight;

  const UVCCameraViewParamsEntity({
    this.minFps = 10,
    this.maxFps = 60,
    this.frameFormat = 1,
    this.bandwidthFactor = 1.0,
    this.preferredWidth,
    this.preferredHeight,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'minFps': minFps,
      'maxFps': maxFps,
      'frameFormat': frameFormat,
      'bandwidthFactor': bandwidthFactor,
      'preferredWidth': preferredWidth,
      'preferredHeight': preferredHeight,
    };
  }
}

class UVCCameraController {
  static const MethodChannel _channel =
      MethodChannel('selene.uvc_camera/channel');

  UVCCameraState _cameraState = UVCCameraState.closed;
  final List<PreviewSize> _previewSizes = <PreviewSize>[];

  bool _disposed = false;

  void Function(UVCCameraState state)? cameraStateCallback;
  void Function(String path)? clickTakePictureButtonCallback;
  void Function(String message)? msgCallback;

  UVCCameraState get cameraState => _cameraState;
  List<PreviewSize> get previewSizes =>
      List<PreviewSize>.unmodifiable(_previewSizes);

  UVCCameraController() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (_disposed) {
      return;
    }

    switch (call.method) {
      case 'callFlutter':
        final dynamic arguments = call.arguments;
        if (arguments is Map) {
          final String? message = arguments['msg'] as String?;
          if (message != null && message.isNotEmpty) {
            msgCallback?.call(message);
          }
        }
        break;
      case 'takePictureSuccess':
        final String? path = call.arguments as String?;
        if (path != null && path.isNotEmpty) {
          clickTakePictureButtonCallback?.call(path);
        }
        break;
      case 'CameraState':
        _setCameraState(call.arguments?.toString() ?? '');
        break;
      default:
        break;
    }
  }

  Future<void> initializeCamera() async {
    await _channel.invokeMethod<void>('initializeCamera');
  }

  Future<void> openUVCCamera() async {
    await _channel.invokeMethod<void>('openUVCCamera');
  }

  Future<void> closeCamera() async {
    await _channel.invokeMethod<void>('closeCamera');
  }

  Future<List<PreviewSize>> getAllPreviewSizes() async {
    final String? raw =
        await _channel.invokeMethod<String>('getAllPreviewSizes');
    _previewSizes
      ..clear()
      ..addAll(_decodePreviewSizes(raw));
    return previewSizes;
  }

  Future<String?> getCurrentCameraRequestParameters() async {
    return _channel.invokeMethod<String>('getCurrentCameraRequestParameters');
  }

  Future<void> updateResolution(PreviewSize? previewSize) async {
    await _channel.invokeMethod<void>('updateResolution', previewSize?.toMap());
  }

  Future<String?> takePicture() async {
    return _channel.invokeMethod<String>('takePicture');
  }

  Future<String?> captureVideo() async {
    return _channel.invokeMethod<String>('captureVideo');
  }

  Future<void> setZoom(int zoom) async {
    await _channel
        .invokeMethod<void>('setZoom', <String, dynamic>{'zoom': zoom});
  }

  Future<int?> getZoom() async {
    return _channel.invokeMethod<int>('getZoom');
  }

  Future<int?> getMaxZoom() async {
    return _channel.invokeMethod<int>('getMaxZoom');
  }

  Future<void> resetZoom() async {
    await _channel.invokeMethod<void>('resetZoom');
  }

  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
  }

  void _setCameraState(String state) {
    if (state == 'OPENED') {
      _cameraState = UVCCameraState.opened;
      cameraStateCallback?.call(UVCCameraState.opened);
      return;
    }
    if (state == 'CLOSED') {
      _cameraState = UVCCameraState.closed;
      cameraStateCallback?.call(UVCCameraState.closed);
      return;
    }
    if (state.contains('ERROR')) {
      _cameraState = UVCCameraState.error;
      cameraStateCallback?.call(UVCCameraState.error);
      msgCallback?.call(state);
    }
  }

  List<PreviewSize> _decodePreviewSizes(String? raw) {
    if (raw == null || raw.isEmpty) {
      return <PreviewSize>[];
    }

    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map<PreviewSize>((dynamic item) {
          return PreviewSize.fromJson(item);
        }).toList();
      }
    } catch (_) {
      return <PreviewSize>[];
    }
    return <PreviewSize>[];
  }
}

class UVCCameraView extends StatefulWidget {
  final UVCCameraController cameraController;
  final double width;
  final double height;
  final UVCCameraViewParamsEntity? params;

  const UVCCameraView({
    super.key,
    required this.cameraController,
    required this.width,
    required this.height,
    this.params,
  });

  @override
  State<UVCCameraView> createState() => _UVCCameraViewState();
}

class _UVCCameraViewState extends State<UVCCameraView> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AndroidView(
        viewType: 'selene.uvc_camera/view',
        creationParams: widget.params?.toMap(),
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (int _) {
          widget.cameraController.initializeCamera();
        },
      ),
    );
  }
}
