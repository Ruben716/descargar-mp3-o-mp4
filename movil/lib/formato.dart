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
