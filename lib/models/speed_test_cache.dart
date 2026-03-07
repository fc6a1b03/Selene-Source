// 测速缓存数据模型
// 用于缓存直播频道的测速结果

/// 单个频道的测速缓存数据
class SpeedTestCacheItem {
  final String channelId; // 频道ID
  final bool isAvailable; // 是否可用
  final int latencyMs; // 延迟毫秒数，-1表示不可用
  final DateTime testTime; // 测速时间

  const SpeedTestCacheItem({
    required this.channelId,
    required this.isAvailable,
    required this.latencyMs,
    required this.testTime,
  });

  /// 从 JSON 创建
  factory SpeedTestCacheItem.fromJson(Map<String, dynamic> json) {
    return SpeedTestCacheItem(
      channelId: json['channelId'] as String? ?? '',
      isAvailable: json['isAvailable'] as bool? ?? false,
      latencyMs: json['latencyMs'] as int? ?? -1,
      testTime: DateTime.fromMillisecondsSinceEpoch(
        json['testTime'] as int? ?? 0,
      ),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'channelId': channelId,
      'isAvailable': isAvailable,
      'latencyMs': latencyMs,
      'testTime': testTime.millisecondsSinceEpoch,
    };
  }

  /// 检查缓存是否过期
  bool isExpired(Duration maxAge) {
    return DateTime.now().difference(testTime) > maxAge;
  }

  /// 复制并修改
  SpeedTestCacheItem copyWith({
    String? channelId,
    bool? isAvailable,
    int? latencyMs,
    DateTime? testTime,
  }) {
    return SpeedTestCacheItem(
      channelId: channelId ?? this.channelId,
      isAvailable: isAvailable ?? this.isAvailable,
      latencyMs: latencyMs ?? this.latencyMs,
      testTime: testTime ?? this.testTime,
    );
  }
}

/// 测速缓存组（按直播源分组）
class SpeedTestCacheGroup {
  final String sourceKey; // 直播源key
  final String sourceUrl; // 直播源URL（用于检测源是否变化）
  final List<SpeedTestCacheItem> items; // 该源下的所有测速缓存
  final DateTime lastUpdated; // 最后更新时间

  const SpeedTestCacheGroup({
    required this.sourceKey,
    required this.sourceUrl,
    required this.items,
    required this.lastUpdated,
  });

  /// 从 JSON 创建
  factory SpeedTestCacheGroup.fromJson(Map<String, dynamic> json) {
    final itemsList = json['items'] as List<dynamic>? ?? [];
    return SpeedTestCacheGroup(
      sourceKey: json['sourceKey'] as String? ?? '',
      sourceUrl: json['sourceUrl'] as String? ?? '',
      items: itemsList
          .map((item) =>
              SpeedTestCacheItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(
        json['lastUpdated'] as int? ?? 0,
      ),
    );
  }

  /// 转换为 JSON
  Map<String, dynamic> toJson() {
    return {
      'sourceKey': sourceKey,
      'sourceUrl': sourceUrl,
      'items': items.map((item) => item.toJson()).toList(),
      'lastUpdated': lastUpdated.millisecondsSinceEpoch,
    };
  }

  /// 检查缓存是否过期
  bool isExpired(Duration maxAge) {
    return DateTime.now().difference(lastUpdated) > maxAge;
  }

  /// 检查源URL是否匹配
  /// 使用宽松匹配，忽略首尾空格和大小写差异
  bool isSourceUrlMatch(String url) {
    final normalizedCached = sourceUrl.trim().toLowerCase();
    final normalizedNew = url.trim().toLowerCase();
    return normalizedCached == normalizedNew;
  }

  /// 获取指定频道的缓存
  SpeedTestCacheItem? getItem(String channelId) {
    try {
      return items.firstWhere((item) => item.channelId == channelId);
    } catch (e) {
      return null;
    }
  }
}
