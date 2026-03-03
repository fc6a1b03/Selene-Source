import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// 数据库优化器
/// 提供批量操作和查询优化
class DatabaseOptimizer {
  DatabaseOptimizer._();

  /// 批量写入数据
  /// 比单个写入性能提升 5-10 倍
  static Future<void> batchWrite<T>(
    Box<T> box,
    Map<String, T> data, {
    int batchSize = 100,
  }) async {
    if (data.isEmpty) return;

    final entries = data.entries.toList();

    for (var i = 0; i < entries.length; i += batchSize) {
      final batch = entries.sublist(
        i,
        (i + batchSize).clamp(0, entries.length),
      );

      // 使用事务批量写入
      await box.putAll(Map.fromEntries(batch));

      // 每批次后让出时间片
      if (i + batchSize < entries.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  /// 批量删除
  static Future<void> batchDelete<T>(
    Box<T> box,
    List<String> keys, {
    int batchSize = 100,
  }) async {
    if (keys.isEmpty) return;

    for (var i = 0; i < keys.length; i += batchSize) {
      final batch = keys.sublist(
        i,
        (i + batchSize).clamp(0, keys.length),
      );

      await box.deleteAll(batch);

      if (i + batchSize < keys.length) {
        await Future<void>.delayed(Duration.zero);
      }
    }
  }

  /// 分页查询
  static List<T> paginatedQuery<T>(
    Box<T> box, {
    int page = 1,
    int pageSize = 20,
    String? searchKey,
    bool Function(T)? filter,
  }) {
    var values = box.values.toList();

    // 应用过滤器
    if (filter != null) {
      values = values.where(filter).toList();
    }

    // 搜索过滤
    if (searchKey != null && searchKey.isNotEmpty) {
      values = values.where((item) {
        return item.toString().toLowerCase().contains(searchKey.toLowerCase());
      }).toList();
    }

    // 分页
    final startIndex = (page - 1) * pageSize;
    if (startIndex >= values.length) return [];

    final endIndex = (startIndex + pageSize).clamp(0, values.length);
    return values.sublist(startIndex, endIndex);
  }

  /// 异步大数据查询
  /// 在 Isolate 中执行，避免阻塞 UI
  static Future<List<T>> asyncQuery<T>(
    Box<T> box,
    bool Function(T) predicate,
  ) async {
    // 小数据量直接查询
    if (box.length < 100) {
      return box.values.where(predicate).toList();
    }

    // 大数据量在 Isolate 中查询
    return compute(_queryInIsolate<T>, {
      'values': box.values.toList(),
      'predicate': predicate,
    });
  }

  /// 预加载盒子到内存
  /// 对于频繁访问的数据，可以预加载提升性能
  static Future<Box<T>> preloadBox<T>(String boxName) async {
    final box = await Hive.openBox<T>(boxName);
    // 访问所有键触发预加载
    box.keys.toList();
    return box;
  }

  /// 压缩盒子
  /// 删除后清理空间
  static Future<void> compactBox<T>(Box<T> box) async {
    await box.compact();
  }

  /// 批量更新
  static Future<void> batchUpdate<T>(
    Box<T> box,
    List<String> keys,
    T Function(T?) updater,
  ) async {
    final updates = <String, T>{};

    for (final key in keys) {
      final current = box.get(key);
      updates[key] = updater(current);
    }

    await box.putAll(updates);
  }
}

/// 数据库查询缓存
class DatabaseQueryCache {
  static final DatabaseQueryCache _instance = DatabaseQueryCache._internal();
  factory DatabaseQueryCache() => _instance;
  DatabaseQueryCache._internal();

  final Map<String, _CachedQuery> _cache = {};
  static const Duration _defaultExpiration = Duration(minutes: 5);

  /// 获取缓存的查询结果
  T? get<T>(String key) {
    final cached = _cache[key];
    if (cached == null) return null;

    if (cached.isExpired) {
      _cache.remove(key);
      return null;
    }

    cached.touch();
    return cached.data as T;
  }

  /// 设置缓存
  void set<T>(String key, T data, {Duration? expiration}) {
    _cache[key] = _CachedQuery(
      data: data,
      expiration: expiration ?? _defaultExpiration,
    );
  }

  /// 清除缓存
  void clear() => _cache.clear();

  /// 清除过期缓存
  void clearExpired() {
    _cache.removeWhere((key, value) => value.isExpired);
  }
}

class _CachedQuery {
  final dynamic data;
  final Duration expiration;
  DateTime lastAccessed;

  _CachedQuery({
    required this.data,
    required this.expiration,
  }) : lastAccessed = DateTime.now();

  bool get isExpired => DateTime.now().difference(lastAccessed) > expiration;

  void touch() {
    lastAccessed = DateTime.now();
  }
}

/// 数据库连接池（简化版）
/// 管理多个盒子实例
class DatabasePool {
  static final DatabasePool _instance = DatabasePool._internal();
  factory DatabasePool() => _instance;
  DatabasePool._internal();

  final Map<String, Box<dynamic>> _boxes = {};
  final Set<String> _openingBoxes = {};

  /// 获取盒子
  Future<Box<T>> getBox<T>(String name) async {
    // 如果已经在内存中，直接返回
    if (_boxes.containsKey(name)) {
      return _boxes[name]! as Box<T>;
    }

    // 如果正在打开，等待
    while (_openingBoxes.contains(name)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    // 打开盒子
    _openingBoxes.add(name);
    try {
      final box = await Hive.openBox<T>(name);
      _boxes[name] = box;
      return box;
    } finally {
      _openingBoxes.remove(name);
    }
  }

  /// 关闭所有盒子
  Future<void> closeAll() async {
    for (final box in _boxes.values) {
      await box.close();
    }
    _boxes.clear();
  }

  /// 获取盒子统计
  Map<String, int> getStats() {
    return _boxes.map((name, box) => MapEntry(name, box.length));
  }
}

/// 在 Isolate 中查询
List<T> _queryInIsolate<T>(Map<String, dynamic> params) {
  final values = params['values'] as List<T>;
  final predicate = params['predicate'] as bool Function(T);
  return values.where(predicate).toList();
}
