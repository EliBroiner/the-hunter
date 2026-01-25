import com.android.build.gradle.LibraryExtension
import com.android.build.gradle.LibraryPlugin

// הגדרות SDK גלובליות שFlutter plugins קוראים
extra.apply {
    set("compileSdkVersion", 36)
    set("targetSdkVersion", 36)
    set("minSdkVersion", 24)
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

// כפה SDK 36 על כל ספריות Android (plugins כמו isar)
subprojects {
    plugins.withType<LibraryPlugin> {
        extensions.configure<LibraryExtension> {
            compileSdk = 36
            defaultConfig {
                targetSdk = 36
            }
        }
    }
}
