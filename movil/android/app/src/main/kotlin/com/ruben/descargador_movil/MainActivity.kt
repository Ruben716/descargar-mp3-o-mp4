package com.ruben.descargador_movil

import android.Manifest
import android.content.ContentUris
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.MediaStore
import android.system.Os
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.util.zip.ZipInputStream
import kotlin.concurrent.thread
import org.json.JSONArray
import org.json.JSONObject

/**
 * Puente Flutter -> Kotlin -> Python.
 *
 * Chaquopy arranca CPython dentro del proceso de la app y el canal deja que
 * Dart invoque el mismo nucleo que usa la version de consola.
 */
class MainActivity : FlutterActivity() {

    private val canal = "com.ruben.descargador/nucleo"

    @Volatile
    private var ffmpegListo = false

    /** Enlace llegado por Compartir, a la espera de que Flutter lo recoja. */
    @Volatile
    private var urlCompartida: String? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        recogerEnlace(intent)
        pedirPermisoNotificaciones()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        recogerEnlace(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal)
            .setMethodCallHandler { llamada, respuesta ->
                when (llamada.method) {
                    "diagnostico" -> enHilo(respuesta) { puente ->
                        asegurarFfmpeg(puente)
                        puente.callAttr("diagnostico").toString()
                    }
                    "informacion" -> {
                        val url = llamada.argument<String>("url").orEmpty()
                        enHilo(respuesta) { puente ->
                            puente.callAttr("informacion", url).toString()
                        }
                    }
                    "descargar" -> {
                        val ajustes = Ajustes(
                            url = llamada.argument<String>("url").orEmpty(),
                            soloAudio = llamada.argument<Boolean>("soloAudio") ?: false,
                            calidad = llamada.argument<Int>("calidad") ?: 0,
                            formatoAudio = llamada.argument<String>("formatoAudio") ?: "mp3",
                            bitrate = llamada.argument<String>("bitrate") ?: "192",
                            subtitulos = llamada.argument<String>("subtitulos").orEmpty(),
                            fragmento = llamada.argument<String>("fragmento").orEmpty(),
                            sinPatrocinios = llamada.argument<Boolean>("sinPatrocinios") ?: false,
                        )
                        enHilo(respuesta) { puente -> descargar(puente, ajustes) }
                    }
                    "buscar" -> {
                        val texto = llamada.argument<String>("texto").orEmpty()
                        val limite = llamada.argument<Int>("limite") ?: 10
                        enHilo(respuesta) { puente ->
                            puente.callAttr("buscar", texto, limite).toString()
                        }
                    }
                    "biblioteca" -> enHilo(respuesta) { _ -> biblioteca() }
                    // Consulta ligera: Flutter la repite mientras dura la descarga.
                    "progreso" -> enHilo(respuesta) { puente ->
                        puente.callAttr("progreso").toString()
                    }
                    // Flutter la consulta al abrir y al volver del segundo plano.
                    "urlCompartida" -> {
                        val pendiente = urlCompartida
                        urlCompartida = null
                        respuesta.success(pendiente)
                    }
                    else -> respuesta.notImplemented()
                }
            }
    }

    /** Todo lo que el usuario puede ajustar antes de descargar. */
    private data class Ajustes(
        val url: String,
        val soloAudio: Boolean,
        val calidad: Int,
        val formatoAudio: String,
        val bitrate: String,
        val subtitulos: String,
        val fragmento: String,
        val sinPatrocinios: Boolean,
    )

    /**
     * Descarga con el proceso protegido y deja el resultado en la biblioteca
     * del movil, para que aparezca en la galeria o el reproductor de musica.
     */
    private fun descargar(puente: PyObject, ajustes: Ajustes): String {
        asegurarFfmpeg(puente)
        ServicioDescarga.arrancar(this)
        try {
            val crudo = puente.callAttr(
                "descargar",
                ajustes.url,
                carpetaTrabajo().absolutePath,
                ajustes.soloAudio,
                ajustes.calidad,
                ajustes.formatoAudio,
                ajustes.bitrate,
                ajustes.subtitulos,
                ajustes.fragmento,
                ajustes.sinPatrocinios,
            ).toString()

            val datos = JSONObject(crudo)
            if (!datos.optBoolean("ok")) return crudo

            val origen = datos.optJSONArray("archivos") ?: JSONArray()
            val guardados = JSONArray()
            for (i in 0 until origen.length()) {
                val archivo = File(origen.getString(i))
                guardados.put(exportarABiblioteca(archivo, ajustes.soloAudio) ?: archivo.absolutePath)
            }
            return JSONObject().put("ok", true).put("archivos", guardados).toString()
        } finally {
            ServicioDescarga.detener(this)
        }
    }

    /** Lo descargado, leido de la biblioteca del telefono. */
    private fun biblioteca(): String {
        val salida = JSONArray()
        listar(
            MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            "Music/Descargador/", true, salida,
        )
        listar(
            MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY),
            "Movies/Descargador/", false, salida,
        )
        return JSONObject().put("ok", true).put("elementos", salida).toString()
    }

    private fun listar(coleccion: Uri, carpeta: String, esAudio: Boolean, salida: JSONArray) {
        val columnas = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME,
            MediaStore.MediaColumns.SIZE,
            MediaStore.MediaColumns.DURATION,
        )
        try {
            contentResolver.query(
                coleccion,
                columnas,
                "${MediaStore.MediaColumns.RELATIVE_PATH} LIKE ?",
                arrayOf("$carpeta%"),
                "${MediaStore.MediaColumns.DATE_ADDED} DESC",
            )?.use { cursor ->
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(0)
                    salida.put(
                        JSONObject()
                            .put("nombre", cursor.getString(1) ?: "")
                            .put("tamano", cursor.getLong(2))
                            .put("duracion", cursor.getLong(3) / 1000)
                            .put("audio", esAudio)
                            .put("uri", ContentUris.withAppendedId(coleccion, id).toString()),
                    )
                }
            }
        } catch (error: Throwable) {
            // Una coleccion vacia o inaccesible no debe tumbar la biblioteca.
        }
    }

    /**
     * Copia el archivo a Musica/ o Peliculas/ mediante MediaStore y borra el
     * temporal. Asi lo ven el resto de apps del telefono.
     */
    private fun exportarABiblioteca(archivo: File, esAudio: Boolean): String? {
        if (!archivo.isFile) return null
        return try {
            val coleccion = if (esAudio) {
                MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            }
            val carpeta = if (esAudio) "Music/Descargador" else "Movies/Descargador"
            val valores = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, archivo.name)
                put(MediaStore.MediaColumns.MIME_TYPE, if (esAudio) "audio/mpeg" else "video/mp4")
                put(MediaStore.MediaColumns.RELATIVE_PATH, carpeta)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val destino = contentResolver.insert(coleccion, valores) ?: return null
            contentResolver.openOutputStream(destino)?.use { salida ->
                archivo.inputStream().use { it.copyTo(salida) }
            } ?: return null

            valores.clear()
            valores.put(MediaStore.MediaColumns.IS_PENDING, 0)
            contentResolver.update(destino, valores, null, null)
            archivo.delete()
            "$carpeta/${archivo.name}"
        } catch (error: Throwable) {
            // Si la biblioteca falla, el archivo sigue en la carpeta de la app.
            null
        }
    }

    /**
     * Python aqui hace red y disco, asi que nunca puede correr en el hilo
     * principal: Android lanzaria NetworkOnMainThreadException.
     */
    private fun enHilo(
        respuesta: MethodChannel.Result,
        trabajo: (PyObject) -> String,
    ) {
        thread {
            val salida = try {
                trabajo(Python.getInstance().getModule("puente"))
            } catch (error: Throwable) {
                """{"ok": false, "error": "Kotlin: ${error.message}"}"""
            }
            runOnUiThread { respuesta.success(salida) }
        }
    }

    private fun recogerEnlace(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND) return
        val texto = intent.getStringExtra(Intent.EXTRA_TEXT) ?: return
        // Lo compartido suele traer titulo y enlace juntos; se queda el enlace.
        urlCompartida = texto.split(Regex("\\s+")).firstOrNull { it.startsWith("http") } ?: texto
    }

    private fun pedirPermisoNotificaciones() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        val concedido = ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS)
        if (concedido != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(this, arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
        }
    }

    private fun carpetaTrabajo(): File =
        (getExternalFilesDir(null) ?: filesDir).resolve("descargas").apply { mkdirs() }

    /**
     * Deja FFmpeg utilizable y se lo comunica a Python. Solo la primera vez.
     */
    @Synchronized
    private fun asegurarFfmpeg(puente: PyObject) {
        if (ffmpegListo) return
        val nativos = applicationInfo.nativeLibraryDir
        val librerias = extraerLibreriasFfmpeg(nativos)

        // Android solo ejecuta binarios desde la carpeta de librerias nativas,
        // donde llegan con nombre libffmpeg.so. yt-dlp busca ficheros llamados
        // "ffmpeg" y "ffprobe", asi que se enlazan con esos nombres.
        val bin = File(filesDir, "bin").apply { mkdirs() }
        enlazar(File(nativos, "libffmpeg.so"), File(bin, "ffmpeg"))
        enlazar(File(nativos, "libffprobe.so"), File(bin, "ffprobe"))

        puente.callAttr("preparar", bin.absolutePath, librerias.absolutePath)
        ffmpegListo = true
    }

    /**
     * libffmpeg.zip.so es un ZIP con libavcodec y demas. Se descomprime una vez
     * en el almacenamiento de la app; de ahi las carga el ejecutable.
     */
    private fun extraerLibreriasFfmpeg(nativos: String): File {
        val raiz = File(filesDir, "ffmpeg")
        val destino = File(raiz, "usr/lib")
        val marca = File(raiz, ".completo")
        // La marca guarda de que instalacion salieron las librerias: al
        // actualizar la app cambia la ruta nativa y hay que volver a extraer.
        if (marca.exists() && marca.readText() == nativos) return destino

        raiz.deleteRecursively()
        raiz.mkdirs()
        ZipInputStream(FileInputStream(File(nativos, "libffmpeg.zip.so"))).use { zip ->
            var entrada = zip.nextEntry
            while (entrada != null) {
                val salida = File(raiz, entrada.name)
                if (entrada.isDirectory) {
                    salida.mkdirs()
                } else {
                    salida.parentFile?.mkdirs()
                    salida.outputStream().use { zip.copyTo(it) }
                }
                entrada = zip.nextEntry
            }
        }
        marca.writeText(nativos)
        return destino
    }

    private fun enlazar(origen: File, enlace: File) {
        try {
            // Ojo: exists() sigue el enlace, asi que devuelve false cuando esta
            // roto (pasa en cada reinstalacion, porque cambia la ruta nativa) y
            // el enlace viejo se quedaria ahi haciendo fallar a symlink.
            enlace.delete()
            Os.symlink(origen.absolutePath, enlace.absolutePath)
        } catch (error: Throwable) {
            // Sin enlace simbolico se seguira pudiendo descargar: yt-dlp acepta
            // la ruta directa al ejecutable, solo se pierde ffprobe.
        }
    }
}
