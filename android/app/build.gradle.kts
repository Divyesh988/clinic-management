import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
val hasSigningProperties = signingPropertiesFile.exists()

if (hasSigningProperties) {
    FileInputStream(signingPropertiesFile).use { stream ->
        signingProperties.load(stream)
    }
}

android {
    namespace = "com.example.clinic_mangement"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.example.clinic_mangement"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasSigningProperties) {
                val storePath = signingProperties.getProperty("storeFile")
                val storePasswordValue = signingProperties.getProperty("storePassword")
                val keyAliasValue = signingProperties.getProperty("keyAlias")
                val keyPasswordValue = signingProperties.getProperty("keyPassword")

                if (
                    !storePath.isNullOrBlank() &&
                    !storePasswordValue.isNullOrBlank() &&
                    !keyAliasValue.isNullOrBlank() &&
                    !keyPasswordValue.isNullOrBlank()
                ) {
                    val resolvedFile = rootProject.file(storePath)
                    if (!resolvedFile.exists()) {
                        throw GradleException(
                            "Release signing storeFile does not exist: ${resolvedFile.absolutePath}"
                        )
                    }
                    storeFile = resolvedFile
                    storePassword = storePasswordValue
                    keyAlias = keyAliasValue
                    keyPassword = keyPasswordValue
                } else {
                    throw GradleException(
                        "Release signing properties in key.properties are incomplete (storeFile, storePassword, keyAlias, and keyPassword are required)."
                    )
                }
            } else {
                // If key.properties does not exist, fail explicitly when release build is requested
                gradle.taskGraph.whenReady {
                    val isReleaseBuild = allTasks.any { task ->
                        val name = task.name.lowercase()
                        name.contains("release") && (name.contains("apk") || name.contains("bundle") || name.contains("assemble"))
                    }
                    if (isReleaseBuild) {
                        throw GradleException(
                            "Release signing failed: 'android/key.properties' is missing. Release APKs cannot be built with debug or missing credentials."
                        )
                    }
                }
            }
        }
    }

    buildTypes {
        getByName("release") {
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
