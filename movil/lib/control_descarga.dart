import 'dart:async';

import 'package:flutter/foundation.dart';

import 'nucleo.dart';

/// Estado de la descarga, compartido por las pantallas.
///
/// Vive fuera de ellas porque una descarga puede empezar desde la lista de
/// resultados o desde la vista previa, y las dos tienen que ver el mismo
/// avance. Aqui tambien viven los ajustes elegidos, que valen para ambas.
class ControlDescarga extends ChangeNotifier {
  ControlDescarga._();

  static final ControlDescarga instancia = ControlDescarga._();

  Ajustes ajustes = const Ajustes(url: '');

  bool _activa = false;
  bool get activa => _activa;

  double? _porcentaje;
  double? get porcentaje => _porcentaje;

  String _estado = '';
  String get estado => _estado;

  String _mensaje = '';
  String get mensaje => _mensaje;

  bool _fallo = false;
  bool get fallo => _fallo;

  Timer? _reloj;

  int _indice = 0;
  int _total = 0;
  bool _cancelado = false;

  /// "3 de 183" mientras dura un lote; vacio si es una sola pista.
  String get progresoLote => _total > 1 ? '$_indice de $_total' : '';

  bool get enLote => _total > 1;

  bool get cancelando => _cancelado;

  /// Corta el lote. No interrumpe la pista en curso: esa termina y para ahi,
  /// que es mas limpio que dejar un archivo a medias.
  void cancelar() {
    if (!_activa) return;
    _cancelado = true;
    notifyListeners();
  }

  /// Avisa a la biblioteca de que hay algo nuevo que mostrar.
  VoidCallback? alTerminar;

  void cambiarAjustes(Ajustes nuevos) {
    ajustes = nuevos;
    notifyListeners();
  }

  void limpiarMensaje() {
    if (_mensaje.isEmpty) return;
    _mensaje = '';
    _fallo = false;
    notifyListeners();
  }

  /// Vuelve al estado inicial. Mismo motivo que en el reproductor: es un
  /// unico objeto compartido y conviene poder empezar de cero.
  void reiniciar() {
    _reloj?.cancel();
    _activa = false;
    _porcentaje = null;
    _estado = '';
    _mensaje = '';
    _fallo = false;
    _indice = 0;
    _total = 0;
    _cancelado = false;
    ajustes = const Ajustes(url: '');
    notifyListeners();
  }

  Future<void> iniciar(String url) => iniciarVarios(<String>[url]);

  /// Descarga una lista entera, una detras de otra.
  ///
  /// Un fallo suelto no detiene el resto: al final se dice cuantas salieron.
  Future<void> iniciarVarios(List<String> urls) async {
    if (_activa || urls.isEmpty) return;
    _activa = true;
    _cancelado = false;
    _indice = 0;
    _total = urls.length;
    _porcentaje = null;
    _estado = 'Preparando...';
    _mensaje = '';
    _fallo = false;
    notifyListeners();
    _vigilar();

    int correctas = 0;
    int fallidas = 0;
    String ultimoError = '';

    try {
      for (int i = 0; i < urls.length; i++) {
        if (_cancelado) break;
        _indice = i + 1;
        notifyListeners();
        try {
          // Solo avisa la ultima: con una lista larga saldrian cientos.
          await Nucleo.descargar(
            ajustes.copiar(url: urls[i]),
            avisar: i == urls.length - 1,
          );
          correctas++;
          alTerminar?.call();
        } on ErrorNucleo catch (error) {
          fallidas++;
          ultimoError = error.registro.isEmpty
              ? error.mensaje
              : '${error.mensaje}\n\n--- registro del motor ---\n'
                  '${error.registro.join('\n')}';
        } catch (error) {
          fallidas++;
          ultimoError = '$error';
        }
      }
      _resumen(correctas, fallidas, ultimoError);
    } finally {
      _reloj?.cancel();
      _activa = false;
      _cancelado = false;
      _indice = 0;
      _total = 0;
      _estado = '';
      _porcentaje = null;
      notifyListeners();
    }
  }

  void _resumen(int correctas, int fallidas, String ultimoError) {
    if (_total == 1) {
      _fallo = fallidas > 0;
      _mensaje = _fallo ? ultimoError : 'Guardado en tu biblioteca.';
      return;
    }
    final String corte = _cancelado ? ' (cancelado)' : '';
    _fallo = correctas == 0;
    _mensaje = fallidas == 0
        ? '$correctas guardadas en tu biblioteca$corte.'
        : '$correctas guardadas, $fallidas con error$corte.'
            '\n\nUltimo error: $ultimoError';
  }

  /// Python publica el avance y aqui se consulta mientras dure la descarga.
  void _vigilar() {
    _reloj?.cancel();
    _reloj = Timer.periodic(const Duration(milliseconds: 500), (Timer reloj) async {
      if (!_activa) {
        reloj.cancel();
        return;
      }
      try {
        final Avance avance = await Nucleo.progreso();
        _porcentaje = avance.porcentaje >= 0 ? avance.porcentaje / 100 : null;
        _estado = switch (avance.estado) {
          'downloading' => _velocidad(avance.velocidad),
          'finished' => 'Uniendo con FFmpeg...',
          _ => 'Preparando...',
        };
        notifyListeners();
      } catch (_) {
        // Una consulta perdida no debe romper la descarga en curso.
      }
    });
  }

  static String _velocidad(int octetos) {
    if (octetos <= 0) return 'Descargando...';
    const List<String> unidades = <String>['B', 'KB', 'MB', 'GB'];
    double valor = octetos.toDouble();
    int i = 0;
    while (valor >= 1024 && i < unidades.length - 1) {
      valor /= 1024;
      i++;
    }
    return '${valor.toStringAsFixed(1)} ${unidades[i]}/s';
  }
}
