plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "uz.telefontv.telefon_tv"
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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "uz.telefontv.telefon_tv"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Native kutubxonalar (internetsiz nutq — sherpa-onnx, Flutter) APK
    // ichida siqilgan: yuklab olish hajmi kichikroq, o‘rnatishda ochiladi.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // USB fleshkaga yozishda HEVC videoni televizor o‘qiydigan H.264 ga o‘tkazish.
    // Versiya video_player_android ishlatadigan Media3 bilan bir xil.
    implementation("androidx.media3:media3-transformer:1.9.2")
    implementation("androidx.media3:media3-common:1.9.2")
    implementation("androidx.media3:media3-effect:1.9.2")
}

flutter {
    source = "../.."
}
