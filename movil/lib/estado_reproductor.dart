import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'nucleo.dart';

/// Lo que esta sonando: un archivo de la biblioteca o una vista previa.
class Pista {
  const Pista({
    required this.titulo,
    required this.fuente,
    this.cabeceras = const <String, String>{},
    this.elemento,
    this.resultado,
  });

  final String titulo;
  final String fuente;
  final Map<String, String> cabeceras;

  /// Nulo cuando es una vista previa: eso todavia no existe en el telefono.
  final Elemento? elemento;

  /// Solo en una vista previa: guarda miniatura y autor para poder pintarla.
  final Resultado? resultado;

  bool get esPrevia => elemento == null;
}

/// Reproduccion de audio compartida por toda la app.
///
/// Vive fuera de las pantallas para que la musica no se corte al cambiar de
/// pestania y para que el mini reproductor sepa siempre que esta sonando.
class EstadoReproductor extends ChangeNotifier {
  EstadoReproductor._() {
    motor.playerStateStream.listen((_) => notifyListeners());
  }

  static final EstadoReproductor instancia = EstadoReproductor._();

  final AudioPlayer motor = AudioPlayer();

  Pista? _actual;
  Pista? get actual => _actual;

  bool _preparando = false;
  bool get preparando => _preparando;

  String? _error;
  String? get error => _error;

  /// Devuelve el error una sola vez, para que la pantalla lo muestre y no se
  /// repita en cada reconstruccion. Un fallo silencioso es peor que ninguno.
  String? consumirError() {
    final String? mensaje = _error;
    _error = null;
    return mensaje;
  }

  bool get sonando => motor.playing;

  bool esActual(String uri) => _actual?.elemento?.uri == uri;

  Future<void> reproducirElemento(Elemento elemento) async {
    if (esActual(elemento.uri)) {
      await alternar();
      return;
    }
    await _poner(Pista(
      titulo: elemento.nombre,
      fuente: elemento.uri,
      elemento: elemento,
    ));
  }

  /// Escucha un resultado de busqueda sin descargarlo.
  ///
  /// La URL del stream la resuelve el nucleo con yt-dlp y caduca en un rato,
  /// asi que se pide justo antes de sonar y no se guarda.
  Future<void> previsualizar(Resultado resultado) async {
    if (_actual?.fuente == resultado.url && _actual!.esPrevia) {
      await alternar();
      return;
    }
    _preparando = true;
    _error = null;
    _actual = Pista(titulo: resultado.titulo, fuente: resultado.url, resultado: resultado);
    notifyListeners();
    try {
      final Previsualizacion pista = await Nucleo.previsualizar(resultado.url);
      await _poner(
        Pista(
          titulo: resultado.titulo,
          fuente: resultado.url,
          cabeceras: pista.cabeceras,
          resultado: resultado,
        ),
        directa: pista.url,
      );
    } on ErrorNucleo catch (error) {
      final String detalle = error.registro.isEmpty
          ? ''
          : '\n\n--- registro del motor ---\n${error.registro.join('\n')}';
      _error = '${error.mensaje}$detalle';
      _actual = null;
    } catch (error) {
      _error = '$error';
      _actual = null;
    } finally {
      _preparando = false;
      notifyListeners();
    }
  }

  Future<void> _poner(Pista pista, {String? directa}) async {
    _actual = pista;
    _error = null;
    notifyListeners();
    try {
      // Con cabeceras, just_audio sirve el audio por un proxy local; sin
      // ellas va directo. Para un archivo del telefono ese rodeo sobra.
      await motor.setUrl(
        directa ?? pista.fuente,
        headers: pista.cabeceras.isEmpty ? null : pista.cabeceras,
      );
      await motor.play();
    } catch (error) {
      _error = '$error';
      _actual = null;
      notifyListeners();
    }
  }

  Future<void> alternar() async {
    if (motor.playing) {
      await motor.pause();
    } else {
      await motor.play();
    }
  }

  Future<void> saltar(Duration desplazamiento) async {
    final Duration destino = motor.position + desplazamiento;
    final Duration total = motor.duration ?? Duration.zero;
    await motor.seek(
      destino < Duration.zero ? Duration.zero : (destino > total ? total : destino),
    );
  }

  Future<void> cerrar() async {
    await motor.stop();
    _actual = null;
    _error = null;
    notifyListeners();
  }

  /// Vuelve al estado inicial sin tocar el motor de audio.
  ///
  /// Al ser un unico objeto para toda la app, lo que quede de una pantalla se
  /// arrastra a la siguiente; esto permite empezar de cero, y es lo que usan
  /// las pruebas para no depender del orden en que se ejecutan.
  void reiniciar() {
    _actual = null;
    _error = null;
    _preparando = false;
    notifyListeners();
  }

  /// Si se borra lo que suena, dejar de sonar.
  Future<void> olvidarSiEs(String uri) async {
    if (esActual(uri)) await cerrar();
  }
}
