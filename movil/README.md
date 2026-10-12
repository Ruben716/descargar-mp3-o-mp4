# Tumbao

App Android para descargar y escuchar musica y video sin depender de la red.

La interfaz es Flutter, pero el nucleo que descarga es el mismo Python del
proyecto de escritorio (`descargador/`), embebido en el APK con Chaquopy y
hablando con Dart por un `MethodChannel`. Lo descargado se guarda en
`Music/Tumbao` y `Movies/Tumbao` a traves de MediaStore, asi que el resto del
telefono tambien lo ve.

## Desarrollo

```bash
flutter pub get
flutter test          # pruebas de widget y de la base de datos
flutter analyze
flutter run            # con el telefono conectado o por depuracion wifi
```

El nucleo de Python no se copia a mano: la tarea Gradle `sincronizarNucleo`
lleva `descargador/` a `android/app/src/main/python/` en cada compilacion.

## Clave de Jamendo

Jamendo es la unica fuente que pide una clave, y es de la app, no del usuario:

1. Crea una cuenta de desarrollador en <https://devportal.jamendo.com> y registra
   una aplicacion (uso no comercial). Te da un **Client ID**.
2. En GitHub: *Settings → Secrets and variables → Actions → New repository
   secret*, con el nombre `JAMENDO_CLIENT_ID` y el Client ID como valor. El
   flujo `apk.yml` lo mete en el APK al compilar.
3. Para la consola o un `flutter run` local, pon el Client ID en
   `descargador/clave_jamendo.txt` (git lo ignora) o en la variable de entorno
   `JAMENDO_CLIENT_ID`.

Sin clave todo sigue funcionando; solo la busqueda en Jamendo avisa de que falta.

## Icono

El icono sale del dibujo en `herramientas/icono_origen.jpeg`. Para rehacerlo
tras un cambio de color:

```bash
python herramientas/generar_icono.py   # regenera assets/icono*.png
dart run flutter_launcher_icons         # los reparte por densidades
```
