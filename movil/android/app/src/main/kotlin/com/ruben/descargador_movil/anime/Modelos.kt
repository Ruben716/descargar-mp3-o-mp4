package com.ruben.descargador_movil.anime

import org.json.JSONObject

/**
 * Modelos de una fuente de anime externa (por ahora JKanime).
 *
 * Son deliberadamente tontos: solo llevan los datos que la app pinta. La
 * conversion a JSON la usan los metodos del canal, que es lo unico que cruza
 * hacia Flutter.
 */
data class AnimeFuente(
    val url: String,
    val titulo: String,
    val portada: String = "",
    val tipo: String = "",
    val estado: String = "",
) {
    fun aJson(): JSONObject = JSONObject()
        .put("url", url)
        .put("titulo", titulo)
        .put("portada", portada)
        .put("tipo", tipo)
        .put("estado", estado)
}

data class EpisodioFuente(
    val numero: String,
    val url: String,
) {
    fun aJson(): JSONObject = JSONObject()
        .put("numero", numero)
        .put("url", url)
}

data class ServidorFuente(
    val nombre: String,
    val idioma: String,
    val url: String,
) {
    fun aJson(): JSONObject = JSONObject()
        .put("nombre", nombre)
        .put("idioma", idioma)
        .put("url", url)
}

/** Lo que devuelve un extractor: la direccion reproducible y sus cabeceras. */
data class StreamResuelto(
    val url: String,
    val cabeceras: Map<String, String> = emptyMap(),
)
