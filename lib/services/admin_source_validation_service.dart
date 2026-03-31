import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:selene/models/admin_source_validation.dart';
import 'package:selene/services/user_data_service.dart';

class AdminSourceValidationService {
  http.Client? _client;
  StreamSubscription<http.StreamedResponse>? _subscription;
  StreamController<AdminSourceValidationEvent>? _eventController;
  final StringBuffer _buffer = StringBuffer();

  Stream<AdminSourceValidationEvent> get eventStream =>
      _eventController?.stream ??
      const Stream<AdminSourceValidationEvent>.empty();

  Future<void> startValidation(String query) async {
    await stopValidation();
    _eventController = StreamController<AdminSourceValidationEvent>.broadcast();

    final String? baseUrl = await UserDataService.getServerUrl();
    final String? cookies = await UserDataService.getCookies();

    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    if (cookies == null || cookies.isEmpty) {
      throw Exception('用户未登录');
    }

    final Uri baseUri = Uri.parse(baseUrl);
    final Uri validationUri = baseUri.replace(
      path: '/api/admin/source/validate',
      queryParameters: <String, String>{
        'q': query.trim(),
      },
    );

    _client = http.Client();
    final http.Request request = http.Request('GET', validationUri);
    request.headers.addAll(<String, String>{
      'Accept': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Cookie': cookies,
    });

    _subscription = _client!.send(request).asStream().listen(
      _handleResponse,
      onError: (dynamic error) {
        _eventController?.add(
          const AdminSourceValidationEvent(
            type: AdminSourceValidationEventType.complete,
          ),
        );
        _closeClient();
      },
      onDone: _closeClient,
    );
  }

  Future<void> stopValidation() async {
    await _subscription?.cancel();
    _subscription = null;
    await _eventController?.close();
    _eventController = null;
    _closeClient();
  }

  void _handleResponse(http.StreamedResponse response) async {
    if (response.statusCode != 200) {
      throw Exception('校验连接失败: ${response.statusCode}');
    }

    _buffer.clear();
    await for (final String chunk
        in response.stream.transform(const Utf8Decoder())) {
      _buffer.write(chunk);
      final List<String> lines = _buffer.toString().split('\n');
      if (lines.isNotEmpty) {
        final String remainder = lines.removeLast();
        _buffer
          ..clear()
          ..write(remainder);
      }

      for (final String line in lines) {
        if (!line.startsWith('data: ')) {
          continue;
        }
        final String jsonString = line.substring(6).trim();
        if (jsonString.isEmpty) {
          continue;
        }

        final Map<String, dynamic> jsonMap =
            Map<String, dynamic>.from(json.decode(jsonString) as Map);
        _eventController?.add(AdminSourceValidationEvent.fromJson(jsonMap));
      }
    }
  }

  void _closeClient() {
    _client?.close();
    _client = null;
  }
}
