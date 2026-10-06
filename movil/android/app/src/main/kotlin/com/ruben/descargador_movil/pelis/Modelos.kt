package com.ruben.descargador_movil.pelis

import org.json.JSONObject

/** Una pelicula o serie del catalogo de PelisPlusHD. */
data class Peli(
    val url: String,
    val titulo: String,
    val portada: String = "",
    val tipo: String = "",
) {
    fun aJson(): JSONObject = JSONObject()
        .put("url", url)
        .put("titulo", titulo)
        .put("portada", portada)
        .put("tipo", tipo)
}

/** Un capitulo de una serie, con su temporada y numero. */
data class CapituloPeli(
    val url: String,
    val temporada: String,
    val numero: String,
    val titulo: String,
) {
    fun aJson(): JSONObject = JSONObject()
        .put("url", url)
        .put("temporada", temporada)
        .put("numero", numero)
        .put("titulo", titulo)
}

/** Un servidor de video (embed) de una pelicula o capitulo. */
data class ServidorPeli(
    val nombre: String,
    val url: String,
) {
    fun aJson(): JSONObject = JSONObject()
        .put("nombre", nombre)
        .put("url", url)
}
