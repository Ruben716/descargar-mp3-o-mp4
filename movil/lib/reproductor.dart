import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import 'calidad.dart';
import 'catalogo.dart';
import 'estado_reproductor.dart';
import 'formato.dart';
import 'gestos.dart';
import 'hoja_cola.dart';
import 'hoja_ecualizador.dart';
import 'hoja_suenio.dart';
import 'nucleo.dart';
import 'pantalla_lista_auto.dart';
import 'paleta.dart';
import 'panel_letras.dart';
import 'portadas.dart';
import 'tema.dart';
import 'video_pro.dart';

/// Reproduce un elemento de la biblioteca a pantalla completa.
class Reproductor extends StatefulWidget {
  const Reproductor({required this.elemento, this.arrancar = true, super.key});

  final Elemento elemento;

  /// Si al abrirse tiene que poner la pista a sonar.
  ///
  /// Desde una lista no: la lista ya la puso, con todas las demas en cola. Antes
  /// el reproductor lo decidia mirando si «ya sonaba», y esa mirada competia
  /// con el motor: si el motor avisaba antes de su posicion en la cola nueva,
  /// parecia que sonaba otra, y el reproductor ponia la pista sola, sin cola.
  /// Por eso no se podia pasar a la siguiente.
  final bool arrancar;

  @override
  State<Reproductor> createState() => _ReproductorState();
}

class _ReproductorState extends State<Reproductor> {
  /// Con clave global el video conserva su estado aunque cambie de sitio en el
  /// arbol, que es justo lo que pasa al entrar y salir de la ventana flotante.
  /// Sin ella se reiniciaria desde el principio cada vez.
  final GlobalKey _claveVideo = GlobalKey();

  /// Si se ve la letra en lugar de la caratula.
  bool _letras = false;

  final EstadoReproductor _estado = EstadoReproductor.instancia;

  @override
  void initState() {
    super.initState();
    // Arrancar la pista se decide aqui y no mas abajo porque ahi el elemento
    // ya es el que suena, y entonces nunca se pondria la que se pidio.
    if (widget.arrancar && widget.elemento.audio && !_estado.esActual(widget.elemento.uri)) {
      _estado.reproducirElemento(widget.elemento);
    }
  }

  /// La pista que toca ensenar.
  ///
  /// Con una cola, lo que suena cambia solo al acabar cada cancion y la
  /// pantalla tiene que seguirlo: antes se quedaba con la que se abrio, asi
  /// que cambiaba el sonido pero no la caratula ni el titulo. El video no se
  /// encola, de modo que ese se queda con el suyo.
  Elemento get _pista =>
      widget.elemento.audio ? (_estado.actual?.elemento ?? widget.elemento) : widget.elemento;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _estado,
      builder: (BuildContext context, _) => _pantalla(context, _pista),
    );
  }

  Widget _pantalla(BuildContext context, Elemento elemento) {
    return ValueListenableBuilder<bool>(
      valueListenable: Nucleo.enVentanaFlotante,
      builder: (BuildContext context, bool flotando, _) {
        final Widget contenido = elemento.audio
            ? _Audio(elemento: elemento, letras: _letras)
            : _Video(key: _claveVideo, elemento: elemento);

        // En la ventana flotante no cabe nada mas que la imagen: ni barra de
        // titulo ni fondo, que es lo que la afeaba.
        if (flotando && !elemento.audio) {
          return ColoredBox(color: Colors.black, child: contenido);
        }

        return ConPaletaDe(
          uri: elemento.uri,
          hijo: Builder(
            builder: (BuildContext context) => _armazon(context, elemento, contenido),
          ),
        );
      },
    );
  }

  Widget _armazon(BuildContext context, Elemento elemento, Widget contenido) {
    final Color tono = Theme.of(context).colorScheme.primary;
    return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            iconTheme: IconThemeData(color: tono),
            title: Text(
              elemento.audio ? 'REPRODUCIENDO' : 'VIDEO',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: tono.withValues(alpha: 0.7),
              ),
            ),
            actions: <Widget>[
              if (elemento.audio) ...<Widget>[
                BotonMeGusta(uri: elemento.uri, color: Theme.of(context).colorScheme.primary),
                IconButton(
                  tooltip: _letras ? 'Ver la caratula' : 'Ver la letra',
                  onPressed: () => setState(() => _letras = !_letras),
                  icon: Icon(
                    _letras ? Icons.lyrics_rounded : Icons.lyrics_outlined,
                    size: 22,
                    color: _letras ? tono : tono.withValues(alpha: 0.7),
                  ),
                ),
                const _BotonTemporizador(),
                IconButton(
                  tooltip: 'Ver la cola',
                  onPressed: () => abrirCola(context),
                  icon: const Icon(Icons.queue_music_rounded, size: 22),
                ),
              ],
              PopupMenuButton<String>(
                color: Tema.superficieAlta,
                icon: const Icon(Icons.more_vert_rounded, size: 20),
                onSelected: (String elegido) {
                  if (elegido == 'compartir') {
                    Nucleo.compartirArchivo(elemento.uri, audio: elemento.audio);
                  } else {
                    abrirEcualizador(context);
                  }
                },
                itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                  if (elemento.audio)
                    const PopupMenuItem<String>(
                      value: 'ecualizador',
                      child: ListTile(
                        leading: Icon(Icons.graphic_eq_rounded),
                        title: Text('Ecualizador'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  const PopupMenuItem<String>(
                    value: 'compartir',
                    child: ListTile(
                      leading: Icon(Icons.share_rounded),
                      title: Text('Compartir'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
      body: _Fondo(elemento: elemento, hijo: contenido),
    );
  }
}

/// La propia caratula, difuminada, hace de fondo. Da color sin inventarlo.
class _Fondo extends StatelessWidget {
  const _Fondo({required this.elemento, required this.hijo});

  final Elemento elemento;
  final Widget hijo;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FutureBuilder<Uint8List?>(
          future: Nucleo.caratula(elemento.uri),
          builder: (BuildContext context, AsyncSnapshot<Uint8List?> imagen) {
            if (imagen.data == null) {
              return const ColoredBox(color: Tema.fondo);
            }
            return ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
              child: Image.memory(imagen.data!, fit: BoxFit.cover),
            );
          },
        ),
        // Velo: sin el, el texto sobre la caratula no se lee. Va tenido con
        // el color de la propia portada en vez de con un gris.
        const VeloDePaleta(),
        SafeArea(child: hijo),
      ],
    );
  }
}

class _Audio extends StatefulWidget {
  const _Audio({required this.elemento, required this.letras});

  final Elemento elemento;

  /// Si en el hueco de la caratula va la letra.
  final bool letras;

  @override
  State<_Audio> createState() => _AudioState();
}

class _AudioState extends State<_Audio> {
  final EstadoReproductor _estado = EstadoReproductor.instancia;

  /// De que calidad llego esta cancion, pedido una vez por pista.
  Future<CalidadAudio?>? _calidad;
  String _calidadPara = '';

  Future<CalidadAudio?> _calidadDe(String uri) {
    if (uri != _calidadPara || _calidad == null) {
      _calidadPara = uri;
      _calidad = Catalogo.instancia.calidadDe(uri);
    }
    return _calidad!;
  }

  /// El sello de calidad, con el archivo si no casa con el origen.
  ///
  /// Un FLAC hecho desde YouTube no es sin perdida: el sello dice de donde
  /// salio el sonido, y aparte en que se guardo, para que no se confunda.
  Widget _sello(String nombre) {
    return FutureBuilder<CalidadAudio?>(
      future: _calidadDe(widget.elemento.uri),
      builder: (BuildContext context, AsyncSnapshot<CalidadAudio?> datos) {
        final CalidadAudio? calidad = datos.data;
        if (calidad == null) return const SizedBox.shrink();
        final String extension = nombre.contains('.') ? nombre.split('.').last.toLowerCase() : '';
        final bool archivoSinPerdida = const <String>['flac', 'wav'].contains(extension);
        // Un MP3 hecho desde un original sin perdida ya no es sin perdida: el
        // sello dorado seria mentira. Se dice que se bajo de ahi, sin mas.
        if (calidad.sinPerdida && !archivoSinPerdida && extension.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '${extension.toUpperCase()} · hecho desde un original sin perdida',
              style: const TextStyle(color: Colors.white54, fontSize: 11),
            ),
          );
        }
        final bool inflado = !calidad.sinPerdida && archivoSinPerdida;
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            children: <Widget>[
              SelloCalidad(calidad: calidad, grande: true),
              if (inflado)
                Text(
                  'guardado en ${extension.toUpperCase()}',
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final AudioPlayer motor = _estado.motor;
    final ColorScheme colores = Theme.of(context).colorScheme;
    final ({String artista, String tema}) partes =
        widget.elemento.partes;

    return Column(
      children: <Widget>[
        const SizedBox(height: kToolbarHeight),
        if (widget.letras)
          Expanded(child: PanelLetras(elemento: widget.elemento))
        else
          // A sangre: la portada llega a los dos bordes, sin margen ni
          // esquinas. Es lo que hace que mande en la pantalla.
          // Deslizar la portada cambia de cancion, como en cualquier app de
          // musica: hacia la izquierda la siguiente, hacia la derecha la anterior.
          DeslizarParaCambiar(
            alSiguiente: _estado.haySiguiente ? _estado.siguiente : null,
            alAnterior: _estado.hayAnterior ? _estado.irALaAnterior : null,
            child: Hero(
              tag: widget.elemento.uri,
              child: PortadaLocal(
                elemento: widget.elemento,
                lado: MediaQuery.of(context).size.width,
                radio: 0,
              ),
            ),
          ),
        // Centrado cuando cabe y con desplazamiento cuando no: un titulo
        // largo en una pantalla corta desbordaria, y ya sabemos como queda.
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    partes.tema,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: colores.primary,
                    ),
                  ),
                  if (partes.artista.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      partes.artista,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: colores.primary.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                  _sello(widget.elemento.nombre),
                  const SizedBox(height: 18),
          StreamBuilder<Duration>(
            stream: motor.positionStream,
            builder: (BuildContext context, AsyncSnapshot<Duration> instante) {
              final Duration total = motor.duration ?? Duration.zero;
              final Duration actual = instante.data ?? Duration.zero;
              final double maximo = total.inMilliseconds.toDouble();
              return Column(
                children: <Widget>[
                  Slider(
                    value: actual.inMilliseconds.clamp(0, maximo.toInt()).toDouble(),
                    max: maximo <= 0 ? 1 : maximo,
                    onChanged: (double v) => motor.seek(Duration(milliseconds: v.round())),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        Text(formatoTiempo(actual.inSeconds),
                            style: TextStyle(
                                color: colores.primary.withValues(alpha: 0.7),
                                fontSize: 12)),
                        Text(formatoTiempo(total.inSeconds),
                            style: TextStyle(
                                color: colores.primary.withValues(alpha: 0.7),
                                fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          ListenableBuilder(
            listenable: _estado,
            // Wrap y no Row: tres botones con sus etiquetas no caben en una
            // pantalla estrecha, y asi bajan de linea en vez de desbordar.
            builder: (BuildContext context, _) => Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                _BotonAleatorio(estado: _estado),
                _BotonRepeticion(estado: _estado),
                _BotonVelocidad(estado: _estado),
              ],
            ),
          ),
          const SizedBox(height: 4),
          ListenableBuilder(
            listenable: _estado,
            builder: (BuildContext context, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                IconButton(
                  iconSize: 30,
                  color: _estado.hayAnterior
                      ? colores.primary.withValues(alpha: 0.85)
                      : colores.primary.withValues(alpha: 0.25),
                  onPressed: _estado.anterior,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                IconButton(
                  iconSize: 30,
                  color: colores.primary.withValues(alpha: 0.85),
                  onPressed: () => _estado.saltar(const Duration(seconds: -10)),
                  icon: const Icon(Icons.replay_10),
                ),
                const SizedBox(width: 12),
                _BotonGrande(
                  sonando: _estado.sonando,
                  alPulsar: _estado.alternar,
                ),
                const SizedBox(width: 12),
                IconButton(
                  iconSize: 30,
                  color: colores.primary.withValues(alpha: 0.85),
                  onPressed: () => _estado.saltar(const Duration(seconds: 10)),
                  icon: const Icon(Icons.forward_10),
                ),
                IconButton(
                  iconSize: 30,
                  color: _estado.haySiguiente
                      ? colores.primary.withValues(alpha: 0.85)
                      : colores.primary.withValues(alpha: 0.25),
                  onPressed: _estado.haySiguiente ? _estado.siguiente : null,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
          ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BotonGrande extends StatelessWidget {
  const _BotonGrande({required this.sonando, required this.alPulsar});

  final bool sonando;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: alPulsar,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[colores.primary, colores.tertiary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colores.primary.withValues(alpha: 0.45),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Icon(
            sonando ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey<bool>(sonando),
            size: 40,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

class _Video extends StatefulWidget {
  const _Video({required this.elemento, super.key});

  final Elemento elemento;

  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> {
  late final VideoPlayerController _motor;
  String? _error;
  bool _listo = false;

  @override
  void initState() {
    super.initState();
    // Los archivos viven en MediaStore, no en una ruta que se pueda abrir.
    _motor = VideoPlayerController.contentUri(Uri.parse(widget.elemento.uri));
    _motor.initialize().then((_) async {
      if (!mounted) return;
      // Si se dejo a medias, se retoma ahi y se ofrece empezar de cero.
      final Duration? antes = await PosicionesVideo.de(widget.elemento.uri);
      if (antes != null && antes < _motor.value.duration) await _motor.seekTo(antes);
      if (!mounted) return;
      setState(() => _listo = true);
      unawaited(_motor.play());
      if (antes != null) _avisarRetomado(antes);
    }).catchError((Object error) {
      if (mounted) setState(() => _error = '$error');
    });
  }

  void _avisarRetomado(Duration desde) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Retomado en ${formatoTiempo(desde.inSeconds)}'),
        action: SnackBarAction(
          label: 'Desde el principio',
          onPressed: () => _motor.seekTo(Duration.zero),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Donde se quedo, para la proxima vez.
    if (_listo) {
      unawaited(PosicionesVideo.guardar(
        widget.elemento.uri,
        _motor.value.position,
        _motor.value.duration,
      ));
    }
    _motor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.error_outline, size: 48, color: Colors.white54),
              const SizedBox(height: 12),
              const Text('No se pudo reproducir este video.'),
              const SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
            ],
          ),
        ),
      );
    }
    if (!_listo) return const Center(child: CircularProgressIndicator());

    return ValueListenableBuilder<bool>(
      valueListenable: Nucleo.enVentanaFlotante,
      builder: (BuildContext context, bool flotando, _) =>
          flotando ? _soloVideo() : _completo(context),
    );
  }

  /// En la ventana flotante sobra todo lo demas: solo la imagen.
  Widget _soloVideo() => ColoredBox(
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: _motor.value.aspectRatio,
            child: VideoPlayer(_motor),
          ),
        ),
      );

  Widget _completo(BuildContext context) => ReproductorVideo(
        motor: _motor,
        titulo: _sinExtension(widget.elemento.nombre),
        alVentanaFlotante: () => Nucleo.pedirVentanaFlotante(
          ancho: _motor.value.size.width.round(),
          alto: _motor.value.size.height.round(),
        ),
      );
}

/// Coloca el video y sus controles sin que nada se salga de la pantalla.
///
/// El video va en un Expanded y no entre Spacer. Con Spacer, el AspectRatio
/// recibe la altura que quiera: en apaisado sale bajito y cabe, pero uno
/// vertical se estira hasta 1,78 veces el ancho y empuja los controles fuera.
/// Dentro de un Expanded la altura viene acotada y el video se encoge solo.
class MarcoVideo extends StatelessWidget {
  const MarcoVideo({
    required this.proporcion,
    required this.video,
    required this.controles,
    super.key,
  });

  /// Ancho partido por alto. Un video sin medir aun llega como cero.
  final double proporcion;
  final Widget video;
  final Widget controles;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: AspectRatio(
                aspectRatio: proporcion > 0 ? proporcion : 16 / 9,
                child: video,
              ),
            ),
          ),
        ),
        controles,
      ],
    );
  }
}

/// Los archivos llevan la extension y el id en el nombre; en pantalla estorban.
String _sinExtension(String nombre) {
  final String sinExt = nombre.replaceAll(RegExp(r'\.[a-zA-Z0-9]{2,4}$'), '');
  return sinExt.replaceAll(RegExp(r'\s*\[[^\]]+\]\s*$'), '').trim();
}


/// Abre el temporizador, y se enciende mientras haya uno puesto.
class _BotonTemporizador extends StatelessWidget {
  const _BotonTemporizador();

  @override
  Widget build(BuildContext context) {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    return ListenableBuilder(
      listenable: estado,
      builder: (BuildContext context, _) {
        final bool puesto = estado.finSuenio != null;
        return IconButton(
          tooltip: puesto ? 'Temporizador puesto' : 'Temporizador',
          onPressed: () => abrirTemporizador(context),
          icon: Icon(
            puesto ? Icons.bedtime_rounded : Icons.bedtime_outlined,
            size: 20,
            color: puesto ? Tema.acento : null,
          ),
        );
      },
    );
  }
}

/// Pone y quita el aleatorio.
class _BotonAleatorio extends StatelessWidget {
  const _BotonAleatorio({required this.estado});

  final EstadoReproductor estado;

  @override
  Widget build(BuildContext context) {
    final Color tono = Theme.of(context).colorScheme.primary;
    return TextButton.icon(
      onPressed: estado.alternarAleatorio,
      icon: Icon(
        Icons.shuffle_rounded,
        size: 20,
        color: estado.aleatorio ? tono : Colors.white38,
      ),
      label: Text(
        estado.aleatorio ? 'Aleatorio' : 'En orden',
        style: TextStyle(
          fontSize: 12,
          color: estado.aleatorio ? tono : Colors.white38,
        ),
      ),
    );
  }
}

/// Pasa por las velocidades de reproduccion.
class _BotonVelocidad extends StatelessWidget {
  const _BotonVelocidad({required this.estado});

  final EstadoReproductor estado;

  @override
  Widget build(BuildContext context) {
    final bool normal = estado.velocidad == 1;
    final Color tono = Theme.of(context).colorScheme.primary;
    // «1x» se escribe sin decimales; «1.25x» los necesita.
    final String etiqueta = estado.velocidad == estado.velocidad.roundToDouble()
        ? '${estado.velocidad.round()}x'
        : '${estado.velocidad}x';
    return TextButton.icon(
      onPressed: estado.alternarVelocidad,
      icon: Icon(
        Icons.speed_rounded,
        size: 20,
        color: normal ? Colors.white38 : tono,
      ),
      label: Text(
        etiqueta,
        style: TextStyle(fontSize: 12, color: normal ? Colors.white38 : tono),
      ),
    );
  }
}

/// Cicla entre no repetir, repetir la cola y repetir una sola.
class _BotonRepeticion extends StatelessWidget {
  const _BotonRepeticion({required this.estado});

  final EstadoReproductor estado;

  @override
  Widget build(BuildContext context) {
    final bool activa = estado.repeticion != LoopMode.off;
    final Color tono = Theme.of(context).colorScheme.primary;
    return TextButton.icon(
      onPressed: estado.alternarRepeticion,
      icon: Icon(
        estado.repeticion == LoopMode.one
            ? Icons.repeat_one_rounded
            : Icons.repeat_rounded,
        size: 20,
        color: activa ? tono : Colors.white38,
      ),
      label: Text(
        switch (estado.repeticion) {
          LoopMode.off => 'Sin repetir',
          LoopMode.all => 'Repetir la lista',
          LoopMode.one => 'Repetir esta',
        },
        style: TextStyle(
          fontSize: 12,
          color: activa ? tono : Colors.white38,
        ),
      ),
    );
  }
}
