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
