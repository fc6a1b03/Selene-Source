pluginManagement {
    var inVersionsSection = false
    val versions = mutableMapOf<String, String>()
    val versionCatalogFile = file("gradle/libs.versions.toml")
    val versionPattern = Regex("""^([A-Za-z0-9_.-]+)\s*=\s*"([^"]+)"""")

    versionCatalogFile.forEachLine { line ->
        val trimmed = line.trim()
        if (trimmed.startsWith("[")) {
            inVersionsSection = trimmed == "[versions]"
        } else if (inVersionsSection) {
            versionPattern.matchEntire(trimmed)?.let { match ->
                versions[match.groupValues[1]] = match.groupValues[2]
            }
        }
    }

    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }

    plugins {
        id("org.jetbrains.kotlin.android") version versions.getValue("kotlin")
        id("com.android.application") version versions.getValue("androidGradlePlugin")
        id("dev.flutter.flutter-plugin-loader") version versions.getValue("flutterPluginLoader")
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.PREFER_SETTINGS)
    repositories {
        maven(url = "https://storage.googleapis.com/download.flutter.io")
        google()
        mavenCentral()
        maven(url = "https://jitpack.io")
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader")
    id("com.android.application") apply false
    id("org.jetbrains.kotlin.android") apply false
}

include(":app")
