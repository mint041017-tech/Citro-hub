// agora_rtc_engine 的 android/build.gradle 通过 safeExtGet('compileSdkVersion', 31)
// 读取根工程 ext，缺省值 31 低于其自身依赖（androidx.window 等）要求的 33+，
// 导致依赖校验冲突。这里在根工程注入与主工程一致（flutter.compileSdkVersion=36）的值。
rootProject.ext.set("compileSdkVersion", 36)

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
