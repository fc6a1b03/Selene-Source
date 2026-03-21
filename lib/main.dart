import 'dart:io' show HttpOverrides, Platform;

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:macos_window_utils/macos_window_utils.dart';
import 'package:media_kit/media_kit.dart';
import 'package:provider/provider.dart';
import 'package:selene/components/animations/modern_loading_animation.dart';
import 'package:selene/design/colors.dart';
import 'package:selene/screens/home_screen.dart';
import 'package:selene/screens/login_screen.dart';
import 'package:selene/services/api_service.dart';
import 'package:selene/services/douban_cache_service.dart';
import 'package:selene/services/local_mode_storage_service.dart';
import 'package:selene/services/speed_test_cache_service.dart';
import 'package:selene/services/subscription_service.dart';
import 'package:selene/services/theme_service.dart';
import 'package:selene/services/usb_capture_service.dart';
import 'package:selene/services/user_data_service.dart';
import 'package:selene/utils/hive_initializer.dart';
import 'package:selene/utils/http_overrides.dart';
import 'package:selene/utils/keyboard_error_handler.dart';

// 应用程序入口点
void main() async {
  // 初始化键盘错误处理器
  KeyboardErrorHandler.initialize();
  // 全局禁用证书校验
  HttpOverrides.global = CustomizeHttpOverrides();
  // 初始化 Flutter
  WidgetsFlutterBinding.ensureInitialized();
  // 初始化 Hive - 必须在 runApp 前完成
  await HiveInitializer.init();
  // 初始化 media_kit - 必须在 runApp 前完成
  MediaKit.ensureInitialized();
  // 初始化 macOS 窗口配置 - 必须在 runApp 前完成
  if (Platform.isMacOS) {
    await WindowManipulator.initialize(enableWindowDelegate: true);
    await WindowManipulator.makeTitlebarTransparent();
    await WindowManipulator.enableFullSizeContentView();
    await WindowManipulator.hideTitle();
  }
  runApp(const SeleneApp());
  // Windows 窗口配置 - 可以在 runApp 后
  if (Platform.isWindows) {
    doWhenWindowReady(() {
      final win = appWindow;
      const size = Size(1200, 800);
      win.size = size;
      win.minSize = size;
      win.alignment = Alignment.center;
      win.title = 'Selene';
      win.show();
    });
  }
  // 延迟初始化非关键服务，避免阻塞启动
  await Future<void>.delayed(Duration.zero);
  _initializeDeferredServices();
  // 初始化 USB 采集卡服务（Android 平台）
  if (Platform.isAndroid) {
    await UsbCaptureService.instance.initialize();
  }
}

/// 延迟初始化非关键服务
void _initializeDeferredServices() async {
  // 初始化豆瓣缓存服务 - 延迟执行
  final cacheService = DoubanCacheService();
  await cacheService.init();
  cacheService.startPeriodicCleanup();
  // 初始化测速缓存服务 - 延迟执行
  await SpeedTestCacheService.init();
}

// 主应用程序组件
class SeleneApp extends StatelessWidget {
  const SeleneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ThemeService()),
        // USB 采集卡服务（Android 平台）
        if (Platform.isAndroid)
          ChangeNotifierProvider.value(value: UsbCaptureService.instance),
      ],
      // 使用 Selector 只监听 themeMode 变化
      child: Selector<ThemeService, ThemeMode>(
        selector: (_, themeService) => themeService.themeMode,
        builder: (context, themeMode, child) {
          // 通过 Provider.of 获取主题数据（不监听，避免主题数据变化时重建）
          final themeService =
              Provider.of<ThemeService>(context, listen: false);
          return MaterialApp(
            title: 'Selene',
            debugShowCheckedModeBanner: false,
            theme: themeService.lightTheme,
            darkTheme: themeService.darkTheme,
            themeMode: themeMode,
            home: const AppWrapper(),
            builder: (context, child) {
              // 为 Windows 平台改善字体渲染
              Widget app = child!;
              if (Platform.isWindows) {
                app = MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: const TextScaler.linear(1.0),
                  ),
                  child: app,
                );
              }
              // 添加键盘事件处理，抑制已知的 Flutter 键盘问题
              return Focus(
                onKeyEvent: (node, event) {
                  // 正常处理键盘事件，不拦截
                  return KeyEventResult.ignored;
                },
                child: app,
              );
            },
          );
        },
      ),
    );
  }
}

// 应用程序包装组件，负责检查登录状态并导航到相应页面
class AppWrapper extends StatefulWidget {
  const AppWrapper({super.key});

  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

// 应用程序包装组件状态类
class _AppWrapperState extends State<AppWrapper> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  void _checkLoginStatus() async {
    try {
      // 检查是否是本地模式
      final isLocalMode = await UserDataService.getIsLocalMode();
      if (isLocalMode) {
        // 本地模式：尝试刷新订阅内容
        try {
          final subscriptionUrl =
              await LocalModeStorageService.getSubscriptionUrl();
          if (subscriptionUrl != null && subscriptionUrl.isNotEmpty) {
            final response = await http.get(Uri.parse(subscriptionUrl));
            if (response.statusCode == 200) {
              final content =
                  await SubscriptionService.parseSubscriptionContent(
                      response.body);
              if (content != null) {
                if (content.searchResources != null &&
                    content.searchResources!.isNotEmpty) {
                  await LocalModeStorageService.saveSearchSources(
                      content.searchResources!);
                }
                if (content.liveSources != null &&
                    content.liveSources!.isNotEmpty) {
                  await LocalModeStorageService.saveLiveSources(
                      content.liveSources!);
                }
              }
            }
          }
        } catch (e) {
          // 刷新失败也继续进入首页
        }
        // 无论刷新成功与否，都进入首页
        if (mounted) {
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (context) => const HomeScreen()),
          );
        }
      }
      // 检查是否有自动登录所需的数据
      final hasAutoLoginData = await UserDataService.hasAutoLoginData();
      if (!hasAutoLoginData) {
        // 如果没有自动登录数据，直接进入登录页
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }
      // 服务器模式：尝试自动登录
      final loginResult = await ApiService.autoLogin();
      if (mounted) {
        if (loginResult.success) {
          // 自动登录成功，进入首页
          await Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(builder: (context) => const HomeScreen()),
          );
        } else {
          // 自动登录失败，进入登录页
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      // 发生异常，进入登录页
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      // 使用 Selector 只监听 isDarkMode 变化
      return Selector<ThemeService, bool>(
        selector: (_, themeService) => themeService.isDarkMode,
        builder: (context, isDarkMode, child) {
          return Scaffold(
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: isDarkMode
                    ? AppColors.darkBackgroundGradient
                    : AppColors.lightBackgroundGradient,
              ),
              child: Center(
                child: ModernLoadingAnimation(
                  message: '正在检查登录状态',
                  subMessage: '请稍候',
                  isDarkMode: isDarkMode,
                  size: 160,
                ),
              ),
            ),
          );
        },
      );
    }
    return const LoginScreen();
  }
}
