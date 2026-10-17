import 'formato.dart';

/// Palabras que marcan otra version de la cancion, no la cancion.
///
/// Arriba de SoundCloud salen muchas veces remixes y ediciones de DJ con el
/// mismo nombre. Si se buscaba el tema original y la «mejor calidad» fuera un
/// remix, la app habria acertado en el sonido y fallado en lo que importa.
const Set<String> marcasDeVersion = <String>{
  'remix', 'rmx', 'cover', 'live', 'vivo', 'karaoke', 'instrumental', 'sped',
  'slowed', 'reverb', 'nightcore', '8d', 'acustico', 'acoustic', 'edit',
  'bootleg', 'mashup', 'extended', 'vip', 'flip', 'rework', 'tribute',
};

List<String> _palabras(String texto) => sinTildes(texto.toLowerCase())
    .split(RegExp(r'[^a-z0-9]+'))
    .where((String p) => p.length >= 2 || RegExp(r'^\d$').hasMatch(p))
    .toList();

/// Lo buscado, separado en cancion y artista cuando se escribio asi.
///
/// Se entiende «artista - cancion» (lo normal en YouTube y Spotify),
/// «cancion - artista» y «cancion by artista». Sin separador no se adivina:
/// las palabras se buscan en el titulo y en el autor a la vez.
class Consulta {
  const Consulta(this.texto, {this.primera = '', this.segunda = ''});

  /// Lo escrito, tal cual.
  final String texto;

  /// Las dos partes, en el orden escrito. Vacias si no habia separador.
  final String primera;
  final String segunda;

  bool get separada => primera.isNotEmpty && segunda.isNotEmpty;

  /// Para enseniarlo: con «a - b» se supone artista y luego cancion.
  ({String artista, String tema}) get comoSeLee => (artista: primera, tema: segunda);
}

final RegExp _guion = RegExp(r'\s+[-–—|]\s+');
final RegExp _by = RegExp(r'\s+by\s+', caseSensitive: false);

Consulta separarConsulta(String texto) {
  final String t = texto.trim();
  final Match? guion = _guion.firstMatch(t);
  if (guion != null) {
    final String a = t.substring(0, guion.start).trim();
    final String b = t.substring(guion.end).trim();
    if (_palabras(a).isNotEmpty && _palabras(b).isNotEmpty) return Consulta(t, primera: a, segunda: b);
  }
  final Match? by = _by.firstMatch(t);
  if (by != null) {
    final String tema = t.substring(0, by.start).trim();
    final String artista = t.substring(by.end).trim();
    if (_palabras(tema).isNotEmpty && _palabras(artista).isNotEmpty) {
      return Consulta(t, primera: artista, segunda: tema);
    }
  }
  return Consulta(t);
}

/// Cuantas de [pedidas] estan en [tiene], perdonando una de cada cuatro si
/// son mas de dos (los titulos cambian «ft.» por «feat.» y cosas asi).
bool _casi(List<String> pedidas, Set<String> tiene) {
  if (pedidas.isEmpty) return true;
  final int estan = pedidas.where(tiene.contains).length;
  final int hacenFalta = pedidas.length <= 2 ? pedidas.length : (pedidas.length * 0.75).ceil();
  return estan >= hacenFalta;
}

/// Si un resultado parece la cancion que se busco, y no otra version de ella.
///
/// Tienen que estar casi todas las palabras buscadas en el titulo o en el
/// autor, y no puede traer una marca de otra version que no se haya pedido.
/// Si se escribio «artista - cancion», la cancion tiene que estar en el titulo
/// y el artista en el titulo o en el autor (en cualquiera de los dos ordenes):
/// asi «Bad Bunny - Titi» no da por buena otra cancion de Bad Bunny.
bool pareceLaMisma(String buscado, {required String titulo, String autor = ''}) {
  final List<String> pedidas = _palabras(buscado);
  if (pedidas.isEmpty) return false;
  final Set<String> enElTitulo = _palabras(titulo).toSet();
  final Set<String> tiene = <String>{...enElTitulo, ..._palabras(autor)};
  final Consulta c = separarConsulta(buscado);
  if (c.separada) {
    bool encaja(String artista, String tema) =>
        _casi(_palabras(tema), enElTitulo) && _casi(_palabras(artista), tiene);
    if (!encaja(c.primera, c.segunda) && !encaja(c.segunda, c.primera)) return false;
  } else if (!_casi(pedidas, tiene)) {
    return false;
  }
  final Set<String> pedidasSet = pedidas.toSet();
  return !marcasDeVersion.any((String m) => enElTitulo.contains(m) && !pedidasSet.contains(m));
}
