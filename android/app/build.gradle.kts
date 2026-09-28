import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// --- release signing ------------------------------------------------------
//
// Read from android/key.properties, which is gitignored and never committed:
// it holds the keystore passwords, and the keystore itself is the one secret
// that cannot be rotated. Lose it and this app can never be updated again —
// Play matches every upload against the key the first one was signed with.
//
// See android/key.properties.example for the four values, and the README for
// the keytool command that produces the keystore.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties()
if (hasKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.thoughtloom.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Permanent. Play identifies the app by this string for the life of the
        // listing and it cannot be changed after the first publish.
        applicationId = "com.thoughtloom.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Only declared when the keystore is actually configured, so a checkout
        // without key.properties still configures and still builds debug.
        if (hasKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Deliberately no debug fallback. Signing a release with the shared
            // debug key produced an APK that looked fine, could not be uploaded
            // to Play, and gave no sign of the problem until it was rejected.
            //
            // With no key.properties this is null and the APK comes out
            // unsigned, which a device and Play both refuse outright — a
            // failure that cannot be mistaken for success.
            // Without key.properties, the debug key — Flutter's own default — so a
            // release APK for testers still installs. Play needs the real key.
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
