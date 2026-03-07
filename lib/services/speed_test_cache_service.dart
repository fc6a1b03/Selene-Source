import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:selene/models/speed_test_cache.dart';

/// 测速缓存服务
/// 管理直播频道测速结果的缓存，支持3天缓存期
class SpeedTestCacheService {
  static const String _boxName = 'speed_test_cache';
  static const Duration _cacheDuration = Duration(days: 3);

  static Box<SpeedTestCacheGroup>? _box;

  /// 初始化服务
  static Future<void> init() async {
    _box = Hive.box<SpeedTestCacheGroup>(_boxName);
    // 启动时清理过期缓存
    await _cleanExpiredCache();
  }

  /// 获取缓存盒子
  static Box<SpeedTestCacheGroup> _getBox() {
    _box ??= Hive.box<SpeedTestCacheGroup>(_boxName);
    return _box!;
  }

  /// 获取指定直播源的测速缓存
  ///
  /// [sourceKey] 直播源 key
  /// [sourceUrl] 直播源 URL（可选，用于验证源是否变化）
  /// Returns 缓存组，如果不存在、已过期或URL不匹配返回 null
  static SpeedTestCacheGroup? getCache(String sourceKey, {String? sourceUrl}) {
    final box = _getBox();
    final cache = box.get(sourceKey);

    if (cache == null) {
      return null;
    }

    // 检查是否过期
    if (cache.isExpired(_cacheDuration)) {
      debugPrint('测速缓存已过期: $sourceKey');
      return null;
    }

    // 如果提供了源URL，检查是否匹配（规范化传入的URL）
    if (sourceUrl != null && !cache.isSourceUrlMatch(sourceUrl.trim())) {
      debugPrint('测速缓存源地址已变化: $sourceKey');
      debugPrint('  缓存URL: ${cache.sourceUrl}');
      debugPrint('  当前URL: ${sourceUrl.trim()}');
      // 异步清理不匹配的缓存
      clearCache(sourceKey);
      return null;
    }

    return cache;
  }

  /// 获取指定频道的测速缓存
  ///
  /// [sourceKey] 直播源 key
  /// [channelId] 频道ID
  /// [sourceUrl] 直播源 URL（可选，用于验证源是否变化）
  /// Returns 缓存项，如果不存在或已过期返回 null
  static SpeedTestCacheItem? getChannelCache(
    String sourceKey,
    String channelId, {
    String? sourceUrl,
  }) {
    final groupCache = getCache(sourceKey, sourceUrl: sourceUrl);
    if (groupCache == null) {
      return null;
    }

    final item = groupCache.getItem(channelId);
    if (item == null) {
      return null;
    }

    // 检查单个频道缓存是否过期（虽然组级别已经检查过）
    if (item.isExpired(_cacheDuration)) {
      return null;
    }

    return item;
  }

  /// 批量获取测速缓存
  ///
  /// [sourceKey] 直播源 key
  /// [channelIds] 频道ID列表
  /// [sourceUrl] 直播源 URL（可选，用于验证源是否变化）
  /// Returns 频道ID到缓存项的映射
  static Map<String, SpeedTestCacheItem> getBatchCache(
    String sourceKey,
    List<String> channelIds, {
    String? sourceUrl,
  }) {
    final result = <String, SpeedTestCacheItem>{};
    final groupCache = getCache(sourceKey, sourceUrl: sourceUrl);

    if (groupCache == null) {
      return result;
    }

    for (final channelId in channelIds) {
      final item = groupCache.getItem(channelId);
      if (item != null && !item.isExpired(_cacheDuration)) {
        result[channelId] = item;
      }
    }

    return result;
  }

  /// 保存测速缓存
  ///
  /// [sourceKey] 直播源 key
  /// [sourceUrl] 直播源 URL（用于检测源是否变化）
  /// [availability] 频道可用性映射 {channelId: isAvailable}
  /// [latency] 频道延迟映射 {channelId: latencyMs}
  static Future<void> saveCache(
    String sourceKey,
    String sourceUrl,
    Map<String, bool> availability,
    Map<String, int> latency,
  ) async {
    final box = _getBox();
    final now = DateTime.now();

    // URL 规范化：去除首尾空格
    final normalizedUrl = sourceUrl.trim();

    // 构建缓存项列表
    final items = <SpeedTestCacheItem>[];

    // 合并 availability 和 latency 中的所有频道ID
    final allChannelIds = <String>{}
      ..addAll(availability.keys)
      ..addAll(latency.keys);

    for (final channelId in allChannelIds) {
      final isAvailable = availability[channelId] ?? false;
      final latencyMs = latency[channelId] ?? -1;

      items.add(SpeedTestCacheItem(
        channelId: channelId,
        isAvailable: isAvailable,
        latencyMs: isAvailable ? latencyMs : -1,
        testTime: now,
      ));
    }

    // 创建缓存组
    final cacheGroup = SpeedTestCacheGroup(
      sourceKey: sourceKey,
      sourceUrl: normalizedUrl,
      items: items,
      lastUpdated: now,
    );

    // 保存到 Hive
    await box.put(sourceKey, cacheGroup);
    debugPrint(
        '测速缓存已保存: $sourceKey, URL: $normalizedUrl, 共 ${items.length} 个频道');
  }

  /// 清理指定直播源的缓存
  ///
  /// [sourceKey] 直播源 key
  static Future<void> clearCache(String sourceKey) async {
    final box = _getBox();
    await box.delete(sourceKey);
    debugPrint('测速缓存已清除: $sourceKey');
  }

  /// 清理所有缓存
  static Future<void> clearAllCache() async {
    final box = _getBox();
    await box.clear();
    debugPrint('所有测速缓存已清除');
  }

  /// 清理过期缓存
  static Future<void> _cleanExpiredCache() async {
    final box = _getBox();
    final keysToDelete = <String>[];

    for (final entry in box.toMap().entries) {
      final sourceKey = entry.key;
      final cache = entry.value;

      if (cache.isExpired(_cacheDuration)) {
        keysToDelete.add(sourceKey);
      }
    }

    for (final key in keysToDelete) {
      await box.delete(key);
    }

    if (keysToDelete.isNotEmpty) {
      debugPrint('已清理 ${keysToDelete.length} 个过期测速缓存');
    }
  }

  /// 获取缓存统计信息
  ///
  /// [sourceKey] 直播源 key（可选，不提供则返回全部统计）
  /// Returns 统计信息 {totalSources: 总源数, totalChannels: 总频道数, expiredSources: 过期源数}
  static Map<String, int> getCacheStats({String? sourceKey}) {
    final box = _getBox();

    if (sourceKey != null) {
      final cache = box.get(sourceKey);
      if (cache == null) {
        return {
          'totalSources': 0,
          'totalChannels': 0,
          'expiredSources': 0,
        };
      }

      final isExpired = cache.isExpired(_cacheDuration);
      return {
        'totalSources': 1,
        'totalChannels': cache.items.length,
        'expiredSources': isExpired ? 1 : 0,
      };
    }

    // 统计全部
    var totalSources = 0;
    var totalChannels = 0;
    var expiredSources = 0;

    for (final cache in box.values) {
      totalSources++;
      totalChannels += cache.items.length;
      if (cache.isExpired(_cacheDuration)) {
        expiredSources++;
      }
    }

    return {
      'totalSources': totalSources,
      'totalChannels': totalChannels,
      'expiredSources': expiredSources,
    };
  }

  /// 检查指定直播源的缓存是否存在且未过期
  ///
  /// [sourceKey] 直播源 key
  /// [sourceUrl] 直播源 URL（可选，用于验证源是否变化）
  static bool hasValidCache(String sourceKey, {String? sourceUrl}) {
    final cache = getCache(sourceKey, sourceUrl: sourceUrl);
    return cache != null;
  }

  /// 获取缓存剩余有效时间
  ///
  /// [sourceKey] 直播源 key
  /// Returns 剩余时间，如果没有缓存返回 null
  static Duration? getCacheRemainingTime(String sourceKey) {
    final cache = getCache(sourceKey);
    if (cache == null) {
      return null;
    }

    final elapsed = DateTime.now().difference(cache.lastUpdated);
    final remaining = _cacheDuration - elapsed;

    return remaining.isNegative ? Duration.zero : remaining;
  }
}
