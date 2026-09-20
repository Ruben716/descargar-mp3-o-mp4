package com.ruben.descargador_movil

import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

/**
 * Puente Flutter -> Kotlin -> Python.
 *
 * Chaquopy arranca CPython dentro del proceso de la app y el canal deja que
 * Dart invoque el mismo nucleo que usa la version de consola.
 */
class MainActivity : FlutterActivity() {

    private val canal = "com.ruben.descargador/nucleo"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, canal)
            .setMethodCallHandler { llamada, respuesta ->
                when (llamada.method) {
                    "diagnostico" -> enHilo(respuesta) { puente ->
                        puente.callAttr("diagnostico").toString()
                    }
                    "informacion" -> {
                        val url = llamada.argument<String>("url").orEmpty()
                        enHilo(respuesta) { puente ->
                            puente.callAttr("informacion", url).toString()
                        }
                    }
                    else -> respuesta.notImplemented()
                }
            }
    }

    /**
     * Python aqui hace red y disco, asi que nunca puede correr en el hilo
     * principal: Android lanzaria NetworkOnMainThreadException.
     */
    private fun enHilo(
        respuesta: MethodChannel.Result,
        trabajo: (com.chaquo.python.PyObject) -> String,
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
}
