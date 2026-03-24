---
name: flutter-performance-2026
description: Selene 项目 Flutter 性能优化技能文档（2026）
---

# Flutter 高性能开发规范 (2026版)

> **适用范围**: Selene 视频播放器项目  
> **核心原则**: 高性能、低损耗、极致用户体验  
> **Flutter版本**: >=3.29 (Impeller默认启用)  
> **更新日期**: 2026-03

---

## 目录

1. [核心渲染优化 (Impeller时代)](#核心渲染优化-impeller时代)
2. [Widget构建规范](#widget构建规范)
3. [状态管理最佳实践](#状态管理最佳实践)
4. [内存管理 checklist](#内存管理-checklist)
5. [视频播放器专项优化](#视频播放器专项优化)
6. [代码审查清单](#代码审查清单)

---

## 核心渲染优化 (Impeller时代)

### 🔴 Impeller 渲染引擎适配

Flutter 3.29+ 已默认启用 **Impeller** 渲染引擎，带来显著性能提升：

| 优化项    | 性能提升         | 说明                   |
|--------|--------------|----------------------|
| 帧栅格化时间 | **减少50%**    | 复杂场景下从 12% 掉帧降至 1.5% |
| 文本渲染   | **提升20-40%** | 高分辨率字形缓存，消除文本动画卡顿    |
| 启动时间   | **< 0.8秒**   | 预编译着色器，消除运行时编译卡顿     |
| 电池效率   | **提升17%**    | 减少CPU-GPU同步开销        |

**关键适配点：**

```
// ✅ 利用 Impeller 的 tile-based 渲染
// 仅重绘变化区域 (约 256x256 像素块)
RepaintBoundary (
child: ComplexVideoThumbnail(), // 隔离复杂子树
)

// ✅ 减少半透明层叠 (Overdraw)
// Impeller 会自动处理，但仍需避免无意义的多层叠加
Container(
decoration: BoxDecoration(
color: Colors.black.withOpacity(0.5), // 单层透明度
),
child: child,
)
```

### 🔴 渲染线程变更适配 (Flutter 3.29+)

> ⚠️ **重要变更**: Dart 代码现在运行在主线程，支持更高效的同步平台调用

```
// ✅ 现在可以安全使用同步平台通道 (需评估必要性)
// 之前需要异步的某些调用现在可以同步执行
// 但仍建议保持异步风格以避免阻塞

// 保持异步最佳实践
Future<void> fetchVideoData() async {
  final data = await platform.invokeMethod('getVideoInfo');
  // ...
}
```

---

## Widget构建规范

### 🔴 强制使用 `const` 构造函数

```
// ❌ 错误: 每次 build 都创建新实例
Widget build(BuildContext context) {
  return Container(
    child: Text('Selene Player'), // 重建
  );
}

// ✅ 正确: const 构造函数复用 Element
Widget build(BuildContext context) {
  return const Container(
    child: Text('Selene Player'), // 编译时实例化
  );
}
```

**lint 规则** (已配置在 `analysis_options.yaml`):

```yaml
linter:
  rules:
    prefer_const_constructors: true
    prefer_const_literals_to_create_immutables: true
```

### 🔴 长列表懒加载 (视频列表场景)

```
// ❌ 错误: 一次性构建所有子项
Column
(
children: videos.map((v) => VideoCard(video: v)).toList(),
)

// ✅ 正确: 按需构建
ListView.builder(
itemCount: videos.length,
itemBuilder: (context, index) => VideoCard(video: videos[index]),
)

// ✅ 进一步优化: 固定高度跳过计算
ListView.builder(
itemExtent: 120, // 视频卡片固定高度
itemBuilder: (context, index) => VideoCard(video:
videos
[
index
]
)
,
)
```

### 🔴 避免复杂 Clip (影响 GPU)

```
// ❌ 错误: 昂贵的裁剪操作
ClipPath
(
clipper: ComplexClipper(),
child: VideoThumbnail(),
)

// ✅ 正确: 使用 BoxDecoration 圆角
Container(
decoration: BoxDecoration(
borderRadius: BorderRadius.circular(8),
),
child:
VideoThumbnail
(
)
,
)
```

### 🔴 动画优化 (Impeller 下更显著)

```
// ❌ 错误: Opacity 导致子树重绘
AnimatedBuilder
(
animation: animation,
builder: (context, child) => Opacity(
opacity: animation.value,
child: VideoOverlay(),
),
)

// ✅ 正确: 使用 FadeTransition
FadeTransition(
opacity: animation,
child: VideoOverlay(),
)

// ✅ 或使用 AnimatedOpacity
AnimatedOpacity(
opacity: showOverlay ? 1.0 : 0.0,
duration: const Duration(milliseconds: 200),
child
:
VideoOverlay
(
)
,
)
```

### 🔴 局部刷新策略

```
// ❌ 错误: 顶层 setState 导致整页重建
class _VideoPageState extends State<VideoPage> {
  int _currentTime = 0;

  void _updateTime() {
    setState(() => _currentTime++); // 重建整个页面！
  }
}

// ✅ 正确: ValueListenableBuilder 局部刷新
class _VideoPageState extends State<VideoPage> {
  final ValueNotifier<int> _currentTime = ValueNotifier(0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const VideoPlayer(), // 不重建
          const VideoControls(), // 不重建
          ValueListenableBuilder<int>(
            valueListenable: _currentTime,
            builder: (context, value, child) {
              return Text('${value}s'); // 仅刷新时间文本
            },
          ),
        ],
      ),
    );
  }
}
```

### 🔴 Selector 细粒度监听 (Provider)

```
// ❌ 错误: 监听整个 model
Consumer<VideoModel>
(
builder: (context, model, child) {
return Text(model.title); // model 任何变化都重建
},
)

// ✅ 正确: 只监听特定字段
Selector<VideoModel, String>(
selector: (context, model) => model.title,
builder: (context, title, child) {
return Text(title); // 只有 title 变化时重建
},
)
```

---

## 状态管理最佳实践

### 🔴 build() 方法严格瘦身

```
// ❌ 错误: build 中排序
Widget build(BuildContext context) {
  final sortedVideos = [...videos]..sort((a, b) => b.rating.compareTo(a.rating));
  return ListView.builder(...);
}

// ✅ 正确: 初始化时排序
class VideoList extends StatelessWidget {
  final List<Video> sortedVideos;

  VideoList(List<Video> videos)
      : sortedVideos = List.unmodifiable([...videos]..sort());

  @override
  Widget build(BuildContext context) {
    return ListView.builder(...); // 直接使用已排序数据
  }
}
```

### 🔴 禁止 build 中创建非 UI 对象

```
// ❌ 错误: build 中创建服务对象
Widget build(BuildContext context) {
  final client = HttpClient(); // 每次 build 都创建！
  return FutureBuilder(...);
}

// ✅ 正确: 在生命周期中创建
class _MyWidgetState extends State<MyWidget> {
  late final HttpClient _client;

  @override
  void initState() {
    super.initState();
    _client = HttpClient(); // 只创建一次
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
```

### 🔴 禁止 build 中发起网络请求

```
// ❌ 错误: 每次重建都重新请求
Widget build(BuildContext context) {
  return FutureBuilder(
    future: http.get(Uri.parse('...')), // 危险！
    builder: ...,
  );
}

// ✅ 正确: initState 中发起
class _MyWidgetState extends State<MyWidget> {
  late Future<Response> _future;

  @override
  void initState() {
    super.initState();
    _future = http.get(Uri.parse('...'));
  }
}
```

### 🔴 Isolate 处理耗时任务

```
import 'dart:convert';
import 'package:flutter/foundation.dart';

// ❌ 错误: 主线程解析大 JSON
void parseEpgs(String jsonString) {
  final data = jsonDecode(jsonString); // 阻塞 UI！
}

// ✅ 正确: 使用 compute 在 Isolate 中处理
Future<Map<String, dynamic>> parseEpgsAsync(String jsonString) async {
  return await compute(jsonDecode, jsonString);
}

// 图片处理示例
Future<Uint8List> processThumbnail(Uint8List bytes) async {
  return await compute(_processInIsolate, bytes);
}
```

### 🔴 并行处理独立请求

```
// ❌ 错误: 顺序 await 累加延迟
Future<void> loadVideoData() async {
  final info = await fetchVideoInfo(); // 300ms
  final related = await fetchRelated(); // 300ms
  final comments = await fetchComments(); // 300ms
  // 总计: 900ms
}

// ✅ 正确: Future.wait 并行
Future<void> loadVideoData() async {
  final results = await Future.wait([
    fetchVideoInfo(),
    fetchRelated(),
    fetchComments(),
  ]);
  // 总计: ~300ms
}
```

---

## 内存管理 Checklist

### 🔴 资源释放模板

```
class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  // 1. 播放器控制器 (最重要)
  VideoPlayerController? _controller;

  // 2. 文本编辑控制器
  final TextEditingController _searchController = TextEditingController();

  // 3. 动画控制器
  late AnimationController _animationController;

  // 4. 流订阅
  StreamSubscription? _playerSubscription;

  // 5. 定时器
  Timer? _hideControlsTimer;

  // 6. ScrollController
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    // 必须按顺序释放！
    _controller?.dispose(); // 1. 先释放播放器
    _searchController.dispose(); // 2
    _animationController.dispose(); // 3
    _playerSubscription?.cancel(); // 4
    _hideControlsTimer?.cancel(); // 5
    _scrollController.dispose(); // 6
    super.dispose();
  }
}
```

### 🔴 Context 安全使用

```
// ❌ 危险: 异步后直接使用 context
void onTap() async {
  await Future.delayed(Duration(seconds: 1));
  Navigator.of(context).pop(); // 可能已 dispose，导致崩溃
}

// ✅ 安全: 检查 mounted
void onTap() async {
  await Future.delayed(Duration(seconds: 1));
  if (mounted) { // 必须检查
    Navigator.of(context).pop();
  }
}

// ✅ 或使用扩展方法
extension BuildContextExtension on BuildContext {
  void safePop() {
    if (mounted) Navigator.of(this).pop();
  }
}
```

### 🔴 图片缓存管理 (视频缩略图场景)

```
// ✅ 按需解码 - 指定尺寸
Image.network
(
thumbnailUrl,
cacheWidth: 400, // 根据实际显示尺寸
cacheHeight: 225,
fit: BoxFit.cover,
)

// ✅ 预加载关键图片
didChangeDependencies() {
super.didChangeDependencies();
precacheImage(
NetworkImage(video.thumbnailUrl),
context,
);
}

// ✅ 内存紧张时清理
void onMemoryPressure() {
imageCache.clear();
imageCache.clearLiveImages();
}
```

---

## 视频播放器专项优化

### 🔴 media_kit 最佳实践

```
class _PlayerScreenState extends State<PlayerScreen> {
  late final Player _player;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _initPlayer();
  }

  void _initPlayer() async {
    // ✅ 设置缓冲区配置
    await _player.setBufferingConfiguration(
      BufferingConfiguration(
        minBufferMs: 15000, // 15秒最小缓冲
        maxBufferMs: 50000, // 50秒最大缓冲
        bufferForPlaybackMs: 2500,
        bufferForPlaybackAfterRebufferMs: 5000,
      ),
    );

    // ✅ 打开视频
    await _player.open(Media(widget.videoUrl));
  }

  @override
  void dispose() {
    // ✅ 必须释放播放器资源
    _player.dispose();
    super.dispose();
  }
}
```

### 🔴 播放器控制 UI 优化

```
// ✅ 使用 ValueListenableBuilder 隔离播放进度刷新
ValueListenableBuilder<Duration>
(
valueListenable: _player.position,
builder: (context, position, child) {
return Text(_formatDuration(position)); // 仅刷新进度文本
},
)

// ✅ 控制按钮使用 const
const PlayPauseButton(), // 状态变化时不重建整个按钮组
const ProgressBar()
,
const
VolumeControl
(
)
,
```

### 🔴 后台播放处理

```
// ✅ 进入后台时的处理
class PlayerService extends ChangeNotifier {
  bool _wasPlayingBeforePause = false;

  void onAppLifecycleStateChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        _wasPlayingBeforePause = _player.state.playing;
        if (!_enableBackgroundPlay) {
          _player.pause();
        }
        break;
      case AppLifecycleState.resumed:
        if (_wasPlayingBeforePause && _autoResume) {
          _player.play();
        }
        break;
      default:
        break;
    }
  }
}
```

---

## 代码审查清单

### 🔴 提交前必查项

- [ ] **所有静态 Widget 都有 `const`** (`prefer_const_constructors`)
- [ ] **长列表使用 `ListView.builder`** 而非 `Column`
- [ ] **没有 `build` 方法中的耗时计算**
- [ ] **没有 `build` 方法中的网络请求**
- [ ] **所有 Controller/Subscription/Timer 已 `dispose/cancel`**
- [ ] **异步操作后使用 `if (mounted)` 检查**
- [ ] **使用 `Future.wait` 替代顺序 `await`** (独立请求)
- [ ] **图片加载指定 `cacheWidth/cacheHeight`**
- [ ] **复杂逻辑已放入 `compute`** (JSON/图片处理)
- [ ] **移除了所有 `print` 语句** (使用 debugPrint 或 Logger)

### 🟡 性能优化建议

- [ ] 使用 `Selector` 替代完整 `Consumer`
- [ ] 使用 `RepaintBoundary` 隔离频繁重绘区域
- [ ] 使用 `BoxDecoration` 替代 `ClipRRect` (圆角)
- [ ] 使用 `FadeTransition` 替代 `Opacity` (动画)
- [ ] 频繁查找使用 `Set/Map` 替代 `List`
- [ ] 拆分大 `State` 类为独立 `StatelessWidget`
- [ ] 播放器控制器及时释放

### 🔴 Selene 项目特定规范

- [ ] **视频播放器页面必须释放 `_player`**
- [ ] **搜索历史使用 `Set` 存储去重**
- [ ] **EPG 数据解析使用 `compute`**
- [ ] **缩略图加载指定缓存尺寸** (不超过 400x225)
- [ ] **直播流使用 `ValueListenableBuilder` 刷新状态**
- [ ] **使用 `AppColors` 设计系统颜色**

---

## 常用反模式速查

| 反模式                    | 问题       | 解决方案                     |
|------------------------|----------|--------------------------|
| `setState` 在根 Widget   | 整页重建     | `ValueListenableBuilder` |
| `Opacity` 动画           | 子树重绘     | `FadeTransition`         |
| `ClipRRect` 大图         | 昂贵裁剪     | `BoxDecoration`          |
| `await` 循环             | 串行执行慢    | `Future.wait`            |
| `List.contains` 大数据    | O(n) 查找  | `Set.contains` O(1)      |
| `build` 中 `jsonDecode` | 阻塞 UI    | `compute` 隔离             |
| 未 dispose Controller   | 内存泄漏     | 统一在 dispose 释放           |
| 无 `mounted` 检查         | Crash 风险 | 异步后检查 mounted            |

---

## 参考链接

- [Flutter Performance Best Practices](https://docs.flutter.dev/perf/best-practices)
- [Impeller Rendering Engine](https://docs.flutter.dev/perf/impeller)
- [Flutter Performance Profiling](https://docs.flutter.dev/perf/ui-performance)
- [Dart DevTools](https://docs.flutter.dev/tools/devtools/overview)
