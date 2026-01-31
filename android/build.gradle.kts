import com.android.build.gradle.LibraryExtension
import org.gradle.api.tasks.compile.JavaCompile

plugins {
    // Google Services - Firebase
    id("com.google.gms.google-services") version "4.4.2" apply false
}

// Force SDK 36 for all projects
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
    // השתקת הערות Java מספריות צד־שלישי (כולל פלאגינים מ-pub cache)
    tasks.withType<JavaCompile>().configureEach {
        options.compilerArgs.addAll(listOf("-Xlint:-options", "-Xlint:-deprecation", "-Xlint:-unchecked"))
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
// כפיית compileSdk 36 על ספריות (פותר android:attr/lStar not found)
subprojects {
    fun setCompileSdk() {
        project.extensions.findByType(LibraryExtension::class.java)?.apply {
            compileSdk = 36
        }
    }
    if (project.state.executed) setCompileSdk() else project.afterEvaluate { setCompileSdk() }
}
tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
