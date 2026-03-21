# Selene - AI Agent Development Guide

> **Language**: 本项目使用 **中文** 作为所有文档和注释的主要语言。修改代码时请保持此约定。

## Project Overview

**Selene** 是一个基于 Flutter 开发的跨平台视频播放器应用（基于 MoonTV 的视频播放器），支持视频点播、直播电视、内容搜索和用户数据管理等功能。

- **Name**: selene
- **Version**: 1.6.6+2156
- **Flutter SDK**: >=3.4.3 <4.0.0
- **Dart SDK**: >=3.4.3
- **Package Manager**: pub (pubspec.yaml)

### Core Features

- 跨平台视频播放（基于 media_kit）
- 直播电视流播放与 EPG（电子节目指南）
- 多源聚合内容搜索
- 用户收藏与播放历史
- 深色/浅色主题切换（默认跟随系统）
- 多平台支持：Android、iOS、macOS、Windows、Linux、Web
- DLNA 投屏支持
- 画中画模式（PiP）
- 本地模式（基于订阅源，无需服务器）

## Technology Stack

### Core Dependencies

| Category          | Package                                 | Purpose      |
|-------------------|-----------------------------------------|--------------|
| State Management  | `provider`                              | 响应式状态管理      |
| Video Player      | `media_kit`                             | 跨平台视频播放      |
| Local Storage     | `hive`                                  | NoSQL 本地数据库  |
| HTTP Client       | `dio`, `http`                           | API 通信       |
| UI Icons          | `lucide_icons_flutter`                  | 图标库          |
| Window Management | `bitsdojo_window`, `macos_window_utils` | 桌面窗口控制       |
| Downloads         | `gal`                                   | 媒体保存到相册      |
| Casting           | `dlna_dart`                             | DLNA 设备发现与投屏 |
| Brightness        | `screen_brightness`                     | 屏幕亮度控制       |
| Volume            | `volume_controller`                     | 系统音量控制       |

### Platform Support

| Platform    | Requirements                                 |
|-------------|----------------------------------------------|
| **Android** | minSdk 21, targetSdk 36, Kotlin DSL, Java 17 |
| **iOS**     | Xcode 15+, CocoaPods                         |
| **macOS**   | Xcode 15+, 支持 ARM64 和 x86_64 双架构             |
| **Windows** | Visual Studio 2022 (C++ 桌面开发)                |
| **Linux**   | clang, cmake, ninja-build, GTK 开发库           |
| **Web**     | CanvasKit 渲染器                                |

## Project Structure

```
lib/
├── main.dart                    # 应用入口点
├── components/
│   └── animations/              # 自定义动画组件
│       ├── glass_card.dart
│       ├── modern_loading_animation.dart
│       ├── neon_button.dart
│       └── video_loading_animation.dart
├── design/                      # Design System 2026
│   ├── animations.dart          # 共享动画
│   ├── colors.dart              # 颜色系统（青绿-蓝色系）
│   ├── design_system.dart       # 设计系统导出
│   ├── shadows.dart             # 阴影定义
│   └── typography.dart          # 文本样式
├── mixins/
│   └── player_control_mixin.dart # 播放器控制混入
├── models/                      # 数据模型
│   ├── video_info.dart          # 视频元数据
│   ├── play_record.dart         # 播放历史
│   ├── favorite_item.dart       # 用户收藏
│   ├── search_result.dart       # 搜索结果
│   ├── live_channel.dart        # 直播频道
│   ├── live_source.dart         # 直播源
│   ├── aggregated_search_result.dart  # 聚合搜索结果
│   ├── bangumi.dart             # Bangumi 数据
│   ├── douban_movie.dart        # 豆瓣电影数据
│   └── speed_test_cache.dart    # 测速缓存
├── screens/                     # 全屏页面
│   ├── home_screen.dart         # 主屏幕（带标签页）
│   ├── player_screen.dart       # 视频播放器
│   ├── search_screen.dart       # 搜索界面
│   ├── live_screen.dart         # 直播电视浏览
│   ├── live_player_screen.dart  # 直播播放器
│   ├── login_screen.dart        # 登录/本地模式
│   ├── movie_screen.dart        # 电影分类
│   ├── tv_screen.dart           # 电视剧分类
│   ├── anime_screen.dart        # 动漫分类
│   ├── show_screen.dart         # 综艺分类
│   └── admin_screen.dart        # 管理后台
├── services/                    # 业务逻辑服务
│   ├── api_service.dart         # HTTP API 客户端
│   ├── theme_service.dart       # 主题管理
│   ├── user_data_service.dart   # 本地用户数据
│   ├── page_cache_service.dart  # 页面数据缓存
│   ├── douban_service.dart      # 豆瓣集成
│   ├── douban_cache_service.dart # 豆瓣缓存
│   ├── bangumi_service.dart     # Bangumi 集成
│   ├── search_service.dart      # 搜索功能
│   ├── live_service.dart        # 直播电视服务
│   ├── version_service.dart     # 更新检查
│   ├── subscription_service.dart # 订阅源解析
│   ├── local_mode_storage_service.dart # 本地模式存储
│   ├── speed_test_cache_service.dart # 测速缓存
│   ├── download_service.dart    # 下载服务
│   ├── dlna_service.dart        # DLNA 投屏（通过 dlna_dart）
│   └── ...
├── utils/                       # 工具类
│   ├── font_utils.dart          # 字体辅助（Poppins/微软雅黑）
│   ├── hive_adapters.dart       # Hive 类型适配器
│   ├── hive_initializer.dart    # 数据库初始化
│   ├── http_overrides.dart      # SSL 证书处理
│   ├── route_animations.dart    # 页面切换动画
│   ├── performance_monitor.dart # 性能监控
│   ├── memory_leak_detector.dart # 内存泄漏检测
│   └── ...
└── widgets/                     # 可复用 UI 组件
    ├── video_card.dart          # 视频卡片
    ├── main_layout.dart         # 应用外壳布局
    ├── mobile_player_controls.dart  # 移动端播放器控制
    ├── pc_player_controls.dart      # PC 端播放器控制
    ├── bangumi_grid.dart        # Bangumi 网格
    ├── douban_movies_grid.dart  # 豆瓣电影网格
    ├── favorites_grid.dart      # 收藏网格
    ├── history_grid.dart        # 历史记录网格
    ├── hot_*_section.dart       # 各类热门内容区块
    └── ...
```

## Build Commands

### 编码前环境检查

**在开始编码之前，必须先运行以下命令检查 Flutter 环境版本：**

```bash
flutter doctor --verbose
```

**检查要点：**

- ✅ 确认 Flutter SDK 版本与项目要求匹配 (`>=3.4.3 <4.0.0`)
- ✅ 确认 Dart SDK 版本兼容
- ✅ 检查所有平台工具链是否正常（Android SDK、Xcode、Visual Studio 等）
- ✅ 确认 `flutter` 和 `dart` 命令可用

**版本兼容性说明：**

| 环境          | 项目要求             | 说明          |
|-------------|------------------|-------------|
| Flutter SDK | `>=3.4.3 <4.0.0` | 当前使用 3.38.9 |
| Dart SDK    | `>=3.4.3`        | 当前使用 3.11.0 |

> ⚠️ **重要**: 编码时必须确保语法与当前 Flutter/Dart 版本匹配，避免使用过时的 API 或语法。如遇到不兼容的语法错误，请先检查
`flutter doctor` 输出确认版本。

### Development

```bash
# 安装依赖
flutter pub get

# 运行到已连接设备
flutter run

# 运行到指定设备
flutter run -d <device-id>

# 代码分析
flutter analyze

# 格式化代码
dart format lib/
```

### Production Builds

项目提供完整的构建脚本 (`build.sh`)：

```bash
# 构建所有平台（并行）
./build.sh

# 平台特定构建
./build.sh --android-only       # Android APK (arm64, armv7) + AAB
./build.sh --ios-only           # iOS 无签名 IPA
./build.sh --macos-only         # macOS 双架构
./build.sh --macos-arm64-only   # Apple Silicon
./build.sh --macos-x86_64-only  # Intel Mac
./build.sh --apple-only         # iOS + macOS
./build.sh --windows-only       # Windows
./build.sh --linux-only         # Linux
./build.sh --web-only           # Web
./build.sh --sequential         # 顺序构建（非并行）
./build.sh --no-clean           # 跳过清理（快速构建）
```

### Manual Flutter Builds

```bash
# Android
flutter build apk --release --target-platform android-arm64,android-arm --split-per-abi --no-tree-shake-icons
flutter build appbundle --release --no-tree-shake-icons

# iOS（仅 macOS）
flutter build ios --release --no-codesign

# macOS（仅 macOS）
flutter build macos --release

# Windows（仅 Windows）
flutter build windows --release --no-tree-shake-icons

# Linux（仅 Linux）
flutter build linux --release

# Web
flutter build web --release --web-renderer canvaskit
```

**注意**: 使用 `media_kit` 构建时必须加上 `--no-tree-shake-icons` 参数，否则图标资源会被误删。

## Code Style Guidelines

### Language Conventions

- **注释**: 使用中文编写所有内联注释和文档
- **用户界面字符串**: 使用中文
- **变量名**: 使用驼峰命名法 (camelCase)，描述性英文名称
- **文件名**: 所有 Dart 文件使用蛇形命名法 (snake_case)

### Analysis Configuration

项目使用严格的分析规则 (`analysis_options.yaml`)：

```yaml
# 关键强制规则
- always_declare_return_types: true      # 必须声明返回类型
- always_use_package_imports: true       # 禁止使用相对导入
- avoid_relative_lib_imports: true       # 仅使用 package 导入
- prefer_final_fields: true              # 尽可能使用不可变字段
- prefer_final_locals: true              # 局部变量使用 final
- prefer_single_quotes: true             # 字符串使用单引号
- use_key_in_widget_constructors: true   # Widget 必须提供 Key 参数
- use_build_context_synchronously: true  # 正确处理异步 context
```

### Design System Usage

导入设计系统以保持 UI 一致性：

```
import 'package:selene/design/design_system.dart';

// 颜色
Container(
  color: AppColors.primary,
  decoration: BoxDecoration(
    gradient: AppColors.primaryGradient,
  ),
)

// 字体
Text('标题', style: AppTypography.headlineMediumStyle(isDark: true))

// 阴影
Container(
  decoration: BoxDecoration(
    boxShadow: AppShadows.medium,
  ),
)
```

### Font Guidelines

使用 FontUtils 保持字体一致性：

```
import 'package:selene/utils/font_utils.dart';

// 主要字体（Windows 使用微软雅黑，其他使用 Poppins）
Text('Hello', style: FontUtils.poppins(fontSize: 16))

// 等宽字体
Text('Code', style: FontUtils.sourceCodePro(fontSize: 14))
```

## Performance Standards

**新特性开发必须遵循高性能、低损耗原则：**

### Widget 构建优化

- 使用 `const` 构造函数减少重建
- 长列表使用 `ListView.builder` 替代 `Column`
- 避免在 `build` 方法中执行复杂计算
- 使用 `RepaintBoundary` 隔离频繁重绘区域
- 使用 `Selector` 替代 `Consumer` 监听特定字段

### 状态管理优化

- 精确控制 `notifyListeners()` 调用时机
- 避免在 `didUpdateWidget` 中触发状态更新

### 资源管理

- 及时释放控制器（`VideoPlayerController`、`ScrollController` 等）
- 使用 `CachedNetworkImage` 替代原生长图片加载
- 图片使用适当分辨率，避免内存溢出

### 异步操作

- 使用 `FutureBuilder`/`StreamBuilder` 管理异步状态
- 取消未完成的异步请求避免内存泄漏
- 耗时操作移至 Isolate（如 JSON 解析、图片处理）

## Code Quality Gates

**每个开发阶段必须通过 `flutter analyze` 检查：**

```bash
# 阶段 1: 编码完成后立即检查
flutter analyze

# 阶段 2: 提交前最终检查
flutter analyze --fatal-infos --fatal-warnings
```

**检查规则：**

- ❌ 禁止提交包含 `error` 的代码
- ❌ 禁止提交包含 `warning` 的代码（特殊情况需注释说明）
- ⚠️ `info` 级别建议修复，可酌情处理

**自动修复命令：**

```bash
# 自动修复格式问题
dart fix --apply

# 格式化代码
dart format lib/
```

## Testing Instructions

### Current State

- **Unit Tests**: 尚未实现
- **Widget Tests**: 尚未实现
- **Integration Tests**: 尚未实现

CI/CD 中测试步骤使用 `|| true` 确保不会因测试缺失而失败。

### Running Tests

```bash
# 运行所有测试
flutter test

# 运行带覆盖率报告
flutter test --coverage

# 生成覆盖率 HTML 报告（需要 lcov）
genhtml coverage/lcov.info -o coverage/html
```

## Security Considerations

### SSL/TLS Handling

应用全局禁用证书验证（开发便利）：

```
// lib/main.dart
HttpOverrides.global = CustomizeHttpOverrides(); // 禁用证书检查
```

**警告**: 此配置仅用于开发便利。生产部署应实现适当的证书固定。

### Code Obfuscation

发布构建启用代码混淆：

```bash
flutter build apk --obfuscate --split-debug-info=build/app/outputs/symbols
```

调试符号作为 CI 产物上传，用于崩溃分析。

### Data Storage

- 用户凭证存储在 Hive（本地加密存储）
- Cookie 由 UserDataService 管理
- 发布版本不记录敏感数据日志

### Dependencies

CI 包含安全审计步骤：

```bash
flutter pub audit  # 检查已知漏洞
```

## Key Services Reference

### ApiService

通用 HTTP 客户端，自动处理认证：

```
// GET 请求
final response = await ApiService.get<List<SearchResult>>(
  '/api/search',
  fromJson: (data) => /* 解析逻辑 */,
);

// POST 请求
final response = await ApiService.post<void>(
  '/api/favorites',
  body: {'key': key, 'favorite': favoriteData},
);
```

### PageCacheService

管理收藏、历史和搜索的本地缓存：

```
final cacheService = PageCacheService();
await cacheService.refreshFavorites(context);
await cacheService.refreshPlayRecords(context);
```

### ThemeService

通过 Provider 管理主题：

```
// 切换主题
context.read<ThemeService>().toggleTheme(context);

// 检查当前模式
final isDark = context.read<ThemeService>().isDarkMode;
```

## Local Development Mode

应用支持"本地模式"，无需后端服务器即可工作：

1. 用户提供订阅源 URL
2. 应用从订阅源解析 M3U/搜索源
3. 内容直接从源 URL 获取

在登录屏幕通过"本地模式"选项启用。

## CI/CD Pipeline

GitHub Actions 工作流：

- **ci-cd.yml**: 完整流水线（push 到 main/develop/release 分支）
    - 代码分析和测试
    - 安全审计
    - 6 个平台并行构建
    - 标签推送时自动创建 Release

- **pr-check.yml**: PR 轻量验证
    - 分析和格式检查
    - 冒烟构建测试

构建矩阵：Android (APK + AAB)、iOS (IPA)、macOS (ARM64 + x86_64 DMG)、Windows (ZIP)、Linux (tar.gz)、Web (tar.gz)

## Common Tasks

### Adding a New Screen

1. 在 `lib/screens/` 创建文件
2. 在相关页面添加路由导航
3. 使用 package 导入：`import 'package:selene/screens/new_screen.dart';`

### Adding a Model

1. 在 `lib/models/` 创建模型类
2. 添加 `fromJson`/`toJson` 方法
3. 如需持久化，在 `lib/utils/hive_adapters.dart` 创建 Hive 适配器
4. 在 `lib/utils/hive_initializer.dart` 注册适配器

### Adding an API Endpoint

1. 在 `ApiService` 添加方法，使用适当的泛型类型
2. 返回 `ApiResponse<T>` 并指定类型
3. 在 `_handleResponse` 中处理 401 未授权

## Troubleshooting

### Build Issues

```bash
# 清理构建产物
flutter clean
rm -rf build/ ios-build/ build-arm64/ build-x86_64/

# 重新生成平台文件
flutter pub get
```

### Dependency Issues

```bash
# 更新依赖
flutter pub upgrade

# 检查过时包
flutter pub outdated
```

### Platform-Specific

**Android**: 确保安装 Java 17 并设置 `JAVA_HOME`
**iOS/macOS**: 需要 Xcode，在 ios/ 目录运行 `pod install`
**Windows**: 需要 Visual Studio 并安装 C++ 桌面开发工作负载
**Linux**: 需要 clang、cmake、ninja-build、GTK 开发头文件

## Dependencies Overview

### SDK & Framework

| Package     | Version | Description |
|-------------|---------|-------------|
| Flutter SDK | 3.38.9  | UI 框架       |
| Dart SDK    | 3.11.0  | 编程语言        |

### Core Dependencies Summary

```
selene
├── Core: provider, media_kit*, hive*, dio, http
├── UI: flutter_svg, lucide_icons_flutter, google_fonts, cached_network_image
├── Platform: bitsdojo_window, macos_window_utils, screen_brightness, volume_controller
├── Network: web_socket_channel, xml, dlna_dart
├── Crypto: encrypt, crypto, bs58check
└── Utils: intl, uuid, path_provider, package_info_plus, url_launcher
```

完整依赖列表见 `pubspec.yaml`。
