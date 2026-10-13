allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// flutter_google_places_sdk_android's Kotlin code targets the legacy Places
// SDK Place API (place.address/latLng/name/...), which its own default
// version (5.1.1, set in its gradle.properties) no longer exposes. Force
// every project's dependency resolution — including the plugin module's own
// compile classpath — onto the last 3.x release that still has those fields.
allprojects {
    configurations.all {
        resolutionStrategy {
            force("com.google.android.libraries.places:places:3.5.0")
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
