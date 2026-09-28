import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalogo.dart';
import 'ecualizador.dart';
import 'formato.dart';
import 'nucleo.dart';
import 'orden_aleatorio.dart';

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
    motor.positionStream.listen((Duration instante) {
      _anotarSiYaCuenta(instante);
      _quizasGuardarSesion();
    });
    // Al saltar de pista dentro de la cola hay que actualizar lo que se ve.
    motor.currentIndexStream.listen((int? indice) {
      if (indice == null || indice >= _cola.length) return;
      final Elemento actual = _cola[indice];
      if (actual.uri != _anotada) _anotada = null;
      _actual = Pista(titulo: actual.nombre, fuente: actual.uri, elemento: actual);
      unawaited(_guardarSesion());
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

  /// Cuanto hay que oir de una pista para que cuente como escuchada.
  ///
  /// Sin este minimo, pasar veinte canciones buscando una las dejaria a todas
  /// como escuchadas y «lo mas oido» no diria nada.
  static const Duration minimoParaContar = Duration(seconds: 20);

  /// La pista que ya se anoto, para no sumarla otra vez mientras siga sonando.
  String? _anotada;

  void _anotarSiYaCuenta(Duration instante) {
    final String? uri = _actual?.elemento?.uri;
    if (uri == null || uri == _anotada) return;
    if (instante < minimoParaContar) return;
    _anotada = uri;
    unawaited(Catalogo.instancia.anotarEscucha(uri));
  }

  // --- Retomar donde se dejo ----------------------------------------------

  @visibleForTesting
  static const String claveSesion = 'sesion_v1';

  bool _sesionRestaurada = false;
  DateTime _ultimoGuardado = DateTime.fromMillisecondsSinceEpoch(0);

  /// Cuantas ordenes de reproduccion lleva dadas el usuario.
  ///
  /// Retomar la sesion tarda: hay que leer la biblioteca entera y pedir una
  /// caratula por pista. Si mientras tanto el usuario toca una cancion, lo
  /// retomado llegaba despues y le quitaba la suya de debajo: la pantalla
  /// seguia con la que habia elegido, pero el motor se quedaba con la vieja y
  /// parada, asi que no sonaba nada y el telefono anunciaba otra cancion.
  /// Mirar la cola al entrar no bastaba, porque entre esa mirada y el momento
  /// de tocar el motor hay varios «await» de por medio.
  int _ordenes = 0;

  /// Apunta la cola y el punto exacto para poder seguir tras cerrar la app.
  Future<void> _guardarSesion() async {
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      if (_cola.isEmpty) {
        await memoria.remove(claveSesion);
        return;
      }
      await memoria.setString(
        claveSesion,
        jsonEncode(<String, dynamic>{
          'uris': _cola.map((Elemento e) => e.uri).toList(),
          'indice': motor.currentIndex ?? 0,
          'posicion': motor.position.inMilliseconds,
        }),
      );
    } catch (_) {
      // Quedarse sin guardar la sesion no puede cortar la musica.
    }
  }

  /// Guarda de tanto en tanto mientras suena, que la posicion cambia siempre.
  void _quizasGuardarSesion() {
    final DateTime ahora = DateTime.now();
    if (ahora.difference(_ultimoGuardado) < const Duration(seconds: 5)) return;
    _ultimoGuardado = ahora;
    unawaited(_guardarSesion());
  }

  /// Vuelve a dejar la cola como estaba, parada y en el mismo punto.
  ///
  /// No se pone a sonar sola: abrir la app no deberia arrancar musica. Lo que
  /// se haya borrado desde la ultima vez se cae de la cola, y el sitio donde
  /// ibas se busca por su URI y no por el numero que tenia, porque si algo de
  /// antes ya no esta ese numero apuntaria a otra cancion.
  Future<void> restaurarSesion() async {
    if (_sesionRestaurada || _cola.isNotEmpty) return;
    _sesionRestaurada = true;
    final int ordenes = _ordenes;
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      final String? crudo = memoria.getString(claveSesion);
      if (crudo == null || crudo.isEmpty) return;

      final ({List<Elemento> cola, int indice, Duration posicion})? sesion =
          sesionDesde(crudo, await Nucleo.biblioteca());
      if (sesion == null) return;
      // Cuanto antes se deje, mejor: las caratulas van por el mismo canal que
      // las que necesita lo que el usuario acaba de pedir, y le harian cola.
      if (_ordenes != ordenes) return;

      // Las caratulas de la cola entera son lo que mas tarda, y es justo la
      // espera en la que el usuario da al play. Se piden antes de tocar nada
      // para poder rendirse sin haber movido ya la pantalla, y se deja a
      // medias en cuanto el usuario pide algo.
      final List<AudioSource> fuentes =
          await _fuentes(sesion.cola, abandonar: () => _ordenes != ordenes);
      if (_ordenes != ordenes) return;

      _cola = sesion.cola;
      final Elemento donde = sesion.cola[sesion.indice];
      _actual = Pista(titulo: donde.nombre, fuente: donde.uri, elemento: donde);
      notifyListeners();

      await motor.setAudioSources(
        fuentes,
        initialIndex: sesion.indice,
        initialPosition: sesion.posicion,
      );
    } catch (_) {
      // Una sesion que ya no se entiende no puede impedir abrir la app.
    }
  }

  /// Traduce lo guardado a la cola que toca, cruzandolo con la biblioteca.
  ///
  /// Va aparte del motor a proposito: aqui esta todo lo que puede salir mal
  /// (una sesion ilegible, canciones borradas, un indice que ya no apunta a
  /// donde apuntaba) y asi se puede comprobar sin un reproductor de por medio.
  /// Devuelve `null` cuando no queda nada que retomar.
  @visibleForTesting
  static ({List<Elemento> cola, int indice, Duration posicion})? sesionDesde(
    String crudo,
    List<Elemento> biblioteca,
  ) {
    try {
      final Map<String, dynamic> datos = jsonDecode(crudo) as Map<String, dynamic>;
      final List<String> uris = ((datos['uris'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic u) => u.toString())
          .toList();
      if (uris.isEmpty) return null;

      final Map<String, Elemento> porUri = <String, Elemento>{
        for (final Elemento e in biblioteca) e.uri: e,
      };
      final List<Elemento> cola = <Elemento>[
        for (final String u in uris)
          if (porUri[u] != null) porUri[u]!,
      ];
      if (cola.isEmpty) return null;

      // El sitio se busca por la cancion y no por el numero que tenia: si algo
      // de antes ya no esta, ese numero apuntaria a otra distinta.
      final int guardado = (datos['indice'] as num?)?.toInt() ?? 0;
      final String? sonaba = guardado >= 0 && guardado < uris.length ? uris[guardado] : null;
      final int encontrado =
          sonaba == null ? 0 : cola.indexWhere((Elemento e) => e.uri == sonaba);

      return (
        cola: cola,
        indice: encontrado < 0 ? 0 : encontrado,
        posicion: Duration(milliseconds: (datos['posicion'] as num?)?.toInt() ?? 0),
      );
    } catch (_) {
      return null;
    }
  }

  /// Recupera el ecualizador guardado en cuanto el aparato diga sus bandas.
  ///
  /// Sin esperar al resultado: eso no pasa hasta que suena la primera pista, y
  /// bloquear el arranque de la app por un ajuste de sonido no tendria sentido.
  void recuperarEcualizador() {
    unawaited(Ecualizador.instancia.recuperar());
  }

  /// El orden aleatorio es nuestro y no el de fabrica para poder decidir donde
  /// caen las altas; ver [OrdenAleatorio].
  final OrdenAleatorio _orden = OrdenAleatorio();

  /// El ecualizador se enchufa al construir el motor: los efectos de Android
  /// no se pueden anadir a un reproductor que ya existe.
  late final AudioPlayer motor = AudioPlayer(
    shuffleOrder: _orden,
    audioPipeline: Ecualizador.instancia.tuberia,
  );

  /// Lo que hay en cola, en el orden en que se cargo. Sin ella no habria
  /// siguiente ni anterior.
  ///
  /// Va en paralelo a `motor.audioSources`: la posicion `i` de una es la `i` de
  /// la otra. Con el aleatorio puesto ese **no** es el orden en que suena; para
  /// eso esta [colaEnEscucha].
  List<Elemento> _cola = <Elemento>[];
  List<Elemento> get cola => List<Elemento>.unmodifiable(_cola);

  /// La cola en el orden en que se va a oir, con el aleatorio ya aplicado.
  List<Elemento> get colaEnEscucha => <Elemento>[
    for (final int i in motor.effectiveIndices)
      if (i < _cola.length) _cola[i],
  ];

  /// Que posicion de [colaEnEscucha] esta sonando, o -1 si no hay cola.
  int get posicionEnEscucha {
    final int? actual = motor.currentIndex;
    if (actual == null) return -1;
    return motor.effectiveIndices.indexOf(actual);
  }

  bool get haySiguiente => motor.hasNext;
  bool get hayAnterior => motor.hasPrevious;

  LoopMode get repeticion => motor.loopMode;

  bool get aleatorio => motor.shuffleModeEnabled;

  /// Reproduce desde una pista y deja el resto en cola detras.
  Future<void> reproducirLista(List<Elemento> elementos, int desde) async {
    if (elementos.isEmpty) return;
    final int ordenes = ++_ordenes;
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
      // Una cola nueva llega sin barajar. Si el aleatorio seguia puesto de
      // antes hay que rebarajar, o diria "aleatorio" y sonaria en orden.
      if (motor.shuffleModeEnabled) await motor.shuffle();
      await motor.play();
      unawaited(_guardarSesion());
    } catch (error) {
      _fallo(error, ordenes);
    }
  }

  /// Cuenta el fallo, salvo que sea de una carga que ya no interesaba.
  ///
  /// Si el usuario pide otra cosa antes de que la anterior termine de cargar,
  /// el motor abandona la primera con un «Loading interrupted». Eso no es una
  /// averia: es justo lo que se le pidio. Anunciarlo tapaba la pantalla con un
  /// error mientras la cancion nueva se preparaba debajo.
  void _fallo(Object error, int ordenes) {
    if (_ordenes != ordenes) return;
    _error = '$error';
    _actual = null;
    notifyListeners();
  }

  /// Prepara la cola pidiendo las caratulas de ocho en ocho.
  ///
  /// Una a una tardaria demasiado con una lista larga, y todas a la vez
  /// abriria un hilo por pista en Kotlin.
  /// [abandonar] se consulta entre tanda y tanda. Sin eso, lo que ya no
  /// interesa seguia pidiendo caratulas hasta el final, y como todas van por
  /// el mismo canal, lo que el usuario acababa de pedir esperaba su turno
  /// detras de las que quedaran. Ahi estaba la espera larga al abrir la app.
  Future<List<AudioSource>> _fuentes(
    List<Elemento> elementos, {
    bool Function()? abandonar,
  }) async {
    final List<AudioSource> fuentes = <AudioSource>[];
    for (int i = 0; i < elementos.length; i += 8) {
      if (abandonar?.call() ?? false) return const <AudioSource>[];
      final List<Elemento> trozo = elementos.skip(i).take(8).toList();
      final List<Uri?> artes = await Future.wait(trozo.map((Elemento e) => _arte(e.uri)));
      for (int j = 0; j < trozo.length; j++) {
        fuentes.add(_fuente(trozo[j], artes[j]));
      }
    }
    return fuentes;
  }

  /// Caratulas ya pedidas, para no volver a cruzar a Kotlin por la misma.
  ///
  /// Importa al encolar de una en una: sin esto, anadir una pista a la cola
  /// pagaria otra vez la consulta a MediaStore de una pista que ya suena.
  final Map<String, Uri?> _artes = <String, Uri?>{};

  Future<Uri?> _arte(String uri) async {
    if (_artes.containsKey(uri)) return _artes[uri];
    return _artes[uri] = await Nucleo.caratulaArchivo(uri);
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

  /// Pone o quita el aleatorio.
  ///
  /// Al ponerlo se baraja dejando en cabeza lo que ya suena, para no cortar la
  /// cancion a mitad; al quitarlo se vuelve al orden en que se cargo la cola.
  Future<void> alternarAleatorio() async {
    final bool activar = !motor.shuffleModeEnabled;
    if (activar) await motor.shuffle();
    await motor.setShuffleModeEnabled(activar);
    notifyListeners();
  }

  /// Mete una pista justo detras de la que suena.
  Future<void> reproducirAContinuacion(Elemento elemento) async {
    await _encolar(elemento, aContinuacion: true);
  }

  /// Mete una pista al final de lo que queda por sonar.
  Future<void> anadirAlFinal(Elemento elemento) async {
    await _encolar(elemento, aContinuacion: false);
  }

  Future<void> _encolar(Elemento elemento, {required bool aContinuacion}) async {
    if (_cola.isEmpty) {
      await reproducirLista(<Elemento>[elemento], 0);
      return;
    }
    final int actual = motor.currentIndex ?? 0;
    final int destino = aContinuacion ? actual + 1 : _cola.length;
    final AudioSource fuente = _fuente(elemento, await _arte(elemento.uri));

    // El orden aleatorio no sabe donde esta el oyente, asi que se le dice antes
    // de insertar y se le quita despues: solo vale para esta alta.
    _orden.proximaInsercion =
        aContinuacion ? posicionEnEscucha + 1 : motor.effectiveIndices.length;
    try {
      await motor.insertAudioSource(destino, fuente);
    } finally {
      _orden.proximaInsercion = null;
    }
    _cola.insert(destino, elemento);
    unawaited(_guardarSesion());
    notifyListeners();
  }

  /// Salta a una pista de la cola por su sitio en el orden de escucha.
  Future<void> saltarACola(int posicion) async {
    final List<int> escucha = motor.effectiveIndices;
    if (posicion < 0 || posicion >= escucha.length) return;
    await motor.seek(Duration.zero, index: escucha[posicion]);
    if (!motor.playing) await motor.play();
  }

  /// Quita de la cola la pista que ocupa esa posicion en el orden de escucha.
  Future<void> quitarDeCola(int posicion) async {
    final List<int> escucha = motor.effectiveIndices;
    if (posicion < 0 || posicion >= escucha.length) return;
    // Quedarse sin cola es cerrar: dejar el motor con cero fuentes lo deja en
    // un estado del que no sabe salir.
    if (escucha.length == 1) {
      await cerrar();
      return;
    }
    final int original = escucha[posicion];
    await motor.removeAudioSourceAt(original);
    _cola.removeAt(original);
    unawaited(_guardarSesion());
    notifyListeners();
  }

  /// Reordena la cola arrastrando. [hasta] ya viene sin contar el hueco que
  /// deja la fila al salir de su sitio.
  ///
  /// Solo tiene sentido sin aleatorio: con el puesto, el orden lo decide el
  /// barajado y moverlo a mano no se podria sostener. La pantalla esconde el
  /// asa en ese caso, y esto se guarda de todos modos.
  Future<void> moverEnCola(int desde, int hasta) async {
    if (aleatorio || desde == hasta) return;
    if (desde < 0 || desde >= _cola.length) return;
    final int destino = hasta.clamp(0, _cola.length - 1);
    await motor.moveAudioSource(desde, destino);
    _cola.insert(destino, _cola.removeAt(desde));
    unawaited(_guardarSesion());
    notifyListeners();
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

  // --- Temporizador de apagado -------------------------------------------

  Timer? _relojSuenio;
  DateTime? _finSuenio;

  /// Cuando se va a pausar sola, o `null` si no hay temporizador puesto.
  DateTime? get finSuenio => _finSuenio;

  /// Lo que falta para que se apague, o `null` si no hay temporizador.
  Duration? get restanteSuenio {
    final DateTime? fin = _finSuenio;
    if (fin == null) return null;
    final Duration queda = fin.difference(DateTime.now());
    return queda.isNegative ? Duration.zero : queda;
  }

  /// Pausa la reproduccion dentro de [espera].
  void dormirEn(Duration espera) {
    _relojSuenio?.cancel();
    _finSuenio = DateTime.now().add(espera);
    _relojSuenio = Timer(espera, () async {
      await motor.pause();
      cancelarSuenio();
    });
    notifyListeners();
  }

  /// Pausa al terminar lo que suena ahora.
  ///
  /// Se resuelve como un temporizador normal con lo que le queda a la pista, y
  /// no esperando a que cambie de indice, porque ese cambio tambien lo provoca
  /// el usuario al pulsar siguiente y apagaria la musica sin venir a cuento.
  void dormirAlAcabarPista() {
    final Duration total = motor.duration ?? Duration.zero;
    final Duration queda = total - motor.position;
    dormirEn(queda.isNegative ? Duration.zero : queda);
  }

  void cancelarSuenio() {
    _relojSuenio?.cancel();
    _relojSuenio = null;
    _finSuenio = null;
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
    final int ordenes = ++_ordenes;
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
      _fallo(error, ordenes);
    }
  }

  Future<void> alternar() async {
    if (motor.playing) {
      await motor.pause();
      unawaited(_guardarSesion());
    } else {
      await motor.play();
    }
  }

  /// Velocidades ofrecidas, de la mas lenta a la mas rapida.
  static const List<double> velocidades = <double>[0.75, 1, 1.25, 1.5, 2];

  double get velocidad => motor.speed;

  /// La que sigue en la lista, volviendo al principio al pasar la ultima.
  ///
  /// Una velocidad que no este en la lista (o la de arranque) devuelve la
  /// primera, para no quedarse sin salida.
  @visibleForTesting
  static double siguienteVelocidad(double actual) {
    final int donde = velocidades.indexOf(actual);
    return donde < 0 ? velocidades.first : velocidades[(donde + 1) % velocidades.length];
  }

  Future<void> alternarVelocidad() async {
    await motor.setSpeed(siguienteVelocidad(motor.speed));
    notifyListeners();
  }

  Future<void> saltar(Duration desplazamiento) async {
    final Duration destino = motor.position + desplazamiento;
    final Duration total = motor.duration ?? Duration.zero;
    await motor.seek(
      destino < Duration.zero ? Duration.zero : (destino > total ? total : destino),
    );
  }

  Future<void> cerrar() async {
    _ordenes++;
    _cola = <Elemento>[];
    cancelarSuenio();
    unawaited(_guardarSesion());
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
    _anotada = null;
    _error = null;
    _preparando = false;
    _cola = <Elemento>[];
    // Sin esto, una prueba que ya retomo la sesion dejaba la marca puesta y la
    // siguiente se saltaba el retomado entero sin que se notara.
    _sesionRestaurada = false;
    _ordenes = 0;
    _artes.clear();
    _relojSuenio?.cancel();
    _relojSuenio = null;
    _finSuenio = null;
    notifyListeners();
  }

  /// Si se borra lo que suena, dejar de sonar.
  Future<void> olvidarSiEs(String uri) async {
    if (esActual(uri)) await cerrar();
  }
}
