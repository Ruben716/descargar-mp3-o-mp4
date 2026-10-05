package com.ruben.descargador_movil

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.view.View
import android.widget.RemoteViews
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

/** Lo que ensenia el widget. Sin titulo, la app no tiene nada puesto. */
data class EstadoWidget(
    val titulo: String? = null,
    val artista: String = "",
    val sonando: Boolean = false,
    val caratula: String? = null,
)

/**
 * Widget de la pantalla de inicio: caratula, titulo y los tres botones.
 *
 * No se refresca solo: Flutter lo pinta cada vez que cambia lo que suena. Los
 * botones van a [ReceptorWidget], que se lo pasa a Flutter por el canal.
 *
 * Con la app muerta no hay a quien pasarselo, asi que en ese estado los
 * botones abren la app en vez de mandar ordenes que nadie oiria. Arrancar el
 * servicio de audio desde aqui sin Flutter detras acaba en el cierre forzoso
 * de Android por no ponerse en primer plano a tiempo.
 */
class WidgetTumbao : AppWidgetProvider() {

    override fun onUpdate(contexto: Context, gestor: AppWidgetManager, ids: IntArray) {
        // Lo piden el sistema al ponerlo o al reiniciar: si la app no esta viva
        // se pinta como cerrada.
        pintar(contexto, if (canalVivo != null) ultimo else EstadoWidget())
    }

    companion object {
        /** El canal hacia Flutter mientras su motor siga vivo. */
        @Volatile
        var canalVivo: MethodChannel? = null

        @Volatile
        private var ultimo = EstadoWidget()

        /** Lado de la caratula en pixeles: de sobra para 48 dp y ligera. */
        private const val LADO = 192

        fun actualizar(contexto: Context, estado: EstadoWidget) {
            ultimo = estado
            pintar(contexto, estado)
        }

        /** El motor de Flutter se va: los botones pasan a abrir la app. */
        fun alMorirFlutter(contexto: Context) {
            canalVivo = null
            pintar(contexto, EstadoWidget())
        }

        private fun pintar(contexto: Context, estado: EstadoWidget) {
            val app = contexto.applicationContext
            val gestor = AppWidgetManager.getInstance(app)
            val componente = ComponentName(app, WidgetTumbao::class.java)
            // Sin widgets puestos no hay nada que pintar, ni caratula que leer.
            if (gestor.getAppWidgetIds(componente).isEmpty()) return
            // La caratula se lee de disco: fuera del hilo principal.
            thread {
                try {
                    gestor.updateAppWidget(componente, vistas(app, estado))
                } catch (error: Throwable) {
                    // Un widget que no se pudo pintar no puede tumbar la app.
                }
            }
        }

        private fun vistas(contexto: Context, estado: EstadoWidget): RemoteViews {
            val vistas = RemoteViews(contexto.packageName, R.layout.widget_tumbao)
            val vivo = canalVivo != null && estado.titulo != null

            vistas.setTextViewText(
                R.id.widget_titulo,
                estado.titulo ?: contexto.getString(R.string.widget_sin_nada),
            )
            vistas.setTextViewText(
                R.id.widget_artista,
                if (estado.titulo == null) contexto.getString(R.string.widget_toca_para_abrir)
                else estado.artista,
            )
            val imagen = estado.caratula?.let { caratulaRedonda(it) }
            if (imagen != null) vistas.setImageViewBitmap(R.id.widget_portada, imagen)
            else vistas.setImageViewResource(R.id.widget_portada, R.mipmap.ic_launcher)

            vistas.setImageViewResource(
                R.id.widget_alternar,
                if (vivo && estado.sonando) R.drawable.widget_pausa else R.drawable.widget_reproducir,
            )
            // Sin nada puesto, anterior y siguiente no tienen sentido.
            val laterales = if (vivo) View.VISIBLE else View.GONE
            vistas.setViewVisibility(R.id.widget_anterior, laterales)
            vistas.setViewVisibility(R.id.widget_siguiente, laterales)

            val abrir = abrirApp(contexto, null, 0)
            vistas.setOnClickPendingIntent(R.id.widget_portada, abrir)
            vistas.setOnClickPendingIntent(R.id.widget_textos, abrir)
            if (vivo) {
                vistas.setOnClickPendingIntent(R.id.widget_anterior, orden(contexto, "anterior", 1))
                vistas.setOnClickPendingIntent(R.id.widget_alternar, orden(contexto, "alternar", 2))
                vistas.setOnClickPendingIntent(R.id.widget_siguiente, orden(contexto, "siguiente", 3))
            } else {
                // Abre la app y sigue por donde se quedo.
                vistas.setOnClickPendingIntent(R.id.widget_alternar, abrirApp(contexto, "continuar", 4))
            }
            return vistas
        }

        /** Abre la app como el icono: si ya estaba abierta, la trae delante. */
        fun abrirApp(contexto: Context, atajo: String?, codigo: Int): PendingIntent {
            val intento = Intent(contexto, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_RESET_TASK_IF_NEEDED)
                if (atajo != null) putExtra("atajo", atajo)
            }
            return PendingIntent.getActivity(
                contexto,
                codigo,
                intento,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        private fun orden(contexto: Context, accion: String, codigo: Int): PendingIntent =
            PendingIntent.getBroadcast(
                contexto,
                codigo,
                Intent(contexto, ReceptorWidget::class.java).setAction(accion),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )

        /** La caratula reducida y con las esquinas redondeadas. */
        private fun caratulaRedonda(ruta: String): Bitmap? {
            val limites = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeFile(ruta, limites)
            if (limites.outWidth <= 0 || limites.outHeight <= 0) return null
            var muestra = 1
            while (minOf(limites.outWidth, limites.outHeight) / (muestra * 2) >= LADO) muestra *= 2
            val original = BitmapFactory.decodeFile(
                ruta,
                BitmapFactory.Options().apply { inSampleSize = muestra },
            ) ?: return null

            // Recorte cuadrado del centro, como la caratula en la app.
            val lado = minOf(original.width, original.height)
            val cuadrada = Bitmap.createBitmap(
                original,
                (original.width - lado) / 2,
                (original.height - lado) / 2,
                lado,
                lado,
            )
            val escalada = Bitmap.createScaledBitmap(cuadrada, LADO, LADO, true)
            val salida = Bitmap.createBitmap(LADO, LADO, Bitmap.Config.ARGB_8888)
            val lienzo = Canvas(salida)
            val pincel = Paint(Paint.ANTI_ALIAS_FLAG)
            val radio = LADO * 0.18f
            lienzo.drawRoundRect(RectF(0f, 0f, LADO.toFloat(), LADO.toFloat()), radio, radio, pincel)
            pincel.xfermode = PorterDuffXfermode(PorterDuff.Mode.SRC_IN)
            lienzo.drawBitmap(escalada, 0f, 0f, pincel)
            return salida
        }
    }
}

/** Los botones del widget: se le pasan a Flutter, que es quien lleva la musica. */
class ReceptorWidget : BroadcastReceiver() {
    override fun onReceive(contexto: Context, intento: Intent) {
        val accion = intento.action ?: return
        val canal = WidgetTumbao.canalVivo
        if (canal != null) {
            canal.invokeMethod("widget", accion)
            return
        }
        // La app murio desde el ultimo pintado: se repinta como cerrada para
        // que el siguiente toque ya abra la app.
        WidgetTumbao.alMorirFlutter(contexto)
        try {
            WidgetTumbao.abrirApp(contexto, "continuar", 5).send()
        } catch (error: Exception) {
            // Android puede negar abrir algo desde aqui; el widget ya quedo
            // listo para abrirla con el siguiente toque.
        }
    }
}
