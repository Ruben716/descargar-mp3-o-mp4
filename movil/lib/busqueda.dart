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

/// Si un resultado parece la cancion que se busco, y no otra version de ella.
///
/// Tienen que estar casi todas las palabras buscadas en el titulo o en el
/// autor, y no puede traer una marca de otra version que no se haya pedido.
bool pareceLaMisma(String buscado, {required String titulo, String autor = ''}) {
  final List<String> pedidas = _palabras(buscado);
  if (pedidas.isEmpty) return false;
  final Set<String> tiene = <String>{..._palabras(titulo), ..._palabras(autor)};
  final int estan = pedidas.where(tiene.contains).length;
  // Con dos palabras o menos tienen que estar todas; con mas se perdona una
  // de cada cuatro, que los titulos cambian «ft.» por «feat.» y cosas asi.
  final int hacenFalta = pedidas.length <= 2 ? pedidas.length : (pedidas.length * 0.75).ceil();
  if (estan < hacenFalta) return false;
  final Set<String> enElTitulo = _palabras(titulo).toSet();
  final Set<String> pedidasSet = pedidas.toSet();
  return !marcasDeVersion.any((String m) => enElTitulo.contains(m) && !pedidasSet.contains(m));
}
