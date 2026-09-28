/// Pequenas ayudas de presentacion compartidas por las pantallas.
library;

String formatoTamano(num octetos) {
  if (octetos <= 0) return '--';
  const List<String> unidades = <String>['B', 'KB', 'MB', 'GB'];
  double valor = octetos.toDouble();
  int i = 0;
  while (valor >= 1024 && i < unidades.length - 1) {
    valor /= 1024;
    i++;
  }
  return '${valor.toStringAsFixed(1)} ${unidades[i]}';
}

String formatoTiempo(num segundos) {
  if (segundos <= 0) return '0:00';
  final int total = segundos.round();
  final int horas = total ~/ 3600;
  final int minutos = (total % 3600) ~/ 60;
  final int segs = total % 60;
  final String base = '$minutos:${segs.toString().padLeft(2, '0')}';
  return horas > 0 ? '$horas:${minutos.toString().padLeft(2, '0')}:${segs.toString().padLeft(2, '0')}' : base;
}

/// Quita la extension y el identificador del nombre de archivo.
///
/// "Cancion [abc123].mp3" queda en "Cancion": es lo que debe verse en la
/// notificacion y en el reproductor.
String nombreLimpio(String nombre) {
  final String sinExtension = nombre.replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,4}$'), '');
  return sinExtension.replaceAll(RegExp(r'\s*\[[^\]]+\]\s*$'), '').trim();
}

const Map<String, String> _equivalencias = <String, String>{
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n', 'ç': 'c',
};

/// Deja un texto listo para comparar: sin mayusculas y sin tildes.
///
/// Buscando "corazon" tiene que salir "Corazón": nadie escribe las tildes en
/// un buscador, y sin esto media biblioteca en castellano seria inencontrable.
String sinTildes(String texto) {
  final StringBuffer salida = StringBuffer();
  for (final String letra in texto.toLowerCase().split('')) {
    salida.write(_equivalencias[letra] ?? letra);
  }
  return salida.toString();
}

/// Si [texto] contiene [consulta], ignorando mayusculas y tildes.
bool coincide(String texto, String consulta) =>
    sinTildes(texto).contains(sinTildes(consulta.trim()));

/// Separa «Artista - Tema» en sus dos mitades.
///
/// Se corta por el primer guion y no por el ultimo: hay temas que llevan
/// guion dentro, pero el artista casi nunca. Sin guion no hay artista que
/// sacar y el nombre entero es el tema.
({String artista, String tema}) partirNombre(String texto) {
  final Match? corte = RegExp(r'\s+[-–—]\s+').firstMatch(texto);
  if (corte == null) return (artista: '', tema: texto.trim());
  return (
    artista: texto.substring(0, corte.start).trim(),
    tema: texto.substring(corte.end).trim(),
  );
}

/// Coletillas de YouTube que no son parte del titulo: «(Official Video)»,
/// «[4K]», «(Letra)»... Solo dentro de parentesis o corchetes: «Live» suelto
/// puede ser parte del tema, pero «(Live)» al final nunca lo es. Es el mismo
/// criterio que usa el nucleo al etiquetar.
final RegExp _ruido = RegExp(
  r'\s*[\(\[][^)\]]*\b(?:official|oficial|video|videoclip|lyrics?|letra|'
  r'audio|hd|hq|4k|8k|mv|remaster(?:ed)?|visualizer|visualiser|'
  r'en\s+vivo|live)\b[^)\]]*[\)\]]',
  caseSensitive: false,
);

String _sinRuido(String titulo) {
  final String limpio = titulo.replaceAll(_ruido, '').replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  // Si el titulo era solo coletilla, mejor dejarlo como estaba que en blanco.
  return limpio.isEmpty ? titulo.trim() : limpio;
}

/// El nombre de un canal y no de un artista: «Queen - Topic», «ShakiraVEVO».
String _sinCanal(String artista) => artista
    .replaceFirst(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
    .replaceFirst(RegExp(r'VEVO$'), '')
    .trim();

/// Si una etiqueta se escribio con la codificacion equivocada.
///
/// Pasa con alguna descarga antigua: «Orión» quedo como «Ori髇». El nombre
/// del archivo si esta bien, asi que si la etiqueta trae letras chinas que el
/// archivo no tiene, y el archivo lleva tildes, la etiqueta esta rota.
bool _malCodificada(String etiqueta, String archivo) {
  final RegExp chino = RegExp(r'[一-鿿]');
  final bool tildes = RegExp(r'[áéíóúñüÁÉÍÓÚÑÜ]').hasMatch(archivo);
  return tildes &&
      chino.allMatches(etiqueta).any((Match m) => !archivo.contains(m.group(0)!));
}

/// Artista y tema para ensenar, de las etiquetas cuando son de fiar.
///
/// El nombre del archivo es el titulo de YouTube tal cual, con su codigo
/// entre corchetes. Las etiquetas suelen estar mejor, pero no siempre: en las
/// descargas antiguas el titulo aun lleva «Artista - Tema» y el artista es el
/// nombre del canal («TheStruckFernVEVO» en vez de Piso 21). Por eso:
///
/// - Si el titulo de la etiqueta lleva «Artista - Tema», se parte y el
///   artista de la etiqueta se ignora, que es el canal.
/// - Si no, se usan titulo y artista de la etiqueta.
/// - Si la etiqueta falta o esta mal codificada, se parte el nombre del archivo.
///
/// Y siempre se quita el ruido tipo «(Official Video)».
({String artista, String tema}) nombreVisible(
  String archivo, {
  String titulo = '',
  String artista = '',
}) {
  final String deArchivo = nombreLimpio(archivo);
  String t = titulo.trim();
  String a = artista.trim();
  if (a == '<unknown>') a = '';
  if (t.isEmpty || _malCodificada('$t $a', deArchivo)) {
    final ({String artista, String tema}) partes = partirNombre(deArchivo);
    return (artista: partes.artista, tema: _sinRuido(partes.tema));
  }
  if (RegExp(r'\s+[-–—]\s+').hasMatch(t)) {
    final ({String artista, String tema}) partes = partirNombre(t);
    return (artista: partes.artista, tema: _sinRuido(partes.tema));
  }
  // «AIRBAG - Cicatrices»: el artista con el disco pegado. Vale lo de delante.
  a = partirNombre(a).artista.isNotEmpty ? partirNombre(a).artista : a;
  return (artista: _sinCanal(a), tema: _sinRuido(t));
}
