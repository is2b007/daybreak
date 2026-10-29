import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val daybreakVersion = rootProject.file("../../VERSION").readText().trim()
val hostedUrl = (findProperty("daybreakHostedUrl") as String?).orEmpty()

android {
    namespace = "app.daybreak.android"
    compileSdk = 35

    defaultConfig {
        applicationId = "app.daybreak.android"
        minSdk = 28
        targetSdk = 35
        versionName = daybreakVersion
        versionCode = (System.getenv("GITHUB_RUN_NUMBER") ?: "1").toInt()
        buildConfigField("String", "HOSTED_URL", "\"$hostedUrl\"")
    }

    // Release builds are signed with the key in DAYBREAK_KEYSTORE (a path), when
    // it is set. Without it they use this machine's debug key, which is fine for
    // sideloading onto your own device.
    val releaseKeystore = System.getenv("DAYBREAK_KEYSTORE").orEmpty()
    signingConfigs {
        create("release") {
            if (releaseKeystore.isNotBlank()) {
                storeFile = file(releaseKeystore)
                storePassword = System.getenv("DAYBREAK_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("DAYBREAK_KEY_ALIAS")
                keyPassword = System.getenv("DAYBREAK_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName(if (releaseKeystore.isNotBlank()) "release" else "debug")
        }
    }

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        named("main") { java { srcDirs("src/main/kotlin") } }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation("dev.hotwire:core:1.3.2")
    implementation("dev.hotwire:navigation-fragments:1.3.2")
    implementation("com.google.android.material:material:1.12.0")
    implementation("androidx.browser:browser:1.8.0")
}
