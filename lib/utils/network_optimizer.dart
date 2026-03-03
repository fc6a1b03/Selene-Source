import 'dart:async';
import 'dart:collection';

/// 网络请求优化器
/// 提供请求合并、去重和缓存
class NetworkOptimizer {
  // ignore: unused_element
  NetworkOptimizer._();

  static final NetworkOptimizer _instance = NetworkOptimizer._internal();
  static NetworkOptimizer get instance => _instance;
  NetworkOptimizer._internal();

  // 进行中的请求
  final Map<String, Future<dynamic>> _pendingRequests = {};

  // 请求队列
  final Queue<_QueuedRequest<dynamic>> _requestQueue =
      Queue<_QueuedRequest<dynamic>>();

  // 是否正在处理队列
  bool _isProcessing = false;

  // 最大并发数
  int _maxConcurrent = 5;
  int _currentConcurrent = 0;

  /// 去重请求
  /// 相同的请求如果正在进行中，返回现有的 Future
  Future<T> dedupedRequest<T>(
    String key,
    Future<T> Function() request,
  ) {
    // 如果已有相同请求进行中，复用
    if (_pendingRequests.containsKey(key)) {
      return _pendingRequests[key]! as Future<T>;
    }

    // 创建新请求
    final future = request();
    _pendingRequests[key] = future;

    // 请求完成后移除
    future.whenComplete(() {
      _pendingRequests.remove(key);
    });

    return future;
  }

  /// 添加请求到队列
  Future<T> enqueue<T>(
    Future<T> Function() request, {
    int priority = 0,
    Duration? timeout,
  }) {
    final completer = Completer<T>(); // ignore: strict_raw_type
    final queuedRequest = _QueuedRequest<T>(
      request: request,
      completer: completer,
      priority: priority,
      timeout: timeout,
    );

    _requestQueue.add(queuedRequest);
    _requestQueue.toList().sort((a, b) => b.priority.compareTo(a.priority));

    _processQueue();

    return completer.future;
  }

  /// 处理请求队列
  void _processQueue() async {
    if (_isProcessing || _requestQueue.isEmpty) return;
    if (_currentConcurrent >= _maxConcurrent) return;

    _isProcessing = true;

    while (_requestQueue.isNotEmpty && _currentConcurrent < _maxConcurrent) {
      final _QueuedRequest<dynamic> request = _requestQueue.removeFirst();
      _currentConcurrent++;

      _executeRequest(request);
    }

    _isProcessing = false;
  }

  /// 执行单个请求
  void _executeRequest(_QueuedRequest<dynamic> request) async {
    try {
      Future<dynamic> future = request.request();

      // 添加超时
      if (request.timeout != null) {
        future = future.timeout(request.timeout!);
      }

      final result = await future;
      request.completer.complete(result);
    } catch (e) {
      request.completer.completeError(e);
    } finally {
      _currentConcurrent--;
      // 继续处理队列
      _processQueue();
    }
  }

  /// 设置最大并发数
  void setMaxConcurrent(int max) {
    _maxConcurrent = max;
  }

  /// 清除所有待处理请求
  void clearQueue() {
    for (final request in _requestQueue) {
      request.completer.completeError(Exception('Request cancelled'));
    }
    _requestQueue.clear();
  }

  /// 获取队列状态
  Map<String, int> getStatus() {
    return {
      'pending': _pendingRequests.length,
      'queued': _requestQueue.length,
      'concurrent': _currentConcurrent,
      'maxConcurrent': _maxConcurrent,
    };
  }
}

class _QueuedRequest<T> {
  final Future<T> Function() request;
  final Completer<T> completer;
  final int priority;
  final Duration? timeout;

  _QueuedRequest({
    required this.request,
    required this.completer,
    required this.priority,
    this.timeout,
  });
}

/// 请求缓存
class RequestCache {
  static final RequestCache _instance = RequestCache._internal();
  static RequestCache get instance => _instance;
  RequestCache._internal();

  final Map<String, _CachedResponse> _cache = {};

  // 最大缓存条目数
  int _maxSize = 100;

  // 默认过期时间
  Duration _defaultExpiration = const Duration(minutes: 5);

  /// 获取缓存
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
    // 清理过期缓存
    _cleanupExpired();

    // 如果超过最大大小，清理最旧的
    if (_cache.length >= _maxSize) {
      _evictLRU();
    }

    _cache[key] = _CachedResponse(
      data: data,
      expiration: expiration ?? _defaultExpiration,
    );
  }

  /// 清除过期缓存
  void _cleanupExpired() {
    _cache.removeWhere((key, value) => value.isExpired);
  }

  /// 清理最久未使用的
  void _evictLRU() {
    if (_cache.isEmpty) return;

    String? oldestKey;
    DateTime? oldestTime;

    _cache.forEach((key, value) {
      if (oldestTime == null || value.lastAccessed.isBefore(oldestTime!)) {
        oldestKey = key;
        oldestTime = value.lastAccessed;
      }
    });

    if (oldestKey != null) {
      _cache.remove(oldestKey);
    }
  }

  /// 清除所有缓存
  void clear() => _cache.clear();

  /// 设置配置
  void configure({
    int? maxSize,
    Duration? defaultExpiration,
  }) {
    if (maxSize != null) _maxSize = maxSize;
    if (defaultExpiration != null) _defaultExpiration = defaultExpiration;
  }

  /// 获取缓存统计
  Map<String, dynamic> getStats() {
    return {
      'size': _cache.length,
      'maxSize': _maxSize,
      'hitCount': _cache.values.fold(0, (sum, v) => sum + v.accessCount),
    };
  }
}

class _CachedResponse {
  final dynamic data;
  final Duration expiration;
  DateTime lastAccessed;
  int accessCount = 0;

  _CachedResponse({
    required this.data,
    required this.expiration,
  }) : lastAccessed = DateTime.now();

  bool get isExpired => DateTime.now().difference(lastAccessed) > expiration;

  void touch() {
    lastAccessed = DateTime.now();
    accessCount++;
  }
}

/// 批量请求管理器
class BatchRequestManager {
  static final BatchRequestManager _instance = BatchRequestManager._internal();
  static BatchRequestManager get instance => _instance;
  BatchRequestManager._internal();

  final Map<String, List<Completer<dynamic>>> _batchGroups = {};
  Timer? _batchTimer;
  Duration _batchWindow = const Duration(milliseconds: 50);

  /// 添加批量请求
  Future<T> add<T>(
    String groupKey,
    String itemKey,
    Future<Map<String, T>> Function(List<String>) batchRequest,
  ) {
    final completer = Completer<T>();

    if (!_batchGroups.containsKey(groupKey)) {
      _batchGroups[groupKey] = [];

      // 延迟执行批量请求
      _batchTimer?.cancel();
      _batchTimer = Timer(_batchWindow, () {
        _executeBatch(groupKey, batchRequest);
      });
    }

    _batchGroups[groupKey]!.add(completer);

    return completer.future;
  }

  /// 执行批量请求
  void _executeBatch<T>(
    String groupKey,
    Future<Map<String, T>> Function(List<String>) batchRequest,
  ) async {
    final completers = _batchGroups.remove(groupKey);
    if (completers == null || completers.isEmpty) return;

    try {
      // 这里简化处理，实际应该根据 itemKey 分组
      // ignore: unused_local_variable
      final results = await batchRequest([]);

      for (final completer in completers) {
        if (!completer.isCompleted) {
          completer.completeError(Exception('Batch request not implemented'));
        }
      }
    } catch (e) {
      for (final completer in completers) {
        if (!completer.isCompleted) {
          completer.completeError(e);
        }
      }
    }
  }

  /// 设置批量窗口时间
  void setBatchWindow(Duration window) {
    _batchWindow = window;
  }
}

/// 请求重试包装器
Future<T> withRetry<T>(
  Future<T> Function() request, {
  int maxRetries = 3,
  Duration delay = const Duration(seconds: 1),
  bool Function(Exception)? shouldRetry,
}) async {
  int attempts = 0;

  while (true) {
    try {
      return await request();
    } on Exception catch (e) {
      attempts++;

      if (attempts >= maxRetries) {
        rethrow;
      }

      if (shouldRetry != null && !shouldRetry(e)) {
        rethrow;
      }

      await Future<void>.delayed(delay * attempts);
    }
  }
}
