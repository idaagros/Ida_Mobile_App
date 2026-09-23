plugins {
    id("com.android.application")
    id("kotlin-android")
    // Push notifications (Firebase) — reads android/app/google-services.json
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ida.agrico"
    // Hardcoded rather than left as flutter.compileSdkVersion/flutter.ndkVersion —
    // google_mlkit_face_detection/commons need compileSdk 36, and
    // camera_android_camerax + several other plugins need NDK
    // 27.0.12077973. Both are backward compatible with everything
    // else in the project (per Flutter's own build warning).
    compileSdk = 36
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.ida.agrico"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Firebase Messaging needs at least Android 6 (API 23).
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            // R8 minification was already running by default on this
            // release build (confirmed directly from the build error)
            // but with no custom keep rules wired in - added here so
            // the ML Kit plugin classes it needs aren't stripped.
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // google_mlkit_text_recognition's Dart-side TextRecognitionScript
    // parameter alone does not pull in anything beyond Latin script -
    // confirmed directly from the package's own documentation: "By
    // default, this package only supports recognition of Latin
    // characters. If you need to recognize other languages, you need
    // to manually add dependencies." This app now uses
    // TextRecognitionScript.devanagari for Marathi handwritten notes,
    // so the native Devanagari model is added explicitly here.
    implementation("com.google.mlkit:text-recognition-devanagari:16.0.1")
}