import 'nucleo.dart';

/// Listas en .m3u, el formato que abren VLC, Poweramp, foobar y casi todos.
///
/// Las listas de la app viven en su propia memoria y ningun otro reproductor
/// las ve. Exportadas asi, la misma lista suena en el coche o en el PC.
class M3u {
  M3u._();

  /// La carpeta donde se guarda la lista; las rutas de dentro son desde aqui.
  static const String carpeta = 'Music/Tumbao/';

  /// Como se llama el archivo: sin los caracteres que Android o Windows
  /// no aceptan en un nombre.
  static String nombreArchivo(String lista) {
    final String limpio = lista.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    return '${limpio.isEmpty ? 'Lista' : limpio}.m3u';
  }

  /// Ruta de una cancion vista desde [carpeta].
  ///
  /// Lo de Music/Tumbao va por su nombre; lo de otra carpeta (la vieja
  /// Music/Descargador) sube un nivel por cada uno que haya que salir.
  static String ruta(Elemento e) {
    final String suya = e.carpeta.isEmpty ? carpeta : (e.carpeta.endsWith('/') ? e.carpeta : '${e.carpeta}/');
    final List<String> desde = carpeta.split('/')..removeWhere((String p) => p.isEmpty);
    final List<String> hasta = suya.split('/')..removeWhere((String p) => p.isEmpty);
    int comunes = 0;
    while (comunes < desde.length && comunes < hasta.length && desde[comunes] == hasta[comunes]) {
      comunes++;
    }
    return <String>[
      for (int i = comunes; i < desde.length; i++) '..',
      ...hasta.skip(comunes),
      e.nombre,
    ].join('/');
  }

  /// El texto de la lista: solo el audio, en su orden, con lo que dura cada
  /// pista y su «Artista - Tema» para que el reproductor lo ensenie bonito.
  static String texto(List<Elemento> pistas) {
    final StringBuffer salida = StringBuffer('#EXTM3U\n');
    for (final Elemento e in pistas.where((Elemento e) => e.audio)) {
      final ({String artista, String tema}) p = e.partes;
      final String titulo = p.artista.isEmpty ? p.tema : '${p.artista} - ${p.tema}';
      salida
        ..write('#EXTINF:${e.duracion.round()},${titulo.replaceAll('\n', ' ')}\n')
        ..write('${ruta(e)}\n');
    }
    return salida.toString();
  }
}
