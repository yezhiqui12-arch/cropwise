import java.util.Properties
import java.security.KeyStore

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingPropertiesFile = System.getenv("WORMWISE_SIGNING_PROPERTIES")
    ?.let { file(it) } ?: rootProject.file("key.properties")
val signingProperties = Properties().apply {
    if (signingPropertiesFile.isFile) signingPropertiesFile.inputStream().use { load(it) }
}
val signingFields = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
val hasReleaseSigning = signingFields.all { !signingProperties.getProperty(it).isNullOrBlank() }
val verifyWormWiseReleaseSigning = tasks.register("verifyWormWiseReleaseSigning") {
    doLast {
        if (!hasReleaseSigning) throw GradleException(
            "Production signing is missing. Configure android/key.properties or WORMWISE_SIGNING_PROPERTIES; see docs/PRODUCTION_SIGNING.md."
        )
        if (!file(signingProperties.getProperty("storeFile")).isFile) {
            throw GradleException("The configured production signing keystore is unavailable.")
        }
        try {
            val store = KeyStore.getInstance(
                file(signingProperties.getProperty("storeFile")),
                signingProperties.getProperty("storePassword").toCharArray()
            )
            val alias = signingProperties.getProperty("keyAlias")
            if (!store.isKeyEntry(alias) || store.getKey(alias,
                    signingProperties.getProperty("keyPassword").toCharArray()) == null) {
                throw GradleException("The production signing alias has no private key.")
            }
        } catch (_: Exception) {
            throw GradleException("The production signing credentials could not be validated.")
        }

    }
}
// Debug/profile builds stay available without production credentials. Every
// release variant fails closed instead of silently using a development key.
tasks.matching { it.name == "preReleaseBuild" }.configureEach {
    dependsOn(verifyWormWiseReleaseSigning)
}

android {
    namespace = "com.wormwise.app.wormwise"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.wormwise.app.wormwise"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeType = signingProperties.getProperty("storeType", "PKCS12")
                storeFile = file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
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
