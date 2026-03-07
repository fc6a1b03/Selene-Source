import 'package:hive_flutter/hive_flutter.dart';
import 'package:selene/models/speed_test_cache.dart';
import 'package:selene/utils/hive_adapters.dart';

/// Hive 初始化器
/// 用于初始化 Hive 数据库和注册适配器
class HiveInitializer {
  /// 初始化 Hive
  static Future<void> init() async {
    // 初始化 Hive
    await Hive.initFlutter();
    // 注册适配器
    Hive.registerAdapter(LiveSourceAdapter());
    Hive.registerAdapter(PlayRecordAdapter());
    Hive.registerAdapter(FavoriteItemAdapter());
    Hive.registerAdapter(SearchResourceAdapter());
    Hive.registerAdapter(SpeedTestCacheGroupAdapter());
    // 打开本地模式数据盒子
    await Hive.openBox<dynamic>('user_data');
    await Hive.openBox<String>('version_data');
    await Hive.openBox<String>('local_mode_data');
    // 打开测速缓存盒子
    await Hive.openBox<SpeedTestCacheGroup>('speed_test_cache');
  }
}
