# 优化 R8 编译速度：禁用部分优化，保留核心混淆
# 注意：这会轻微增加 APK 大小（约 5-10%），但大幅提升编译速度

# 禁用 R8 的激进优化（编译更快）
-dontoptimize
-dontpreverify

# === Play Core 动态交付（Flutter 需要）===
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# 保留行号信息方便调试
-keepattributes SourceFile,LineNumberTable

# === media_kit 相关规则 ===
-keep class com.alexmercerind.media_kit_video.** { *; }
-keep class com.alexmercerind.media_kit.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugin.** { *; }

# === DLNA 库 ===
-keep class com.dlna.** { *; }
-keep class org.fourthline.cling.** { *; }

# === 加密库 ===
-keep class org.bouncycastle.** { *; }
-keep class com.pointycastle.** { *; }

# === 其他 Flutter 插件 ===
-keep class com.builttoroam.devicecalendar.** { *; }
-keep class io.github.ponnamkarthik.** { *; }
-keep class com.ryanheise.** { *; }
-keep class me.schlaubi.** { *; }

# === flutter_uvc_camera / AndroidUSBCamera ===
-keep class com.jiangdg.uvc.UVCCamera {
    native <methods>;
    long mNativePtr;
}
-keep class com.jiangdg.uvc.IStatusCallback {
    *;
}
-keep interface com.jiangdg.uvc.IButtonCallback {
    *;
}
-keep class com.jiangdg.ausbc.** { *; }
-keep class com.jiangdg.usb.** { *; }

# === 避免反射问题 ===
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# === 保持注解 ===
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
-keepattributes InnerClasses
-keepattributes EnclosingMethod
