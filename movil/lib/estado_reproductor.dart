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
    // Al saltar de pista dentro de la cola hay que actualizar lo que se ve.
    motor.currentIndexStream.listen((int? indice) {
      if (indice == null || indice >= _cola.length) return;
      final Elemento actual = _cola[indice];
      _actual = Pista(titulo: actual.nombre, fuente: actual.uri, elemento: actual);
      notifyListeners();
    });
    // Un fallo mientras suena no llega por el await de setUrl: viaja por este
    // flujo. Sin escucharlo, el reproductor se quedaba mudo sin explicacion.
    motor.playbackEventStream.listen(
      (_) {},
      onError: (Object fallo, StackTrace _) {
        _preparando = false;
        // Al cambiar de pista o cerrar, el motor suele soltar un error
        // pasajero ("Connection aborted") aunque todo siga sonando. Solo
        // interesa cuando de verdad nos quedamos sin nada reproduciendo.
        if (motor.playing) {
          notifyListeners();
          return;
        }
        _error = '$fallo';
        notifyListeners();
      },
    );
  }

  static final EstadoReproductor instancia = EstadoReproductor._();

  final AudioPlayer motor = AudioPlayer();

  /// Lo que hay en cola. Sin ella no habria siguiente ni anterior.
  List<Elemento> _cola = <Elemento>[];
  List<Elemento> get cola => List<Elemento>.unmodifiable(_cola);

  bool get haySiguiente => motor.hasNext;
  bool get hayAnterior => motor.hasPrevious;

  LoopMode get repeticion => motor.loopMode;

  /// Reproduce desde una pista y deja el resto en cola detras.
  Future<void> reproducirLista(List<Elemento> elementos, int desde) async {
    if (elementos.isEmpty) return;
    _cola = List<Elemento>.from(elementos);
    _actual = Pista(
      titulo: elementos[desde].nombre,
      fuente: elementos[desde].uri,
      elemento: elementos[desde],
    );
    _error = null;
    notifyListeners();
    try {
      await motor.setAudioSources(await _fuentes(elementos), initialIndex: desde);
      await motor.play();
    } catch (error) {
      _error = '$error';
      _actual = null;
      notifyListeners();
    }
  }

  /// Prepara la cola pidiendo las caratulas de ocho en ocho.
  ///
  /// Una a una tardaria demasiado con una lista larga, y todas a la vez
  /// abriria un hilo por pista en Kotlin.
  Future<List<AudioSource>> _fuentes(List<Elemento> elementos) async {
    final List<AudioSource> fuentes = <AudioSource>[];
    for (int i = 0; i < elementos.length; i += 8) {
      final List<Elemento> trozo = elementos.skip(i).take(8).toList();
      final List<Uri?> artes = await Future.wait(
        trozo.map((Elemento e) => Nucleo.caratulaArchivo(e.uri)),
      );
      for (int j = 0; j < trozo.length; j++) {
        fuentes.add(_fuente(trozo[j], artes[j]));
      }
    }
    return fuentes;
  }

  AudioSource _fuente(Elemento elemento, Uri? arte) => AudioSource.uri(
    Uri.parse(elemento.uri),
    tag: MediaItem(
      id: elemento.uri,
      title: nombreLimpio(elemento.nombre),
      album: 'Tumbao',
      artUri: arte,
    ),
  );

  Future<void> siguiente() async {
    if (motor.hasNext) await motor.seekToNext();
  }

  /// Como en cualquier reproductor: si ya sono un rato, vuelve al principio.
  Future<void> anterior() async {
    if (motor.position > const Duration(seconds: 3) || !motor.hasPrevious) {
      await motor.seek(Duration.zero);
      return;
    }
    await motor.seekToPrevious();
  }

  /// Cicla entre no repetir, repetir la cola y repetir una sola.
  Future<void> alternarRepeticion() async {
    final LoopMode siguiente = switch (motor.loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    await motor.setLoopMode(siguiente);
    notifyListeners();
  }

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
            album: 'Tumbao',
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
    _cola = <Elemento>[];
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
