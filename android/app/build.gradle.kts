import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.io.FileInputStream
import java.util.Properties

plugins {
    alias(libs.plugins.kotlinAndroid)
    alias(libs.plugins.androidApplication)
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = libs.versions.appNamespace.get()
    ndkVersion = libs.versions.ndkVersion.get()
    compileSdk = libs.versions.compileSdk.get().toInt()

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.toVersion(libs.versions.java.get())
        targetCompatibility = JavaVersion.toVersion(libs.versions.java.get())
    }

    subprojects {
        afterEvaluate {
            if (hasProperty("android")) {
                extensions.configure<com.android.build.gradle.BaseExtension> {
                    ndkVersion = libs.versions.ndkVersion.get()
                    compileOptions {
                        isCoreLibraryDesugaringEnabled = true
                        sourceCompatibility = JavaVersion.toVersion(libs.versions.java.get())
                        targetCompatibility = JavaVersion.toVersion(libs.versions.java.get())
                    }
                }
                tasks.withType<JavaCompile> {
                    options.compilerArgs.addAll(listOf("-Xlint:-options", "-Xlint:-deprecation"))
                }
            }
        }
    }

    kotlin {
        compilerOptions {
            jvmTarget = JvmTarget.fromTarget(libs.versions.jvmTarget.get())
        }
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = libs.versions.appId.get()
        minSdk = libs.versions.minSdk.get().toInt()
        targetSdk = libs.versions.targetSdk.get().toInt()
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("int", "UVC_MIN_FPS", libs.versions.uvcMinFps.get())
        buildConfigField("int", "UVC_MAX_FPS", libs.versions.uvcMaxFps.get())
        buildConfigField("int", "UVC_FRAME_FORMAT", libs.versions.uvcFrameFormat.get())
        buildConfigField("int", "UVC_PREFERRED_WIDTH", libs.versions.uvcPreferredWidth.get())
        buildConfigField("int", "UVC_PREFERRED_HEIGHT", libs.versions.uvcPreferredHeight.get())
        buildConfigField(
            "float",
            "UVC_BANDWIDTH_FACTOR",
            "${libs.versions.uvcBandwidthFactor.get()}f",
        )
    }
    val keystorePropertiesFile = rootProject.file("key.properties")
    val hasSigningConfig = keystorePropertiesFile.exists()

    signingConfigs {
        if (hasSigningConfig) {
            create("release") {
                val properties = Properties()
                properties.load(FileInputStream(keystorePropertiesFile))

                storeFile = file(properties.getProperty("storeFile")!!)
                storePassword = properties.getProperty("storePassword")
                keyAlias = properties.getProperty("keyAlias")
                keyPassword = properties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            if (hasSigningConfig) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // 本地开发的调试签名的回退
                signingConfig = signingConfigs.getByName("debug")
            }
            // 启用 R8 代码缩减、混淆和优化
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            // Keep debug builds fast
            isMinifyEnabled = false
        }
        // 快速发布构建：用于日常测试，跳过部分优化
        create("fastRelease") {
            initWith(getByName("release"))
            // 禁用资源压缩（提速 5-10s）
            isShrinkResources = false
            // 使用更简单混淆规则
            proguardFiles(
                getDefaultProguardFile("proguard-android.txt"),
                "proguard-rules.pro"
            )
            // 更快的构建，稍大的包
            isMinifyEnabled = false
        }
    }
}

dependencies {
    implementation(libs.google.gson)
    implementation(libs.androidx.appcompat)
    implementation(libs.android.usb.camera.libuvc)
    implementation(libs.android.usb.camera.libusbc)
    coreLibraryDesugaring(libs.android.desugar.jdk.libs)
}

flutter {
    source = "../.."
}
