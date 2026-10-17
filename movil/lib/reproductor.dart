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
import 'hoja_fundido.dart';
import 'hoja_mejor_calidad.dart';
import 'movimiento_reproductor.dart';
import 'posiciones.dart';
import 'ritmos.dart';
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
            // En audio sin titulo: «REPRODUCIENDO» no cabia con los botones y
            // no decia nada que la pantalla no dijera ya.
            title: elemento.audio
                ? null
                : Text(
              'VIDEO',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
                color: tono.withValues(alpha: 0.7),
              ),
            ),
            actions: <Widget>[
              if (elemento.audio) ...<Widget>[
                // Sin marcar, en blanco: en el tinte de la caratula el corazon
                // marcado (cian hielo) y el primario quedaban casi iguales.
                BotonMeGusta(uri: elemento.uri, color: Colors.white70),
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
                  } else if (elegido == 'fundido') {
                    abrirFundido(context);
                  } else if (elegido == 'videoclip') {
                    verVideoclip(context, elemento);
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
                  if (elemento.audio)
                    const PopupMenuItem<String>(
                      value: 'videoclip',
                      child: ListTile(
                        leading: Icon(Icons.smart_display_outlined),
                        title: Text('Ver videoclip'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  if (elemento.audio)
                    const PopupMenuItem<String>(
                      value: 'fundido',
                      child: ListTile(
                        leading: Icon(Icons.blur_linear_rounded),
                        title: Text('Fundido entre canciones'),
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
        // Al cambiar de cancion, el fondo de una se funde con el de la otra.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 700),
          child: FutureBuilder<Uint8List?>(
            key: ValueKey<String>(elemento.uri),
            future: Nucleo.caratula(elemento.uri),
            builder: (BuildContext context, AsyncSnapshot<Uint8List?> imagen) {
              if (imagen.data == null) {
                return const ColoredBox(color: Tema.fondo);
              }
              // Se desenfoca una vez y queda en su capa: lo que se mueve
              // encima no obliga a desenfocarla de nuevo.
              return RepaintBoundary(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                  child: Image.memory(imagen.data!, fit: BoxFit.cover, gaplessPlayback: true),
                ),
              );
            },
          ),
        ),
        // Velo: sin el, el texto sobre la caratula no se lee. Va tenido con
        // el color de la propia portada en vez de con un gris.
        const VeloDePaleta(),
        // Los colores de la portada, moviendose despacio por encima del velo.
        const FondoVivo(),
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
          return Text(
            '${extension.toUpperCase()} de un original sin perdida',
            style: const TextStyle(color: Colors.white54, fontSize: 10),
          );
        }
        final bool inflado = !calidad.sinPerdida && archivoSinPerdida;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SelloCalidad(calidad: calidad),
            if (inflado)
              Text(
                '  en ${extension.toUpperCase()}',
                style: const TextStyle(color: Tema.textoTenue, fontSize: 10),
              ),
          ],
        );
      },
    );
  }

  /// El tempo de lo que suena y si va en una mezcla DJ. Nada si no se sabe.
  Widget _ritmo() {
    return ListenableBuilder(
      listenable: Ritmos.instancia,
      builder: (BuildContext context, _) {
        final String? bpm = Ritmos.instancia.rasgosDe(widget.elemento.uri)?.textoBpm;
        final bool dj = _estado.modoDj != null;
        if (bpm == null && !dj) return const SizedBox.shrink();
        return Text(
          '  ·  ${<String>[if (dj) _estado.alCompas ? 'DJ al compas' : 'DJ', ?bpm].join('  ·  ')}',
          style: const TextStyle(color: Tema.textoTenue, fontSize: 10, letterSpacing: 0.3),
        );
      },
    );
  }

  /// Lo tecnico (calidad, tempo, DJ) en una sola linea, entre los dos tiempos
  /// de la barra: es un hueco que estaba vacio y no le quita sitio a nada.
  Widget _detalles() {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[_sello(widget.elemento.nombre), _ritmo()],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AudioPlayer motor = _estado.motor;
    final ColorScheme colores = Theme.of(context).colorScheme;
    final ({String artista, String tema}) partes =
        widget.elemento.partes;

    // Sin hueco para la barra: el Scaffold ya mete su alto en el SafeArea del
    // fondo (extendBodyBehindAppBar), y con otro mas quedaba una franja vacia.
    return ConLatido(
      child: Column(
      children: <Widget>[
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
              child: _PortadaViva(elemento: widget.elemento, lado: MediaQuery.of(context).size.width),
            ),
          ),
        // Centrado cuando cabe y con desplazamiento cuando no: un titulo
        // largo en una pantalla corta desbordaria, y ya sabemos como queda.
        // Con la letra no: ocupan lo justo y la letra se queda todo lo demas.
        _ocupar(
          letras: widget.letras,
          hijo: Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
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
                  const SizedBox(height: 10),
          StreamBuilder<Duration>(
            stream: motor.positionStream,
            builder: (BuildContext context, AsyncSnapshot<Duration> instante) {
              final Duration total = motor.duration ?? Duration.zero;
              final Duration actual = instante.data ?? Duration.zero;
              final double maximo = total.inMilliseconds.toDouble();
              return Column(
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: BarraOndulada(
                      valor: maximo <= 0 ? 0 : (actual.inMilliseconds / maximo).clamp(0.0, 1.0),
                      sonando: _estado.sonando,
                      alSoltar: (double f) => motor.seek(Duration(milliseconds: (maximo * f).round())),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Row(
                      // Cifras tabulares: todas del mismo ancho, asi el
                      // contador no baila a cada segundo que pasa.
                      children: <Widget>[
                        Text(formatoTiempo(actual.inSeconds),
                            style: TextStyle(
                                color: colores.primary.withValues(alpha: 0.7),
                                fontSize: 12,
                                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Center(child: _detalles()),
                          ),
                        ),
                        Text(formatoTiempo(total.inSeconds),
                            style: TextStyle(
                                color: colores.primary.withValues(alpha: 0.7),
                                fontSize: 12,
                                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()])),
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
            // Los cuatro en una sola fila, compactos: en dos filas se comian
            // el sitio de la letra. En una pantalla muy estrecha se encogen.
            builder: (BuildContext context, _) => FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _BotonAleatorio(estado: _estado),
                  _BotonRepeticion(estado: _estado),
                  _BotonVelocidad(estado: _estado),
                  _BotonTramo(estado: _estado),
                ],
              ),
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
      ],
      ),
    );
  }

  /// Con la caratula, los datos van centrados en lo que sobre (y se desplazan
  /// si no caben); con la letra, solo lo justo, para que ella crezca.
  static Widget _ocupar({required bool letras, required Widget hijo}) => letras
      ? hijo
      : Expanded(
          child: Align(
            alignment: const Alignment(0, -0.45),
            child: SingleChildScrollView(child: hijo),
          ),
        );
}

class _BotonGrande extends StatelessWidget {
  const _BotonGrande({required this.sonando, required this.alPulsar});

  final bool sonando;
  final VoidCallback alPulsar;

  /// El mismo color, un poco mas claro y con el tono corrido hacia el cian.
  static Color _vecino(Color base) {
    final HSLColor hsl = HSLColor.fromColor(base);
    return hsl
        .withHue((hsl.hue - 18) % 360)
        .withLightness((hsl.lightness + 0.08).clamp(0, 0.85))
        .toColor();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final Latido? latido = Latido.de(context);
    // Un brillo alrededor y no una sombra desplazada, que parecia un segundo
    // boton debajo. Con pulso, brilla en cada golpe de la cancion.
    BoxDecoration brillo(double golpe) => BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: colores.primary.withValues(alpha: 0.28 + 0.32 * golpe),
              blurRadius: 22 + 16 * golpe,
              spreadRadius: 1 + 5 * golpe,
            ),
          ],
        );
    final Widget circulo = _circulo(colores);
    return GestureDetector(
      onTap: alPulsar,
      child: latido == null
          ? DecoratedBox(decoration: brillo(0), child: circulo)
          : ValueListenableBuilder<double>(
              valueListenable: latido.golpe,
              child: circulo,
              builder: (BuildContext context, double golpe, Widget? hijo) =>
                  DecoratedBox(decoration: brillo(golpe), child: hijo),
            ),
    );
  }

  Widget _circulo(ColorScheme colores) {
    return Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          // Sin caratula, el degradado de marca de cian a azul. Con caratula,
          // dos tonos vecinos de su primario: el terciario de Material gira el
          // tono (una portada azul acababa con el boton rosa) y el secundario
          // sale casi gris, porque Material le quita casi todo el color.
          gradient: LinearGradient(
            colors: colores == Paleta.neutra
                ? Tema.degradado.colors
                : <Color>[_vecino(colores.primary), colores.primary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Icon(
            sonando ? Icons.pause_rounded : Icons.play_arrow_rounded,
            key: ValueKey<bool>(sonando),
            size: 40,
            color: Tema.tinta,
          ),
        ),
    );
  }
}

/// La portada del reproductor: se funde con el fondo por abajo, respira con
/// cada pulso y, en el ultimo compas de una mezcla DJ, deja ver la siguiente.
class _PortadaViva extends StatelessWidget {
  const _PortadaViva({required this.elemento, required this.lado});

  final Elemento elemento;
  final double lado;

  @override
  Widget build(BuildContext context) {
    // Sin corte de golpe por abajo: no queda una franja entre ella y el titulo.
    final Widget portada = RepaintBoundary(
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (Rect r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.white, Colors.white, Colors.transparent],
          stops: <double>[0, 0.84, 1],
        ).createShader(r),
        child: PortadaLocal(elemento: elemento, lado: lado, radio: 0),
      ),
    );
    final Latido? latido = Latido.de(context);
    // En el vuelo del Hero no hay latido: va quieta, que es lo que toca.
    if (latido == null) return portada;
    return Stack(
      alignment: Alignment.center,
      children: <Widget>[
        ValueListenableBuilder<double>(
          valueListenable: latido.golpe,
          child: portada,
          builder: (BuildContext context, double golpe, Widget? hijo) =>
              Transform.scale(scale: 1 + 0.012 * golpe, child: hijo),
        ),
        Positioned.fill(child: _MezclaDj(latido: latido, lado: lado)),
      ],
    );
  }
}

/// El ultimo compas de una mezcla DJ, a la vista: la siguiente portada va
/// apareciendo encima y una cuenta 4·3·2·1 sigue el pulso hasta el corte.
class _MezclaDj extends StatelessWidget {
  const _MezclaDj({required this.latido, required this.lado});

  final Latido latido;
  final double lado;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int?>(
      valueListenable: latido.cuenta,
      builder: (BuildContext context, int? cuenta, _) {
        final Elemento? siguiente = EstadoReproductor.instancia.siguienteElemento;
        if (cuenta == null || siguiente == null) return const SizedBox.shrink();
        return IgnorePointer(
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              ValueListenableBuilder<double>(
                valueListenable: latido.mezcla,
                builder: (BuildContext context, double mezcla, Widget? hijo) =>
                    Opacity(opacity: mezcla * 0.85, child: hijo),
                child: PortadaLocal(elemento: siguiente, lado: lado, radio: 0),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (Widget hijo, Animation<double> a) =>
                        ScaleTransition(scale: Tween<double>(begin: 1.4, end: 1).animate(a), child: FadeTransition(opacity: a, child: hijo)),
                    child: Text(
                      '$cuenta',
                      key: ValueKey<int>(cuenta),
                      style: const TextStyle(
                        fontSize: 72,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        shadows: <Shadow>[Shadow(color: Tema.acentoHielo, blurRadius: 28)],
                      ),
                    ),
                  ),
                  const Text(
                    'MEZCLANDO AL COMPAS',
                    style: TextStyle(fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w700, color: Colors.white70),
                  ),
                ],
              ),
            ],
          ),
        );
      },
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
      final Duration? antes = await Posiciones.video.de(widget.elemento.uri);
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
      unawaited(Posiciones.video.guardar(
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

/// Botones de texto con poco relleno, para que quepan cuatro en una fila.
final ButtonStyle _compacto = TextButton.styleFrom(
  padding: const EdgeInsets.symmetric(horizontal: 8),
  minimumSize: const Size(0, 40),
  visualDensity: VisualDensity.compact,
);

/// Pone y quita el aleatorio.
class _BotonAleatorio extends StatelessWidget {
  const _BotonAleatorio({required this.estado});

  final EstadoReproductor estado;

  @override
  Widget build(BuildContext context) {
    final Color tono = Theme.of(context).colorScheme.primary;
    return TextButton.icon(
      style: _compacto,
      onPressed: estado.alternarAleatorio,
      icon: Icon(
        Icons.shuffle_rounded,
        size: 20,
        color: estado.aleatorio ? tono : Tema.textoTenue,
      ),
      label: Text(
        estado.aleatorio ? 'Aleatorio' : 'En orden',
        style: TextStyle(
          fontSize: 12,
          color: estado.aleatorio ? tono : Tema.textoTenue,
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
      style: _compacto,
      onPressed: estado.alternarVelocidad,
      icon: Icon(
        Icons.speed_rounded,
        size: 20,
        color: normal ? Tema.textoTenue : tono,
      ),
      label: Text(
        etiqueta,
        style: TextStyle(fontSize: 12, color: normal ? Tema.textoTenue : tono),
      ),
    );
  }
}

/// Marca el principio y el final de un tramo que se repite, y lo quita.
class _BotonTramo extends StatelessWidget {
  const _BotonTramo({required this.estado});

  final EstadoReproductor estado;

  @override
  Widget build(BuildContext context) {
    final Color tono = Theme.of(context).colorScheme.primary;
    final Duration? a = estado.puntoA;
    final Duration? b = estado.puntoB;
    final bool activo = a != null;
    // Lo que se ve dice lo que hara el siguiente toque.
    final (String etiqueta, String ayuda) = switch ((a, b)) {
      (null, _) => ('A-B', 'Marcar el principio del tramo'),
      (_, null) => ('A ${formatoTiempo(a!.inSeconds)}…', 'Marcar el final del tramo'),
      _ => (
          '${formatoTiempo(a!.inSeconds)}-${formatoTiempo(b!.inSeconds)}',
          'Dejar de repetir el tramo',
        ),
    };
    return Tooltip(
      message: ayuda,
      child: TextButton.icon(
        style: _compacto,
        onPressed: estado.alternarTramo,
        icon: Icon(Icons.repeat_one_on_rounded, size: 20, color: activo ? tono : Tema.textoTenue),
        label: Text(etiqueta, style: TextStyle(fontSize: 12, color: activo ? tono : Tema.textoTenue)),
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
      style: _compacto,
      onPressed: estado.alternarRepeticion,
      icon: Icon(
        estado.repeticion == LoopMode.one
            ? Icons.repeat_one_rounded
            : Icons.repeat_rounded,
        size: 20,
        color: activa ? tono : Tema.textoTenue,
      ),
      label: Text(
        switch (estado.repeticion) {
          LoopMode.off => 'Sin repetir',
          LoopMode.all => 'Repetir la lista',
          LoopMode.one => 'Repetir esta',
        },
        style: TextStyle(
          fontSize: 12,
          color: activa ? tono : Tema.textoTenue,
        ),
      ),
    );
  }
}
