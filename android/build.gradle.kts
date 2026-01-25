import com.android.build.gradle.LibraryExtension
import com.android.build.gradle.LibraryPlugin

// Force SDK 35 for all projects including plugins like isar_flutter_libs
val sdkVersion = 35

allprojects {
    repositories {
        google()
        mavenCentral()
    }
    
    // Set extra properties that plugins read
    extra["compileSdkVersion"] = sdkVersion
    extra["targetSdkVersion"] = sdkVersion
    extra["minSdkVersion"] = 24
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

// Force compileSdk on library plugins (like isar_flutter_libs) - runs when plugin is applied
subprojects {
    plugins.withType<LibraryPlugin> {
        extensions.configure<LibraryExtension> {
            compileSdk = sdkVersion
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
