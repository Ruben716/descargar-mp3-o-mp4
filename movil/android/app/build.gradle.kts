plugins {
    id("com.android.application")
    // Chaquopy debe aplicarse despues del plugin de Android.
    id("com.chaquo.python")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.ruben.descargador_movil"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.ruben.descargador_movil"
        // Android 10: es la version donde MediaStore permite escribir en
        // Musica y Peliculas sin permisos de almacenamiento heredados.
        minSdk = 29
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Solo movil real por USB/WiFi. Evita empaquetar Python y los binarios
        // nativos por duplicado para arquitecturas que no vamos a usar.
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // Android moderno no extrae las librerias del APK, las carga en
            // sitio. Pero libffmpeg.zip.so no es una libreria: es un ZIP que
            // tenemos que abrir como archivo, y el ejecutable de FFmpeg solo
            // puede correr desde esta carpeta. Con el empaquetado clasico el
            // instalador las deja en disco.
            useLegacyPackaging = true
            // Ese mismo ZIP no es un objeto ELF, asi que llvm-strip falla al
            // intentar limpiarlo. Se excluye del proceso.
            keepDebugSymbols += "**/libffmpeg.zip.so"
        }
    }
}

// El plugin de Flutter anade las tres arquitecturas despues de nuestro bloque
// android{}, y Chaquopy no publica Python 3.14 para armeabi-v7a. finalizeDsl se
// ejecuta cuando todos los plugins han terminado, asi que aqui gana el ultimo.
androidComponents {
    finalizeDsl { dsl ->
        dsl.defaultConfig.ndk.abiFilters.clear()
        dsl.defaultConfig.ndk.abiFilters.add("arm64-v8a")
    }
}

dependencies {
    // Trae el ejecutable ffmpeg y ffprobe compilados para Android, mas sus
    // librerias comprimidas en libffmpeg.zip.so. abiFilters recorta el resto
    // de arquitecturas, asi que solo pesa lo de arm64.
    implementation("com.github.yausername.youtubedl-android:ffmpeg:0.14.0")
    // NotificationCompat para la notificacion del servicio de descarga.
    implementation("androidx.core:core-ktx:1.15.0")
}

chaquopy {
    defaultConfig {
        // Coincide con el Python del equipo, que es lo que Gradle usa para pip.
        version = "3.14"
        pip {
            install("yt-dlp")
        }
    }
}

// El nucleo Python vive en la raiz del repositorio y lo comparten la consola y
// la app. Se copia aqui antes de compilar para no duplicarlo en git.
val sincronizarNucleo by tasks.registering(Sync::class) {
    from(rootProject.file("../../descargador"))
    into(layout.projectDirectory.dir("src/main/python/descargador"))
}

// Chaquopy empaqueta src/main/python, que es justo donde escribe la copia, asi
// que hay que declarar el orden o Gradle no garantiza que exista a tiempo.
tasks.matching { it.name.endsWith("PythonSources") || it.name == "preBuild" }
    .configureEach { dependsOn(sincronizarNucleo) }

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
