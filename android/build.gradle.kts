import com.android.build.gradle.LibraryExtension
import com.android.build.gradle.LibraryPlugin

// Force SDK 36 for all projects (required by path_provider_android & speech_to_text)
val sdkVersion = 36

allprojects {
    repositories {
        google()
        mavenCentral()
    }
    
    // Set extra properties that plugins read
    extra["compileSdkVersion"] = sdkVersion
    extra["targetSdkVersion"] = sdkVersion  
    extra["minSdkVersion"] = 24
    
    // Force SDK on all library plugins including isar_flutter_libs
    plugins.withType<LibraryPlugin> {
        extensions.configure<LibraryExtension> {
            compileSdk = sdkVersion
            defaultConfig {
                minSdk = 24
                targetSdk = sdkVersion
            }
        }
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

// Use gradle.projectsEvaluated to force SDK after all projects are evaluated
gradle.projectsEvaluated {
    subprojects {
        extensions.findByType<LibraryExtension>()?.apply {
            compileSdk = sdkVersion
        }
    }
}
