import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Local-only secrets (gitignored) — holds the Google Maps API key so it
// never ends up committed to source control.
val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}
val googleMapsApiKey: String = localProperties.getProperty("googleMaps.apiKey", "")

android {
    namespace = "com.example.trip_split_gujarat"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.trip_split_gujarat"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["googleMapsApiKey"] = googleMapsApiKey
    }

    signingConfigs {
        getByName("debug") {
            // Pinned to the keystore committed at app/debug.keystore instead of
            // Gradle's implicit per-machine ~/.android/debug.keystore, so every
            // build — local or CI — signs with the same key. That keeps the
            // SHA-1 stable, which is what the Google Maps API key is restricted to.
            storeFile = file("debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        create("release") {
            // Dedicated release certificate (PKCS12). Unlike the shared Android
            // debug cert — which every developer's machine uses and which Play
            // Protect blocks as an unsafe sideload — this is a unique cert, so
            // fresh installs from the GitHub asset are no longer blocked.
            // Committed alongside its password like debug.keystore above: same
            // informal model for this personal app; the key only governs who
            // can ship updates to it. Regenerating it would change the SHA-1
            // and require re-registering (below) and reinstalling every device.
            //
            // The Google Maps API key is SHA-1-restricted. Both certs' SHA-1s
            // must be on the key's Android restriction in Google Cloud Console:
            //   release: CC:F1:7A:DD:B4:5D:EA:72:5C:20:49:FF:53:01:0A:4C:4E:19:C9:6F
            //   debug:   used by `flutter run` / CI debug builds (already registered)
            storeFile = file("release.keystore")
            storeType = "PKCS12"
            storePassword = "<release-password>"
            keyAlias = "tripsplit"
            keyPassword = "<release-password>"
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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
    implementation("androidx.core:core-ktx:1.13.1")
    // On-device OCR for "Scan receipt" (bundled model, works offline).
    implementation("com.google.mlkit:text-recognition:16.0.1")
}
