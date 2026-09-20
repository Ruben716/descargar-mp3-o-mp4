# La red nativa la llama unicamente el nucleo Python, en tiempo de ejecucion y
# por reflexion. Desde Kotlin no la referencia nadie, asi que R8 no le ve
# ningun uso y la borraba del APK: en el telefono salia «No module named 'com'»
# porque la clase, sencillamente, no viajaba dentro.
-keep class com.ruben.descargador_movil.RedNativa { *; }
-keep class com.ruben.descargador_movil.RespuestaNativa { *; }
