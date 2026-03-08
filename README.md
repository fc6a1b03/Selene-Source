# Selene

基于 MoonTV 的视频播放器

## 特性

- 基于 Flutter 的跨平台架构
- 常用插件与平台适配（见 `pubspec.yaml`）
- 预置平台目录与构建脚本

## 快速开始

1. 安装 Flutter（见 https://flutter.dev ）并配置平台工具链（Android SDK、Xcode、Visual Studio 等）。
2. 在仓库根目录运行：

   flutter pub get

3. 运行应用（选择设备或模拟器）：

   flutter run -d <device-id>

4. 打包构建示例：

   flutter build apk
   flutter build ios
   flutter build web
   flutter build windows

（根据目标平台选择对应命令）

## 项目结构（概要）

- lib/: 应用源码（`main.dart`、screens、widgets、services 等）
- android/、ios/、web/、windows/、macos/、linux/: 平台工程
- build/: 构建产物与中间文件
- pubspec.yaml: 依赖与资源声明
