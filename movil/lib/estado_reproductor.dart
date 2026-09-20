import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'formato.dart';
import 'nucleo.dart';

/// Lo que esta sonando: un archivo de la biblioteca o una vista previa.
class Pista {
  const Pista({
    required this.titulo,
    required this.fuente,
    this.elemento,
  });

  final String titulo;
  final String fuente;
  final Elemento? elemento;
}

/// Reproduccion de audio compartida por toda la app.
///
/// Vive fuera de las pantallas para que la musica no se corte al cambiar de
/// pestania y para que el mini reproductor sepa siempre que esta sonando.
class EstadoReproductor extends ChangeNotifier {
  EstadoReproductor._() {
    motor.playerStateStream.listen((_) => notifyListeners());
    // Un fallo mientras suena no llega por el await de setUrl: viaja por este
    // flujo. Sin escucharlo, el reproductor se quedaba mudo sin explicacion.
    motor.playbackEventStream.listen(
      (_) {},
      onError: (Object fallo, StackTrace _) {
        _error = 'Reproduccion: $fallo';
        _preparando = false;
        notifyListeners();
      },
    );
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

  Future<void> _poner(Pista pista) async {
    _actual = pista;
    _error = null;
    notifyListeners();
    try {
      // La etiqueta MediaItem es lo que pinta el sistema en la notificacion y
      // en la pantalla de bloqueo; sin ella saldria vacia.
      await motor.setAudioSource(
        AudioSource.uri(
          Uri.parse(pista.fuente),
          tag: MediaItem(
            id: pista.fuente,
            title: nombreLimpio(pista.titulo),
            album: 'Descargador',
            artUri: await Nucleo.caratulaArchivo(pista.fuente),
          ),
        ),
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
    try {
      await motor.stop();
    } catch (_) {
      // Parar nunca debe romper a quien llama: si el motor esta en mal estado
      // igualmente queremos olvidar la pista y seguir.
    }
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
