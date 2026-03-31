class AdminConfigResult {
  const AdminConfigResult({
    required this.role,
    required this.config,
  });

  factory AdminConfigResult.fromJson(Map<String, dynamic> json) =>
      AdminConfigResult(
        role: AdminRole.fromJson(_asString(json['Role'], fallback: 'owner')),
        config: AdminConfig.fromJson(_asMap(json['Config'])),
      );

  final AdminRole role;
  final AdminConfig config;

  AdminConfigResult copyWith({
    AdminRole? role,
    AdminConfig? config,
  }) {
    return AdminConfigResult(
      role: role ?? this.role,
      config: config ?? this.config,
    );
  }
}

enum AdminRole {
  owner,
  admin;

  factory AdminRole.fromJson(String value) {
    switch (value) {
      case 'admin':
        return AdminRole.admin;
      case 'owner':
      default:
        return AdminRole.owner;
    }
  }

  String get label {
    switch (this) {
      case AdminRole.owner:
        return '站长';
      case AdminRole.admin:
        return '管理员';
    }
  }
}

class AdminConfig {
  const AdminConfig({
    required this.configSubscription,
    required this.configFile,
    required this.siteConfig,
    required this.userConfig,
    required this.sourceConfig,
    required this.customCategories,
    required this.liveConfig,
  });

  factory AdminConfig.fromJson(Map<String, dynamic> json) {
    return AdminConfig(
      configSubscription: AdminConfigSubscription.fromJson(
        _asMap(json['ConfigSubscribtion']),
      ),
      configFile: _asString(json['ConfigFile']),
      siteConfig: AdminSiteConfig.fromJson(_asMap(json['SiteConfig'])),
      userConfig: AdminUserConfig.fromJson(_asMap(json['UserConfig'])),
      sourceConfig: _asMapList(json['SourceConfig'])
          .map(AdminSourceConfig.fromJson)
          .toList(growable: false),
      customCategories: _asMapList(json['CustomCategories'])
          .map(AdminCategoryConfig.fromJson)
          .toList(growable: false),
      liveConfig: _asMapList(json['LiveConfig'])
          .map(AdminLiveSourceConfig.fromJson)
          .toList(growable: false),
    );
  }

  final AdminConfigSubscription configSubscription;
  final String configFile;
  final AdminSiteConfig siteConfig;
  final AdminUserConfig userConfig;
  final List<AdminSourceConfig> sourceConfig;
  final List<AdminCategoryConfig> customCategories;
  final List<AdminLiveSourceConfig> liveConfig;

  int get bannedUserCount =>
      userConfig.users.where((user) => user.banned).length;

  int get disabledSourceCount =>
      sourceConfig.where((source) => source.disabled).length;

  int get disabledLiveSourceCount =>
      liveConfig.where((source) => source.disabled).length;

  int get disabledCategoryCount =>
      customCategories.where((category) => category.disabled).length;

  AdminConfig copyWith({
    AdminConfigSubscription? configSubscription,
    String? configFile,
    AdminSiteConfig? siteConfig,
    AdminUserConfig? userConfig,
    List<AdminSourceConfig>? sourceConfig,
    List<AdminCategoryConfig>? customCategories,
    List<AdminLiveSourceConfig>? liveConfig,
  }) {
    return AdminConfig(
      configSubscription: configSubscription ?? this.configSubscription,
      configFile: configFile ?? this.configFile,
      siteConfig: siteConfig ?? this.siteConfig,
      userConfig: userConfig ?? this.userConfig,
      sourceConfig: sourceConfig ?? this.sourceConfig,
      customCategories: customCategories ?? this.customCategories,
      liveConfig: liveConfig ?? this.liveConfig,
    );
  }
}

class AdminConfigSubscription {
  const AdminConfigSubscription({
    required this.url,
    required this.autoUpdate,
    required this.lastCheck,
  });

  factory AdminConfigSubscription.fromJson(Map<String, dynamic> json) {
    return AdminConfigSubscription(
      url: _asString(json['URL']),
      autoUpdate: _asBool(json['AutoUpdate']),
      lastCheck: _asString(json['LastCheck']),
    );
  }

  final String url;
  final bool autoUpdate;
  final String lastCheck;
}

class AdminSiteConfig {
  const AdminSiteConfig({
    required this.siteName,
    required this.announcement,
    required this.searchDownstreamMaxPage,
    required this.siteInterfaceCacheTime,
    required this.doubanProxyType,
    required this.doubanProxy,
    required this.doubanImageProxyType,
    required this.doubanImageProxy,
    required this.disableYellowFilter,
    required this.fluidSearch,
  });

  factory AdminSiteConfig.fromJson(Map<String, dynamic> json) {
    return AdminSiteConfig(
      siteName: _asString(json['SiteName']),
      announcement: _asString(json['Announcement']),
      searchDownstreamMaxPage:
          _asInt(json['SearchDownstreamMaxPage'], fallback: 1),
      siteInterfaceCacheTime:
          _asInt(json['SiteInterfaceCacheTime'], fallback: 7200),
      doubanProxyType:
          _asString(json['DoubanProxyType'], fallback: 'cmliussss-cdn-tencent'),
      doubanProxy: _asString(json['DoubanProxy']),
      doubanImageProxyType: _asString(
        json['DoubanImageProxyType'],
        fallback: 'cmliussss-cdn-tencent',
      ),
      doubanImageProxy: _asString(json['DoubanImageProxy']),
      disableYellowFilter: _asBool(json['DisableYellowFilter']),
      fluidSearch: _asBool(json['FluidSearch'], fallback: true),
    );
  }

  final String siteName;
  final String announcement;
  final int searchDownstreamMaxPage;
  final int siteInterfaceCacheTime;
  final String doubanProxyType;
  final String doubanProxy;
  final String doubanImageProxyType;
  final String doubanImageProxy;
  final bool disableYellowFilter;
  final bool fluidSearch;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'SiteName': siteName,
      'Announcement': announcement,
      'SearchDownstreamMaxPage': searchDownstreamMaxPage,
      'SiteInterfaceCacheTime': siteInterfaceCacheTime,
      'DoubanProxyType': doubanProxyType,
      'DoubanProxy': doubanProxy,
      'DoubanImageProxyType': doubanImageProxyType,
      'DoubanImageProxy': doubanImageProxy,
      'DisableYellowFilter': disableYellowFilter,
      'FluidSearch': fluidSearch,
    };
  }

  AdminSiteConfig copyWith({
    String? siteName,
    String? announcement,
    int? searchDownstreamMaxPage,
    int? siteInterfaceCacheTime,
    String? doubanProxyType,
    String? doubanProxy,
    String? doubanImageProxyType,
    String? doubanImageProxy,
    bool? disableYellowFilter,
    bool? fluidSearch,
  }) {
    return AdminSiteConfig(
      siteName: siteName ?? this.siteName,
      announcement: announcement ?? this.announcement,
      searchDownstreamMaxPage:
          searchDownstreamMaxPage ?? this.searchDownstreamMaxPage,
      siteInterfaceCacheTime:
          siteInterfaceCacheTime ?? this.siteInterfaceCacheTime,
      doubanProxyType: doubanProxyType ?? this.doubanProxyType,
      doubanProxy: doubanProxy ?? this.doubanProxy,
      doubanImageProxyType: doubanImageProxyType ?? this.doubanImageProxyType,
      doubanImageProxy: doubanImageProxy ?? this.doubanImageProxy,
      disableYellowFilter: disableYellowFilter ?? this.disableYellowFilter,
      fluidSearch: fluidSearch ?? this.fluidSearch,
    );
  }
}

class AdminUserConfig {
  const AdminUserConfig({
    required this.users,
    required this.groups,
  });

  factory AdminUserConfig.fromJson(Map<String, dynamic> json) {
    return AdminUserConfig(
      users: _asMapList(json['Users'])
          .map(AdminUser.fromJson)
          .toList(growable: false),
      groups: _asMapList(json['Tags'])
          .map(AdminUserGroup.fromJson)
          .toList(growable: false),
    );
  }

  final List<AdminUser> users;
  final List<AdminUserGroup> groups;
}

class AdminUser {
  const AdminUser({
    required this.username,
    required this.role,
    required this.banned,
    required this.enabledApis,
    required this.tags,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      username: _asString(json['username']),
      role: AdminUserRole.fromJson(_asString(json['role'], fallback: 'user')),
      banned: _asBool(json['banned']),
      enabledApis: _asStringList(json['enabledApis']),
      tags: _asStringList(json['tags']),
    );
  }

  final String username;
  final AdminUserRole role;
  final bool banned;
  final List<String> enabledApis;
  final List<String> tags;
}

enum AdminUserRole {
  owner,
  admin,
  user;

  factory AdminUserRole.fromJson(String value) {
    switch (value) {
      case 'owner':
        return AdminUserRole.owner;
      case 'admin':
        return AdminUserRole.admin;
      case 'user':
      default:
        return AdminUserRole.user;
    }
  }

  String get label {
    switch (this) {
      case AdminUserRole.owner:
        return '站长';
      case AdminUserRole.admin:
        return '管理员';
      case AdminUserRole.user:
        return '用户';
    }
  }
}

class AdminUserGroup {
  const AdminUserGroup({
    required this.name,
    required this.enabledApis,
  });

  factory AdminUserGroup.fromJson(Map<String, dynamic> json) {
    return AdminUserGroup(
      name: _asString(json['name']),
      enabledApis: _asStringList(json['enabledApis']),
    );
  }

  final String name;
  final List<String> enabledApis;
}

class AdminSourceConfig {
  const AdminSourceConfig({
    required this.key,
    required this.name,
    required this.api,
    required this.detail,
    required this.from,
    required this.disabled,
  });

  factory AdminSourceConfig.fromJson(Map<String, dynamic> json) {
    return AdminSourceConfig(
      key: _asString(json['key']),
      name: _asString(json['name']),
      api: _asString(json['api']),
      detail: _asString(json['detail']),
      from: _asString(json['from'], fallback: 'config'),
      disabled: _asBool(json['disabled']),
    );
  }

  final String key;
  final String name;
  final String api;
  final String detail;
  final String from;
  final bool disabled;

  bool get isCustom => from == 'custom';
}

class AdminCategoryConfig {
  const AdminCategoryConfig({
    required this.name,
    required this.type,
    required this.query,
    required this.from,
    required this.disabled,
  });

  factory AdminCategoryConfig.fromJson(Map<String, dynamic> json) {
    return AdminCategoryConfig(
      name: _asString(json['name']),
      type: _asString(json['type'], fallback: 'movie'),
      query: _asString(json['query']),
      from: _asString(json['from'], fallback: 'config'),
      disabled: _asBool(json['disabled']),
    );
  }

  final String name;
  final String type;
  final String query;
  final String from;
  final bool disabled;
}

class AdminLiveSourceConfig {
  const AdminLiveSourceConfig({
    required this.key,
    required this.name,
    required this.url,
    required this.ua,
    required this.epg,
    required this.from,
    required this.channelNumber,
    required this.disabled,
  });

  factory AdminLiveSourceConfig.fromJson(Map<String, dynamic> json) {
    return AdminLiveSourceConfig(
      key: _asString(json['key']),
      name: _asString(json['name']),
      url: _asString(json['url']),
      ua: _asString(json['ua']),
      epg: _asString(json['epg']),
      from: _asString(json['from'], fallback: 'config'),
      channelNumber: _asInt(json['channelNumber']),
      disabled: _asBool(json['disabled']),
    );
  }

  final String key;
  final String name;
  final String url;
  final String ua;
  final String epg;
  final String from;
  final int channelNumber;
  final bool disabled;

  bool get isCustom => from == 'custom';
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (dynamic key, dynamic entryValue) => MapEntry(key.toString(), entryValue),
    );
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is! List) {
    return const <Map<String, dynamic>>[];
  }
  return value.map((dynamic item) => _asMap(item)).toList(growable: false);
}

List<String> _asStringList(dynamic value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((dynamic item) => item.toString()).toList(growable: false);
}

String _asString(dynamic value, {String fallback = ''}) {
  if (value is String) {
    return value;
  }
  return fallback;
}

int _asInt(dynamic value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value) ?? fallback;
  }
  return fallback;
}

bool _asBool(dynamic value, {bool fallback = false}) {
  if (value is bool) {
    return value;
  }
  if (value is String) {
    switch (value.toLowerCase()) {
      case 'true':
        return true;
      case 'false':
        return false;
      default:
        return fallback;
    }
  }
  return fallback;
}
