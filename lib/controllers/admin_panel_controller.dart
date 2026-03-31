import 'package:flutter/foundation.dart';
import 'package:selene/models/admin_config.dart';
import 'package:selene/models/admin_data_migration.dart';
import 'package:selene/services/admin_data_migration_service.dart';
import 'package:selene/services/admin_service.dart';
import 'package:selene/services/native_file_access_service.dart';

class AdminPanelController extends ChangeNotifier {
  AdminPanelController({
    AdminService adminService = const AdminService(),
    AdminDataMigrationService dataMigrationService =
        const AdminDataMigrationService(),
    NativeFileAccessService nativeFileAccessService =
        const NativeFileAccessService(),
  })  : _adminService = adminService,
        _dataMigrationService = dataMigrationService,
        _nativeFileAccessService = nativeFileAccessService;

  final AdminService _adminService;
  final AdminDataMigrationService _dataMigrationService;
  final NativeFileAccessService _nativeFileAccessService;

  bool _isLoading = false;
  bool _isSavingSiteConfig = false;
  bool _isFetchingSubscriptionConfig = false;
  bool _isSavingConfigFile = false;
  bool _isResettingConfig = false;
  bool _isExportingMigrationData = false;
  bool _isImportingMigrationData = false;
  String? _errorMessage;
  AdminConfigResult? _configResult;

  bool get isLoading => _isLoading;

  bool get isSavingSiteConfig => _isSavingSiteConfig;

  bool get isFetchingSubscriptionConfig => _isFetchingSubscriptionConfig;

  bool get isSavingConfigFile => _isSavingConfigFile;

  bool get isResettingConfig => _isResettingConfig;

  bool get isExportingMigrationData => _isExportingMigrationData;

  bool get isImportingMigrationData => _isImportingMigrationData;

  String? get errorMessage => _errorMessage;

  AdminConfigResult? get configResult => _configResult;

  AdminRole? get role => _configResult?.role;

  bool get isOwner => role == AdminRole.owner;

  Future<void> loadConfig({bool showLoader = true}) async {
    if (showLoader) {
      _isLoading = true;
      _errorMessage = null;
      notifyListeners();
    }

    final response = await _adminService.fetchConfig();

    if (response.success && response.data != null) {
      _configResult = response.data;
      _errorMessage = null;
    } else {
      _errorMessage = response.message ?? '加载管理面板失败';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<bool> saveSiteConfig(AdminSiteConfig siteConfig) async {
    _isSavingSiteConfig = true;
    _errorMessage = null;
    notifyListeners();

    final response = await _adminService.updateSiteConfig(siteConfig);

    if (!response.success) {
      _isSavingSiteConfig = false;
      _errorMessage = response.message ?? '保存站点设置失败';
      notifyListeners();
      return false;
    }

    if (_configResult != null) {
      _configResult = _configResult!.copyWith(
        config: _configResult!.config.copyWith(siteConfig: siteConfig),
      );
    }

    final refreshResponse = await _adminService.fetchConfig();
    if (refreshResponse.success && refreshResponse.data != null) {
      _configResult = refreshResponse.data;
      _errorMessage = null;
    } else {
      _errorMessage = refreshResponse.message ?? '刷新管理配置失败';
    }

    _isSavingSiteConfig = false;
    notifyListeners();
    return refreshResponse.success;
  }

  Future<bool> performUserAction({
    required String action,
    String? targetUsername,
    String? targetPassword,
    String? userGroup,
    List<String>? enabledApis,
    List<String>? userGroups,
    String? groupAction,
    String? groupName,
    List<String>? usernames,
  }) async {
    _errorMessage = null;
    notifyListeners();

    final response = await _adminService.performUserAction(
      action: action,
      targetUsername: targetUsername,
      targetPassword: targetPassword,
      userGroup: userGroup,
      enabledApis: enabledApis,
      userGroups: userGroups,
      groupAction: groupAction,
      groupName: groupName,
      usernames: usernames,
    );

    if (!response.success) {
      _errorMessage = response.message ?? '用户管理操作失败';
      notifyListeners();
      return false;
    }

    await _refreshConfigSilently();
    return _errorMessage == null;
  }

  Future<bool> performSourceAction({
    required String action,
    String? key,
    String? name,
    String? api,
    String? detail,
    List<String>? keys,
    List<String>? order,
  }) async {
    _errorMessage = null;
    notifyListeners();

    final response = await _adminService.performSourceAction(
      action: action,
      key: key,
      name: name,
      api: api,
      detail: detail,
      keys: keys,
      order: order,
    );

    if (!response.success) {
      _errorMessage = response.message ?? '视频源操作失败';
      notifyListeners();
      return false;
    }

    await _refreshConfigSilently();
    return _errorMessage == null;
  }

  Future<bool> performLiveSourceAction({
    required String action,
    String? key,
    String? name,
    String? url,
    String? ua,
    String? epg,
    List<String>? order,
  }) async {
    _errorMessage = null;
    notifyListeners();

    final response = await _adminService.performLiveSourceAction(
      action: action,
      key: key,
      name: name,
      url: url,
      ua: ua,
      epg: epg,
      order: order,
    );

    if (!response.success) {
      _errorMessage = response.message ?? '直播源操作失败';
      notifyListeners();
      return false;
    }

    await _refreshConfigSilently();
    return _errorMessage == null;
  }

  Future<bool> refreshLiveSources() async {
    _errorMessage = null;
    notifyListeners();

    final response = await _adminService.refreshLiveSources();
    if (!response.success) {
      _errorMessage = response.message ?? '刷新直播源失败';
      notifyListeners();
      return false;
    }

    await _refreshConfigSilently();
    return _errorMessage == null;
  }

  Future<bool> performCategoryAction({
    required String action,
    String? name,
    String? type,
    String? query,
    List<String>? order,
  }) async {
    _errorMessage = null;
    notifyListeners();

    final response = await _adminService.performCategoryAction(
      action: action,
      name: name,
      type: type,
      query: query,
      order: order,
    );

    if (!response.success) {
      _errorMessage = response.message ?? '分类操作失败';
      notifyListeners();
      return false;
    }

    await _refreshConfigSilently();
    return _errorMessage == null;
  }

  Future<String?> fetchConfigSubscription(String url) async {
    _isFetchingSubscriptionConfig = true;
    _errorMessage = null;
    notifyListeners();

    final response = await _adminService.fetchConfigSubscription(url);
    _isFetchingSubscriptionConfig = false;

    if (!response.success || response.data == null) {
      _errorMessage = response.message ?? '拉取配置订阅失败';
      notifyListeners();
      return null;
    }

    notifyListeners();
    return response.data;
  }

  Future<bool> saveConfigFile({
    required String configFile,
    required String subscriptionUrl,
    required bool autoUpdate,
    required String lastCheckTime,
  }) async {
    _isSavingConfigFile = true;
    _errorMessage = null;
    notifyListeners();

    final response = await _adminService.saveConfigFile(
      configFile: configFile,
      subscriptionUrl: subscriptionUrl,
      autoUpdate: autoUpdate,
      lastCheckTime: lastCheckTime,
    );

    _isSavingConfigFile = false;
    if (!response.success) {
      _errorMessage = response.message ?? '保存配置文件失败';
      notifyListeners();
      return false;
    }

    await _refreshConfigSilently();
    return _errorMessage == null;
  }

  Future<bool> resetConfig() async {
    _isResettingConfig = true;
    _errorMessage = null;
    notifyListeners();

    final response = await _adminService.resetConfig();

    _isResettingConfig = false;
    if (!response.success) {
      _errorMessage = response.message ?? '重置配置失败';
      notifyListeners();
      return false;
    }

    await _refreshConfigSilently();
    return _errorMessage == null;
  }

  Future<bool> exportMigrationData(String password) async {
    _isExportingMigrationData = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final DataMigrationExportPayload payload =
          await _dataMigrationService.exportData(password);
      final bool saved = await _nativeFileAccessService.saveExportFile(
        bytes: payload.bytes,
        suggestedName: payload.fileName,
      );
      _isExportingMigrationData = false;
      if (!saved) {
        notifyListeners();
        return false;
      }
      notifyListeners();
      return true;
    } catch (error) {
      _isExportingMigrationData = false;
      _errorMessage = error.toString();
      notifyListeners();
      return false;
    }
  }

  Future<DataMigrationImportResult?> importMigrationData(
      String password) async {
    _isImportingMigrationData = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final NativePickedFile? pickedFile =
          await _nativeFileAccessService.pickImportFile();
      if (pickedFile == null) {
        _isImportingMigrationData = false;
        notifyListeners();
        return null;
      }

      final DataMigrationImportResult result =
          await _dataMigrationService.importData(
        bytes: pickedFile.bytes,
        fileName: pickedFile.name,
        password: password,
      );
      _isImportingMigrationData = false;
      await _refreshConfigSilently();
      return result;
    } catch (error) {
      _isImportingMigrationData = false;
      _errorMessage = error.toString();
      notifyListeners();
      return null;
    }
  }

  Future<void> _refreshConfigSilently() async {
    final refreshResponse = await _adminService.fetchConfig();
    if (refreshResponse.success && refreshResponse.data != null) {
      _configResult = refreshResponse.data;
      _errorMessage = null;
    } else {
      _errorMessage = refreshResponse.message ?? '刷新管理配置失败';
    }
    notifyListeners();
  }
}
