import 'package:selene/models/admin_config.dart';
import 'package:selene/services/api_service.dart';

class AdminService {
  const AdminService();

  Future<ApiResponse<AdminConfigResult>> fetchConfig() {
    return ApiService.get<AdminConfigResult>(
      '/api/admin/config',
      fromJson: (dynamic data) =>
          AdminConfigResult.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> updateSiteConfig(
    AdminSiteConfig siteConfig,
  ) {
    return ApiService.post<Map<String, dynamic>>(
      '/api/admin/site',
      body: siteConfig.toJson(),
      fromJson: (dynamic data) =>
          Map<String, dynamic>.from(data as Map<dynamic, dynamic>),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> performUserAction({
    required String action,
    String? targetUsername,
    String? targetPassword,
    String? userGroup,
    List<String>? enabledApis,
    List<String>? userGroups,
    String? groupAction,
    String? groupName,
    List<String>? usernames,
  }) {
    return ApiService.post<Map<String, dynamic>>(
      '/api/admin/user',
      body: <String, dynamic>{
        if (targetUsername != null && targetUsername.isNotEmpty)
          'targetUsername': targetUsername,
        if (targetPassword != null && targetPassword.isNotEmpty)
          'targetPassword': targetPassword,
        if (userGroup != null) 'userGroup': userGroup,
        if (enabledApis != null) 'enabledApis': enabledApis,
        if (userGroups != null) 'userGroups': userGroups,
        if (groupAction != null && groupAction.isNotEmpty)
          'groupAction': groupAction,
        if (groupName != null && groupName.isNotEmpty) 'groupName': groupName,
        if (usernames != null) 'usernames': usernames,
        'action': action,
      },
      fromJson: (dynamic data) =>
          Map<String, dynamic>.from(data as Map<dynamic, dynamic>),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> performSourceAction({
    required String action,
    String? key,
    String? name,
    String? api,
    String? detail,
    List<String>? keys,
    List<String>? order,
  }) {
    return ApiService.post<Map<String, dynamic>>(
      '/api/admin/source',
      body: <String, dynamic>{
        'action': action,
        if (key != null && key.isNotEmpty) 'key': key,
        if (name != null && name.isNotEmpty) 'name': name,
        if (api != null && api.isNotEmpty) 'api': api,
        if (detail != null && detail.isNotEmpty) 'detail': detail,
        if (keys != null) 'keys': keys,
        if (order != null) 'order': order,
      },
      fromJson: (dynamic data) =>
          Map<String, dynamic>.from(data as Map<dynamic, dynamic>),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> performLiveSourceAction({
    required String action,
    String? key,
    String? name,
    String? url,
    String? ua,
    String? epg,
    List<String>? order,
  }) {
    return ApiService.post<Map<String, dynamic>>(
      '/api/admin/live',
      body: <String, dynamic>{
        'action': action,
        if (key != null && key.isNotEmpty) 'key': key,
        if (name != null && name.isNotEmpty) 'name': name,
        if (url != null && url.isNotEmpty) 'url': url,
        if (ua != null && ua.isNotEmpty) 'ua': ua,
        if (epg != null && epg.isNotEmpty) 'epg': epg,
        if (order != null) 'order': order,
      },
      fromJson: (dynamic data) =>
          Map<String, dynamic>.from(data as Map<dynamic, dynamic>),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> refreshLiveSources() {
    return ApiService.post<Map<String, dynamic>>(
      '/api/admin/live/refresh',
      fromJson: (dynamic data) =>
          Map<String, dynamic>.from(data as Map<dynamic, dynamic>),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> performCategoryAction({
    required String action,
    String? name,
    String? type,
    String? query,
    List<String>? order,
  }) {
    return ApiService.post<Map<String, dynamic>>(
      '/api/admin/category',
      body: <String, dynamic>{
        'action': action,
        if (name != null && name.isNotEmpty) 'name': name,
        if (type != null && type.isNotEmpty) 'type': type,
        if (query != null && query.isNotEmpty) 'query': query,
        if (order != null) 'order': order,
      },
      fromJson: (dynamic data) =>
          Map<String, dynamic>.from(data as Map<dynamic, dynamic>),
    );
  }

  Future<ApiResponse<String>> fetchConfigSubscription(String url) {
    return ApiService.post<String>(
      '/api/admin/config_subscription/fetch',
      body: <String, dynamic>{
        'url': url,
      },
      fromJson: (dynamic data) =>
          (data as Map<String, dynamic>)['configContent'] as String? ?? '',
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> saveConfigFile({
    required String configFile,
    required String subscriptionUrl,
    required bool autoUpdate,
    required String lastCheckTime,
  }) {
    return ApiService.post<Map<String, dynamic>>(
      '/api/admin/config_file',
      body: <String, dynamic>{
        'configFile': configFile,
        'subscriptionUrl': subscriptionUrl,
        'autoUpdate': autoUpdate,
        'lastCheckTime': lastCheckTime,
      },
      fromJson: (dynamic data) =>
          Map<String, dynamic>.from(data as Map<dynamic, dynamic>),
    );
  }

  Future<ApiResponse<Map<String, dynamic>>> resetConfig() {
    return ApiService.get<Map<String, dynamic>>(
      '/api/admin/reset',
      fromJson: (dynamic data) =>
          Map<String, dynamic>.from(data as Map<dynamic, dynamic>),
    );
  }
}
