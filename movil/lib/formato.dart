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
