// Global configuration for plugins - FORCING SDK 36
extra.apply {
    set("compileSdkVersion", 36)
    set("targetSdkVersion", 36)
    set("minSdkVersion", 24)
    set("flutter.compileSdkVersion", 36)
    set("flutter.targetSdkVersion", 36)
    set("flutter.minSdkVersion", 24)
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    // Inject variables directly so Groovy plugins can see them as "project.compileSdkVersion"
    extra["compileSdkVersion"] = 36
    extra["targetSdkVersion"] = 36
    extra["minSdkVersion"] = 24
    extra["flutter.compileSdkVersion"] = 36
    extra["flutter.targetSdkVersion"] = 36
    
    // Also try to force the Android Extension directly if it exists
    plugins.whenPluginAdded {
        if (this is com.android.build.gradle.LibraryPlugin) {
            extensions.configure<com.android.build.gradle.LibraryExtension> {
                compileSdk = 36
                defaultConfig {
                    targetSdk = 36
                }
            }
        }
    }
}
