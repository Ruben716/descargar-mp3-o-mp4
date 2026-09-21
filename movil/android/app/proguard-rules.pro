# La red nativa la llama unicamente el nucleo Python, en tiempo de ejecucion y
# por reflexion. Desde Kotlin no la referencia nadie, asi que R8 no le ve
# ningun uso y la borraba del APK: en el telefono salia «No module named 'com'»
# porque la clase, sencillamente, no viajaba dentro.
-keep class com.ruben.descargador_movil.RedNativa { *; }
-keep class com.ruben.descargador_movil.RespuestaNativa { *; }

# El servicio de reproduccion se declara en el manifiesto, asi que R8 conserva
# su nombre, pero no el de la clase de la que hereda ni las que usa por
# reflexion. Sin ellas el telefono deja de reconocer la app como reproductor:
# no hay controles en la barra de estado ni en la pantalla de bloqueo.
-keep class com.ryanheise.audioservice.** { *; }
-keep class androidx.media.** { *; }
-keep class android.support.v4.media.** { *; }
-keep class androidx.media.session.** { *; }
