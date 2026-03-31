import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:selene/models/admin_data_migration.dart';
import 'package:selene/services/user_data_service.dart';

class AdminDataMigrationService {
  const AdminDataMigrationService();

  static const Duration _timeout = Duration(seconds: 60);

  Future<DataMigrationExportPayload> exportData(String password) async {
    final String baseUrl = await _requireBaseUrl();
    final String cookies = await _requireCookies();

    final http.Response response = await http
        .post(
          Uri.parse('$baseUrl/api/admin/data_migration/export'),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Cookie': cookies,
          },
          body: json.encode(<String, String>{
            'password': password,
          }),
        )
        .timeout(_timeout);

    if (response.statusCode != 200) {
      throw Exception(_extractErrorMessage(response));
    }

    return DataMigrationExportPayload(
      fileName: _extractDownloadFileName(response) ?? 'selene-backup.dat',
      bytes: response.bodyBytes,
    );
  }

  Future<DataMigrationImportResult> importData({
    required Uint8List bytes,
    required String fileName,
    required String password,
  }) async {
    final String baseUrl = await _requireBaseUrl();
    final String cookies = await _requireCookies();

    final http.MultipartRequest request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/admin/data_migration/import'),
    );
    request.headers['Cookie'] = cookies;
    request.fields['password'] = password;
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      ),
    );

    final http.StreamedResponse streamedResponse =
        await request.send().timeout(_timeout);
    final http.Response response = await http.Response.fromStream(
      streamedResponse,
    );

    if (response.statusCode != 200) {
      throw Exception(_extractErrorMessage(response));
    }

    final Map<String, dynamic> jsonMap =
        Map<String, dynamic>.from(json.decode(response.body) as Map);
    return DataMigrationImportResult.fromJson(jsonMap);
  }

  Future<String> _requireBaseUrl() async {
    final String? baseUrl = await UserDataService.getServerUrl();
    if (baseUrl == null || baseUrl.isEmpty) {
      throw Exception('未配置服务器地址');
    }
    return baseUrl;
  }

  Future<String> _requireCookies() async {
    final String? cookies = await UserDataService.getCookies();
    if (cookies == null || cookies.isEmpty) {
      throw Exception('用户未登录');
    }
    return cookies;
  }

  String _extractErrorMessage(http.Response response) {
    try {
      final Map<String, dynamic> jsonMap =
          Map<String, dynamic>.from(json.decode(response.body) as Map);
      return jsonMap['error'] as String? ??
          jsonMap['message'] as String? ??
          '操作失败 (${response.statusCode})';
    } catch (_) {
      return '操作失败 (${response.statusCode})';
    }
  }

  String? _extractDownloadFileName(http.Response response) {
    final String? contentDisposition = response.headers['content-disposition'];
    if (contentDisposition == null) {
      return null;
    }
    final RegExp matchExp = RegExp('filename="([^"]+)"');
    final RegExpMatch? match = matchExp.firstMatch(contentDisposition);
    return match?.group(1);
  }
}
