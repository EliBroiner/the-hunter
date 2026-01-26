plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Google Services - Firebase
    id("com.google.gms.google-services")
}

// קריאת משתני סביבה לחתימה
val envKeystorePath: String? = System.getenv("KEYSTORE_PATH")
val envKeystorePassword: String? = System.getenv("KEYSTORE_PASSWORD")
val envKeyAlias: String? = System.getenv("KEY_ALIAS")
val envKeyPassword: String? = System.getenv("KEY_PASSWORD")

// בדיקה אם כל המשתנים קיימים
val hasSigningConfig = envKeystorePath != null && 
                       envKeystorePassword != null && 
                       envKeyAlias != null && 
                       envKeyPassword != null

// Debug output
println("🔐 Signing Config Check:")
println("   KEYSTORE_PATH: ${if (envKeystorePath != null) "SET" else "NOT SET"}")
println("   KEYSTORE_PASSWORD: ${if (envKeystorePassword != null) "SET" else "NOT SET"}")
println("   KEY_ALIAS: ${if (envKeyAlias != null) "SET" else "NOT SET"}")
println("   KEY_PASSWORD: ${if (envKeyPassword != null) "SET" else "NOT SET"}")
println("   Using release signing: $hasSigningConfig")

android {
    namespace = "com.thehunter.the_hunter"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.thehunter.the_hunter"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // הגדרת חתימות
    signingConfigs {
        if (hasSigningConfig) {
            create("release") {
                storeFile = file(envKeystorePath!!)
                storePassword = envKeystorePassword
                keyAlias = envKeyAlias
                keyPassword = envKeyPassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasSigningConfig) {
                signingConfigs.getByName("release")
            } else {
                println("⚠️ Using debug signing config for release build")
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
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
