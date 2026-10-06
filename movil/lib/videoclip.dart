import 'canales_oficiales.dart';
import 'nucleo.dart';

/// El videoclip de una cancion de la biblioteca, para verlo sin bajarlo.
class Videoclip {
  Videoclip._();

  /// Lo que no es el videoclip aunque salga al buscar.
  static final RegExp _no = RegExp(
    r'lyric|letra|\baudio\b|cover|karaoke|\blive\b|en vivo|\bvivo\b|concierto|reacci|reaction|remix|'
    r'slowed|sped up|\b8d\b|nightcore|tutorial|instrumental|visualizer|visualiser|tomorrowland|'
    r'festival|\bumf\b|ultra music|@|behind the scenes|detras de camaras|making of|\bshow\b|'
    r'sub\.? ?espa|subtitulad|acustico|acoustic|full audio|original mix|radio edit|extended|teaser|trailer',
    caseSensitive: false,
  );

  /// Lo que suele llevar el titulo del videoclip.
  static final RegExp _si = RegExp(r'official|oficial|music video|video ?clip', caseSensitive: false);

  /// Si el canal es el del propio artista (o su VEVO).
  static bool delArtista(String canal, String artista) {
    final String a = CanalesOficiales.normalizar(artista);
    final String c = CanalesOficiales.normalizar(canal)
        .replaceAll('vevo', '')
        .replaceAll(RegExp(r'\b(official|oficial|music|musica|tv|channel|canal)\b'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (a.isEmpty || c.length < 3) return false;
    return a.contains(c) || c.contains(a);
  }

  /// El videoclip de una busqueda, o null si no hay uno fiable.
  ///
  /// Tiene que ser de esa cancion, durar mas o menos lo mismo y, sobre todo,
  /// parecer oficial: decirlo en el titulo o estar en el canal del artista.
  /// Lo subido por cualquiera (directos de festival, letras, fans) no cuenta:
  /// mejor decir que no hay que ensenar otra cosa.
  static Resultado? elegir(List<Resultado> resultados, Elemento e) {
    final ({String artista, String tema}) partes = e.partes;
    final String tema = CanalesOficiales.normalizar(partes.tema);
    Resultado? mejor;
    int mejorPuntos = 0;
    double mejorDistancia = double.infinity;
    for (final Resultado r in resultados) {
      if (_no.hasMatch(r.titulo)) continue;
      if (tema.length >= 2 && !CanalesOficiales.normalizar(r.titulo).contains(tema)) continue;
      if (e.duracion > 0 && r.duracion > 0) {
        if (r.duracion < e.duracion - 20 || r.duracion > e.duracion + 150) continue;
      }
      int puntos = 0;
      if (_si.hasMatch(r.titulo)) puntos += 5;
      if (delArtista(r.autor, partes.artista)) puntos += 4;
      if (puntos < 4) continue;
      final double distancia = e.duracion > 0 && r.duracion > 0 ? (r.duracion - e.duracion).abs() : 0;
      if (puntos > mejorPuntos || (puntos == mejorPuntos && distancia < mejorDistancia)) {
        mejor = r;
        mejorPuntos = puntos;
        mejorDistancia = distancia;
      }
    }
    return mejor;
  }

  static Future<Resultado?> buscar(Elemento e) async {
    final ({String artista, String tema}) partes = e.partes;
    final List<Resultado> hallados = await Nucleo.buscar(
      '${partes.artista} ${partes.tema} video oficial'.trim(),
      limite: 8,
    );
    return elegir(hallados, e);
  }
}
