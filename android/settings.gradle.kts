pluginManagement {
    val flutterSdkPath = run {
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
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    // 8.9.1 is the floor, not a preference: androidx.core 1.17 and
    // androidx.browser 1.9 — pulled in transitively by supabase_flutter — refuse
    // to build under anything older, and the release build fails at
    // checkReleaseAarMetadata rather than at compile.
    //
    // The Gradle wrapper is already 8.12, above the 8.11.1 this needs, so it
    // does not move.
    id("com.android.application") version "8.9.1" apply false
    id("org.jetbrains.kotlin.android") version "2.1.0" apply false
}

include(":app")
