import 'dart:ui';

/// 键盘错误处理器
///
/// 处理 Flutter 框架的已知键盘事件问题：
/// - 当使用 Alt+Tab 切换窗口时，可能会触发 HardwareKeyboard 断言错误
/// - 当使用中文输入法时可能会触发键盘事件异常
/// - 这是一个 Flutter 框架的已知问题，不影响应用功能
///
/// 参考: https://github.com/flutter/flutter/issues/107972
class KeyboardErrorHandler {
  KeyboardErrorHandler._();

  /// 初始化键盘错误处理
  ///
  /// 在 main() 函数的最开始调用，用于捕获并抑制键盘事件相关的断言错误
  static void initialize() {
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      if (_isKeyboardRelatedError(error, stack)) {
        // 忽略键盘事件相关的断言错误
        print('[KeyboardErrorHandler] 抑制键盘错误: $error');
        return true;
      }
      return false;
    };
  }

  /// 判断是否为键盘事件相关的错误
  ///
  /// 检查错误消息和堆栈跟踪来识别各种键盘相关问题
  static bool _isKeyboardRelatedError(Object error, StackTrace stack) {
    final errorString = error.toString();
    final stackString = stack.toString();

    // 检查错误消息中的键盘相关关键字
    final keyboardKeywords = [
      'KeyDownEvent',
      'KeyUpEvent',
      '_pressedKeys',
      'HardwareKeyboard',
      'RawKeyDownEvent',
      'RawKeyUpEvent',
      'keysPressed',
      'raw_keyboard.dart',
      'hardware_keyboard.dart',
      'KeyEventManager',
      '_assertEventIsRegular',
      'PlatformDispatcher._dispatchPlatformMessage',
    ];

    for (final keyword in keyboardKeywords) {
      if (errorString.contains(keyword) || stackString.contains(keyword)) {
        return true;
      }
    }

    // 检查断言错误中的特定模式
    if (error is AssertionError) {
      // 常见的键盘断言错误模式
      if (errorString.contains('isRegularKey') ||
          errorString.contains('keyLabel') ||
          errorString.contains('physicalKey') ||
          errorString.contains('logicalKey')) {
        return true;
      }
    }

    return false;
  }
}
