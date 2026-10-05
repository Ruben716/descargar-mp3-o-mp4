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

# El traductor del telefono (ML Kit) arranca sus piezas por reflexion: busca
# cada «Registrar» por su nombre y lo crea con su constructor vacio. R8 no ve
# a nadie llamando a esos constructores y los quitaba, asi que en el telefono
# salia «NoSuchMethodException ...Registrar.<init>» y la sinopsis se quedaba
# en ingles. Se conserva ML Kit entero y el plugin que lo une con Flutter.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_translate.** { *; }
-keep class com.google.android.gms.internal.mlkit_common.** { *; }
-keep class * implements com.google.firebase.components.ComponentRegistrar { <init>(); }
-keep class com.google_mlkit_translation.** { *; }
-keep class com.google_mlkit_commons.** { *; }
