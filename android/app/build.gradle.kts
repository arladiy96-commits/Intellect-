plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "ai.moy.moy_ai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.2.12479018"

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ai.moy.moy_ai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 28
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("baboonRelease") {
            storeFile = file(System.getenv("BABOON_KEYSTORE_PATH") ?: "missing-baboon-signing-key.p12")
            storePassword = System.getenv("BABOON_STORE_PASSWORD") ?: ""
            keyAlias = "baboon"
            keyPassword = System.getenv("BABOON_KEY_PASSWORD") ?: ""
        }
    }

    buildTypes {
        release {
            // Persistent private signing key, sourced ONLY from GitHub Secrets.
            signingConfig = signingConfigs.getByName("baboonRelease")
            // JNI calls emitToken(String) by name from C++. R8 must keep it.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // FileProvider sends the APK securely to Android's system installer.
    implementation("androidx.core:core:1.15.0")
}

flutter {
    source = "../.."
}
