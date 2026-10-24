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

// CameraX 1.6.1 exposes CallbackToFutureAdapter in a public class signature but
// publishes androidx.concurrent as runtime-only. Make that type available while
// compiling the Flutter CameraX plugin without changing the app's runtime graph.
subprojects {
    if (name == "camera_android_camerax") {
        pluginManager.withPlugin("com.android.library") {
            dependencies.add(
                "compileOnly",
                "androidx.concurrent:concurrent-futures:1.1.0",
            )
        }
    }

    // tflite_flutter compiles its Java sources for JVM 11. With a newer JDK,
    // Kotlin can otherwise inherit the host JVM target (25), and Gradle rejects
    // the plugin because its Java and Kotlin targets do not match.
    if (name == "tflite_flutter") {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(
                org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11,
            )
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
