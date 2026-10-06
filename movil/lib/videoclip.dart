import 'canales_oficiales.dart';
import 'nucleo.dart';

/// El videoclip de una cancion de la biblioteca, para verlo sin bajarlo.
class Videoclip {
  Videoclip._();

  /// Lo que no es el videoclip aunque salga al buscar.
  static final RegExp _no = RegExp(
    r'lyric|letra|\baudio\b|cover|karaoke|\blive\b|en vivo|concierto|reacci|reaction|remix|slowed|'
    r'sped up|\b8d\b|nightcore|tutorial|instrumental|visualizer|visualiser',
    caseSensitive: false,
  );

  /// Lo que suele llevar el titulo del videoclip.
  static final RegExp _si = RegExp(r'official|oficial|music video|video ?clip', caseSensitive: false);

  /// El mejor candidato de una busqueda, o null si ninguno parece el videoclip.
  ///
  /// Tiene que ser de esa cancion y durar mas o menos lo mismo: el videoclip
  /// puede llevar una intro o un final, pero no media hora.
  static Resultado? elegir(List<Resultado> resultados, Elemento e) {
    final ({String artista, String tema}) partes = e.partes;
    final String tema = CanalesOficiales.normalizar(partes.tema);
    final List<Resultado> validos = resultados.where((Resultado r) {
      if (_no.hasMatch(r.titulo)) return false;
      if (tema.length >= 2 && !CanalesOficiales.normalizar(r.titulo).contains(tema)) return false;
      if (e.duracion > 0 && r.duracion > 0) {
        if (r.duracion < e.duracion - 20 || r.duracion > e.duracion + 150) return false;
      }
      return true;
    }).toList();
    for (final Resultado r in validos) {
      if (_si.hasMatch(r.titulo)) return r;
    }
    return validos.isEmpty ? null : validos.first;
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
