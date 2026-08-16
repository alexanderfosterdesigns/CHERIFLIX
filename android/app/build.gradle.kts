import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}
val releaseBuildRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

android {
    namespace = "com.example.cheriflix"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "app.cheriflix.tv.beta"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                storeType = keystoreProperties.getProperty("storeType", "JKS")
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else if (releaseBuildRequested) {
                throw GradleException(
                    "Release signing requires android/key.properties. " +
                        "Refusing to sign a release build with the debug key."
                )
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

// Render the app's real widgets before packaging the temporary screenshot APK.
// The generated PNGs are included as Android assets so CI can transport them
// without requiring a separate workflow artifact definition.
val renderUiScreenshots by tasks.registering(Exec::class) {
    workingDir(rootProject.projectDir.parentFile)
    commandLine(
        "flutter",
        "test",
        "--update-goldens",
        "test/ui_screenshots_test.dart",
    )
    doLast {
        copy {
            from(rootProject.projectDir.parentFile.resolve("test/ui_screenshots"))
            into(projectDir.resolve("src/main/assets/ui_screenshots"))
        }
    }
}

tasks.matching { it.name == "mergeReleaseAssets" }.configureEach {
    dependsOn(renderUiScreenshots)
}
