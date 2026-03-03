import 'dart:async';

import 'package:flutter/foundation.dart';

/// Isolate 工具类
/// 提供在 Isolate 中执行耗时操作的方法
class IsolateUtils {
  IsolateUtils._();

  /// 在 Isolate 中解析 JSON
  /// [jsonString] JSON 字符串
  /// [parser] 解析函数
  static Future<T> parseJson<T>(
    String jsonString,
    T Function(dynamic) parser,
  ) async {
    // 小数据量直接在主线程处理
    if (jsonString.length < 10000) {
      return parser(jsonString);
    }

    // 大数据量使用 Isolate
    return compute(_parseJsonIsolate, {
      'json': jsonString,
      'parser': parser,
    });
  }

  /// 在 Isolate 中批量处理数据
  /// [items] 数据列表
  /// [processor] 处理函数
  static Future<List<R>> processBatch<T, R>(
    List<T> items,
    R Function(T) processor,
  ) async {
    // 小批量直接在主线程处理
    if (items.length < 100) {
      return items.map(processor).toList();
    }

    // 大批量分批处理
    final batchSize = 500;
    final results = <R>[];

    for (var i = 0; i < items.length; i += batchSize) {
      final batch = items.skip(i).take(batchSize).toList();
      final batchResults = await compute(_processBatchIsolate<T, R>, {
        'items': batch,
        'processor': processor,
      });
      results.addAll(batchResults);
    }

    return results;
  }

  /// 在 Isolate 中执行耗时计算
  /// [computation] 计算函数
  static Future<T> computeTask<T>(FutureOr<T> Function() computation) {
    return compute(_computeIsolate, computation);
  }
}

/// Isolate 中解析 JSON
T _parseJsonIsolate<T>(Map<String, dynamic> params) {
  final jsonString = params['json'] as String;
  final parser = params['parser'] as T Function(dynamic);
  return parser(jsonString);
}

/// Isolate 中批量处理
List<R> _processBatchIsolate<T, R>(Map<String, dynamic> params) {
  final items = params['items'] as List<T>;
  final processor = params['processor'] as R Function(T);
  return items.map(processor).toList();
}

/// Isolate 中执行计算
T _computeIsolate<T>(FutureOr<T> Function() computation) {
  return computation() as T;
}

/// 图片尺寸计算任务
class ImageSizeCalculation {
  final String url;
  final int? maxWidth;
  final int? maxHeight;

  ImageSizeCalculation({
    required this.url,
    this.maxWidth,
    this.maxHeight,
  });
}

/// 缓存计算结果
class ComputedCache<K, V> {
  final Map<K, _ComputedEntry<V>> _cache = {};
  final Duration expiration;

  ComputedCache({this.expiration = const Duration(minutes: 5)});

  V? get(K key) {
    final entry = _cache[key];
    if (entry == null) return null;

    if (DateTime.now().difference(entry.computedAt) > expiration) {
      _cache.remove(key);
      return null;
    }

    return entry.value;
  }

  void set(K key, V value) {
    _cache[key] = _ComputedEntry(value);
  }

  void clear() => _cache.clear();
}

class _ComputedEntry<V> {
  final V value;
  final DateTime computedAt;

  _ComputedEntry(this.value) : computedAt = DateTime.now();
}
