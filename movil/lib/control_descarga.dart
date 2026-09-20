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
    ajustes = const Ajustes(url: '');
    notifyListeners();
  }

  Future<void> iniciar(String url) async {
    if (_activa) return;
    _activa = true;
    _porcentaje = null;
    _estado = 'Preparando...';
    _mensaje = '';
    _fallo = false;
    notifyListeners();
    _vigilar();

    try {
      await Nucleo.descargar(ajustes.copiar(url: url));
      _mensaje = 'Guardado en tu biblioteca.';
      _fallo = false;
      alTerminar?.call();
    } on ErrorNucleo catch (error) {
      final String detalle = error.registro.isEmpty
          ? ''
          : '\n\n--- registro del motor ---\n${error.registro.join('\n')}';
      _mensaje = '${error.mensaje}$detalle';
      _fallo = true;
    } catch (error) {
      _mensaje = '$error';
      _fallo = true;
    } finally {
      _reloj?.cancel();
      _activa = false;
      _estado = '';
      _porcentaje = null;
      notifyListeners();
    }
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
