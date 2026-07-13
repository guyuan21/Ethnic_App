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
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            val target = when (project.name) {
                "app",
                "audioplayers_android",
                "flutter_plugin_android_lifecycle",
                "image_picker_android",
                "record_android",
                "shared_preferences_android" -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
                else -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
            }
            jvmTarget.set(target)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
