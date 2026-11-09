import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Chave do projeto para assinar o APK (android/key.properties, fora do git; modelo em
// key.properties.example). Todo APK precisa da MESMA chave, senao o celular recusa a atualizacao.
// Sem o arquivo, o APK sai com a chave de teste deste PC (serve para testar, nao para distribuir).
val arquivoChave = rootProject.file("key.properties")
val chave = Properties().apply { if (arquivoChave.exists()) FileInputStream(arquivoChave).use { load(it) } }

android {
    signingConfigs {
        if (arquivoChave.exists()) {
            create("projeto") {
                storeFile = file(chave.getProperty("storeFile"))
                storePassword = chave.getProperty("storePassword")
                keyAlias = chave.getProperty("keyAlias")
                keyPassword = chave.getProperty("keyPassword")
            }
        }
    }

    namespace = "com.example.app_gerenciamento_energetico"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.app_gerenciamento_energetico"
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
    }

    buildTypes {
        release {
            signingConfig = if (arquivoChave.exists()) {
                signingConfigs.getByName("projeto")
            } else {
                logger.warn("key.properties nao encontrado: APK assinado com a chave de teste deste PC")
                signingConfigs.getByName("debug")
            }
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
