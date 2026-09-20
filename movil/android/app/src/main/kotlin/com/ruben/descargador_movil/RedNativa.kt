package com.ruben.descargador_movil

import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONObject

/** Lo que devuelve una peticion hecha por la red del sistema. */
class RespuestaNativa(
    @JvmField val estado: Int,
    @JvmField val url: String,
    /** Cabeceras en JSON: Python las vuelve a armar como diccionario. */
    @JvmField val cabeceras: String,
    @JvmField val cuerpo: ByteArray,
)

/**
 * Peticiones HTTP por la pila de red de Android.
 *
 * Existe por el saludo TLS. El Python del telefono trae su propio OpenSSL y hay
 * webs que reconocen esa huella y sirven un muro en vez de la pagina. Android
 * usa Conscrypt, la misma pila que Chrome, asi que su huella es la de un
 * navegador de verdad y pasa donde la otra no.
 *
 * La llama el nucleo Python a traves de Chaquopy, y solo cuando una descarga ya
 * choco con ese muro: lo que hoy funciona sigue yendo por su camino.
 */
class RedNativa {
    companion object {
        private const val ESPERA = 30_000

        @JvmStatic
        fun pedir(
            url: String,
            metodo: String,
            cabecerasJson: String,
            cuerpo: ByteArray?,
        ): RespuestaNativa {
            val conexion = URL(url).openConnection() as HttpURLConnection
            try {
                conexion.requestMethod = metodo
                conexion.connectTimeout = ESPERA
                conexion.readTimeout = ESPERA
                conexion.instanceFollowRedirects = true

                val cabeceras = JSONObject(cabecerasJson)
                for (nombre in cabeceras.keys()) {
                    conexion.setRequestProperty(nombre, cabeceras.getString(nombre))
                }

                if (cuerpo != null && cuerpo.isNotEmpty()) {
                    conexion.doOutput = true
                    conexion.outputStream.use { it.write(cuerpo) }
                }

                val estado = conexion.responseCode
                // Un 4xx o 5xx no trae inputStream sino errorStream, y el cuerpo
                // de un error muchas veces es justo lo que explica que paso.
                val flujo = if (estado in 200..299) conexion.inputStream else conexion.errorStream
                val datos = ByteArrayOutputStream()
                flujo?.use { it.copyTo(datos) }

                val salida = JSONObject()
                for ((nombre, valores) in conexion.headerFields) {
                    // La primera linea de la respuesta llega sin nombre.
                    if (nombre == null) continue
                    salida.put(nombre, valores.joinToString(", "))
                }

                return RespuestaNativa(
                    estado,
                    conexion.url.toString(),
                    salida.toString(),
                    datos.toByteArray(),
                )
            } finally {
                conexion.disconnect()
            }
        }
    }
}
