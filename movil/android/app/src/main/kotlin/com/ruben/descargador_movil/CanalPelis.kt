package com.ruben.descargador_movil

import android.os.Handler
import android.os.Looper
import com.ruben.descargador_movil.pelis.Pelisplus
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

/**
 * Canal propio para la pestania de peliculas y series.
 *
 * Como el de anime, es independiente del de descargas: si algo falla aqui no
 * toca la musica ni las descargas.
 */
object CanalPelis {

    private const val CANAL = "com.ruben.descargador/pelis"

    fun registrar(engine: FlutterEngine) {
        val principal = Handler(Looper.getMainLooper())
        val fuente = Pelisplus()

        MethodChannel(engine.dartExecutor.binaryMessenger, CANAL)
            .setMethodCallHandler { llamada, respuesta ->
                Thread {
                    val salida = try {
                        atender(llamada, fuente)
                    } catch (error: Throwable) {
                        fracaso("Kotlin: ${error.message}")
                    }
                    principal.post { runCatching { respuesta.success(salida) } }
                }.start()
            }
    }

    private fun atender(llamada: MethodCall, fuente: Pelisplus): String =
        when (llamada.method) {
            "buscar" -> lista(
                "resultados",
                fuente.buscar(llamada.argument<String>("texto").orEmpty()),
            ) { it.aJson() }
            "peliculas" -> lista(
                "resultados",
                fuente.peliculas(llamada.argument<Int>("pagina") ?: 1),
            ) { it.aJson() }
            "series" -> lista(
                "resultados",
                fuente.series(llamada.argument<Int>("pagina") ?: 1),
            ) { it.aJson() }
            "capitulos" -> lista(
                "capitulos",
                fuente.capitulos(llamada.argument<String>("url").orEmpty()),
            ) { it.aJson() }
            "servidores" -> lista(
                "servidores",
                fuente.servidores(llamada.argument<String>("url").orEmpty()),
            ) { it.aJson() }
            else -> fracaso("Metodo desconocido: ${llamada.method}")
        }

    private fun <T> lista(clave: String, datos: List<T>, aJson: (T) -> JSONObject): String {
        val arreglo = JSONArray()
        for (dato in datos) arreglo.put(aJson(dato))
        return JSONObject().put("ok", true).put(clave, arreglo).toString()
    }

    private fun fracaso(mensaje: String): String =
        JSONObject().put("ok", false).put("error", mensaje.ifBlank { "Error desconocido." }).toString()
}
