plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.jeff.task_blocks"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Needed by flutter_local_notifications for scheduled reminders.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.jeff.task_blocks"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // CI passes --build-number=<run number>, so every build installs over the last.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // The permanent release key comes from CI secrets (see README). Without it the build
    // falls back to the debug key, which can't update an installed copy.
    val keystoreFile = System.getenv("ANDROID_KEYSTORE_FILE")?.let { file(it) }
    signingConfigs {
        if (keystoreFile != null && keystoreFile.exists()) {
            create("release") {
                storeFile = keystoreFile
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = "upload"
                keyPassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // On-device text recognition for "Photo of a list" (nothing is uploaded).
    implementation("com.google.mlkit:text-recognition:16.0.1")
}
