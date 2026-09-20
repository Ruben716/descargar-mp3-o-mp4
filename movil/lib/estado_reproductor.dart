import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'nucleo.dart';

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

  Elemento? _actual;
  Elemento? get actual => _actual;

  bool get sonando => motor.playing;
  bool get hayAlgo => _actual != null;

  Future<void> reproducir(Elemento elemento) async {
    if (_actual?.uri == elemento.uri) {
      await alternar();
      return;
    }
    _actual = elemento;
    notifyListeners();
    try {
      await motor.setUrl(elemento.uri);
      await motor.play();
    } catch (_) {
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
    await motor.seek(destino < Duration.zero
        ? Duration.zero
        : (destino > total ? total : destino));
  }

  Future<void> cerrar() async {
    await motor.stop();
    _actual = null;
    notifyListeners();
  }
}
