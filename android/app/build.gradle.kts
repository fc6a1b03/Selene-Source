import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.io.FileInputStream
import java.util.Properties

plugins {
    id("kotlin-android")
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "org.moontechlab.selene"
    compileSdk = 36
    ndkVersion = "29.0.14206865"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    subprojects {
        afterEvaluate {
            if (hasProperty("android")) {
                extensions.configure<com.android.build.gradle.BaseExtension> {
                    compileOptions {
                        sourceCompatibility = JavaVersion.VERSION_17
                        targetCompatibility = JavaVersion.VERSION_17
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
            jvmTarget = JvmTarget.JVM_17
        }
    }

    defaultConfig {
        applicationId = "org.moontechlab.selene"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
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

flutter {
    source = "../.."
}
