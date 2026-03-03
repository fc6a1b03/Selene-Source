// 通用图片地址处理工具
import 'package:selene/services/user_data_service.dart';

/// 图片 URL 缓存
final Map<String, String> _imageUrlCache = {};

/// 根据来源处理图片 URL（例如豆瓣域名替换）。
/// - [originalUrl]: 原始图片地址
/// - [source]: 数据来源（如 'douban'、'bangumi' 等）
/// 返回可直接用于加载的图片地址。
///
/// 优化：使用缓存避免重复计算
Future<String> getImageUrl(String originalUrl, String? source) async {
  // 空 URL 直接返回
  if (originalUrl.isEmpty) return originalUrl;

  // 非豆瓣来源直接返回
  if (source != 'douban') return originalUrl;

  // 检查缓存
  final cacheKey = '${source}_$originalUrl';
  if (_imageUrlCache.containsKey(cacheKey)) {
    return _imageUrlCache[cacheKey]!;
  }

  // 处理 URL
  final imageSourceKey = await UserDataService.getDoubanImageSourceKey();
  String result;

  switch (imageSourceKey) {
    case 'official_cdn':
      result = originalUrl.replaceAll(
        RegExp(r'img\d+\.doubanio\.com'),
        'img3.doubanio.com',
      );
    case 'cdn_tencent':
      result = originalUrl.replaceAll(
        RegExp(r'img\d+\.doubanio\.com'),
        'img.doubanio.cmliussss.net',
      );
    case 'cdn_aliyun':
      result = originalUrl.replaceAll(
        RegExp(r'img\d+\.doubanio\.com'),
        'img.doubanio.cmliussss.com',
      );
    case 'direct':
    default:
      result = originalUrl;
  }

  // 保存到缓存（限制缓存大小）
  if (_imageUrlCache.length > 1000) {
    _imageUrlCache.clear();
  }
  _imageUrlCache[cacheKey] = result;

  return result;
}

/// 返回加载网络图片所需的 HTTP 头（主要用于绕过特定站点的反盗链）。
/// 注意：只有当 [source] 为 'douban' 或 URL 指向 douban 域名时才添加 Referer/UA。其他来源返回空头。
Map<String, String>? getImageRequestHeaders(String imageUrl, String? source) {
  final bool isDoubanSource = (source == 'douban') ||
      RegExp(r'https?://([^/]+\.)?douban(io|)\.com', caseSensitive: false)
          .hasMatch(imageUrl);
  if (isDoubanSource) {
    // 常见可用的 Referer 和 UA，避免 403 或 Android 解码失败
    return <String, String>{
      'Referer': 'https://movie.douban.com/',
      'User-Agent':
          'Mozilla/5.0 (Linux; Android 13; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    };
  }
  return null;
}
