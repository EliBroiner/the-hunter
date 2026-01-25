import com.android.build.gradle.LibraryExtension

// הגדרות SDK גלובליות שFlutter plugins קוראים
extra.apply {
    set("compileSdkVersion", 35)
    set("targetSdkVersion", 35)
    set("minSdkVersion", 24)
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
    
    // כפה SDK 35 על כל ספריות Android (plugins כמו isar)
    plugins.withId("com.android.library") {
        extensions.configure<LibraryExtension> {
            compileSdk = 35
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
