allprojects {
    repositories {
        // [kelivo-hosted] Aliyun mirrors in front of the upstream repos —
        // repo.maven.apache.org (Maven Central) returns 403 from this
        // network regardless of proxy, so dependency resolution needs a
        // reachable mirror tried first. google()/mavenCentral() stay as the
        // fallback for anything the mirror doesn't have.
        maven { url = uri("https://maven.aliyun.com/repository/google") }
        maven { url = uri("https://maven.aliyun.com/repository/public") }
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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
