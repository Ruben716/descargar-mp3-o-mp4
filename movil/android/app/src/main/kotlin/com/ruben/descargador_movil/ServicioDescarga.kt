package com.ruben.descargador_movil

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.chaquo.python.Python
import org.json.JSONObject
import kotlin.concurrent.thread

/**
 * Mantiene el proceso vivo mientras dura una descarga.
 *
 * Sin esto Android congela o mata la app al bloquear la pantalla y la descarga
 * se pierde a medias. El servicio no descarga nada: consulta el avance que
 * publica Python y lo refleja en la notificacion.
 */
class ServicioDescarga : Service() {

    private var activo = false

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (activo) return START_STICKY
        activo = true

        crearCanal()
        startForeground(NOTIFICACION, construirNotificacion("Preparando...", -1))
        vigilar()
        return START_STICKY
    }

    override fun onDestroy() {
        activo = false
        super.onDestroy()
    }

    /** Refleja en la notificacion lo que Python va publicando. */
    private fun vigilar() = thread {
        val gestor = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        while (activo) {
            val texto: String
            var porcentaje = -1
            try {
                val avance = JSONObject(
                    Python.getInstance().getModule("puente").callAttr("progreso").toString(),
                )
                porcentaje = avance.optDouble("porcentaje", -1.0).toInt()
                texto = when (avance.optString("status")) {
                    "downloading" -> "Descargando..."
                    "finished" -> "Uniendo con FFmpeg..."
                    "listo" -> "Completado"
                    "error" -> "Error en la descarga"
                    else -> "Preparando..."
                }
            } catch (error: Throwable) {
                break
            }
            gestor.notify(NOTIFICACION, construirNotificacion(texto, porcentaje))
            Thread.sleep(1000)
        }
    }

    private fun construirNotificacion(texto: String, porcentaje: Int): Notification =
        NotificationCompat.Builder(this, CANAL)
            .setContentTitle("Descargador")
            .setContentText(texto)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setProgress(100, porcentaje.coerceAtLeast(0), porcentaje < 0)
            .build()

    private fun crearCanal() {
        val canal = NotificationChannel(CANAL, "Descargas", NotificationManager.IMPORTANCE_LOW)
        canal.description = "Progreso de las descargas en curso"
        (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
            .createNotificationChannel(canal)
    }

    companion object {
        private const val CANAL = "descargas"
        private const val NOTIFICACION = 1

        fun arrancar(contexto: Context) {
            contexto.startForegroundService(Intent(contexto, ServicioDescarga::class.java))
        }

        fun detener(contexto: Context) {
            contexto.stopService(Intent(contexto, ServicioDescarga::class.java))
        }
    }
}
