import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'animaciones.dart';
import 'formato.dart';
import 'nucleo.dart';
import 'tema.dart';

/// Reproductor de video con los gestos de VLC y MX Player.
///
/// - Un toque: ensenia u oculta los controles.
/// - Doble toque a la izquierda o a la derecha: 10 segundos atras o adelante
///   (cada toque mas, otros 10).
/// - Deslizar en vertical por la izquierda: brillo; por la derecha: volumen.
/// - Deslizar a los lados: adelantar o atrasar, viendo a donde se va.
/// - Pellizcar: llenar la pantalla o verlo entero.
///
/// Todo va por un solo detector de escala. Con uno de arrastre y otro de
/// escala a la vez, Flutter no sabe a cual dar el gesto y la app falla.
class ReproductorVideo extends StatefulWidget {
  const ReproductorVideo({
    required this.motor,
    required this.titulo,
    required this.alVentanaFlotante,
    this.pantallaCompleta = false,
    super.key,
  });

  final VideoPlayerController motor;
  final String titulo;
  final VoidCallback alVentanaFlotante;
  final bool pantallaCompleta;

  @override
  State<ReproductorVideo> createState() => _ReproductorVideoState();
}

enum _Eje { ninguno, vertical, horizontal, pellizco }

class _ReproductorVideoState extends State<ReproductorVideo> {
  VideoPlayerController get _motor => widget.motor;

  bool _controles = true;
  bool _bloqueado = false;
  bool _llenar = false;
  Timer? _ocultar;

  // Arrastre en curso.
  _Eje _eje = _Eje.ninguno;
  bool _izquierda = false;
  Offset _inicio = Offset.zero;
  double _valorInicial = 0;
  Duration _destino = Duration.zero;

  double _brillo = 0.5;
  double _volumen = 0.5;

  // Lo que se ensenia en el centro mientras dura un gesto.
  IconData? _icono;
  String _aviso = '';
  double? _barra;
  Timer? _quitarAviso;

  // Dobles toques seguidos suman.
  int _saltos = 0;
  Timer? _finSaltos;

  static const List<double> _velocidades = <double>[1, 1.25, 1.5, 2, 0.5, 0.75];

  @override
  void initState() {
    super.initState();
    _programarOcultar();
    unawaited(_leerNiveles());
  }

  Future<void> _leerNiveles() async {
    try {
      final double b = await Nucleo.brillo();
      final double v = await Nucleo.volumen();
      if (!mounted) return;
      _brillo = b < 0 ? 0.5 : b;
      _volumen = v;
    } catch (_) {
      // Sin canal (en las pruebas) se queda en la mitad.
    }
  }

  @override
  void dispose() {
    _ocultar?.cancel();
    _quitarAviso?.cancel();
    _finSaltos?.cancel();
    super.dispose();
  }

  /// Con el video sonando, los controles se esconden solos a los 3 segundos.
  void _programarOcultar() {
    _ocultar?.cancel();
    _ocultar = Timer(const Duration(seconds: 3), () {
      if (mounted && _motor.value.isPlaying) setState(() => _controles = false);
    });
  }

  void _alternarControles() {
    setState(() => _controles = !_controles);
    if (_controles) _programarOcultar();
  }

  void _avisar(IconData icono, String texto, {double? barra}) {
    _quitarAviso?.cancel();
    setState(() {
      _icono = icono;
      _aviso = texto;
      _barra = barra;
    });
    _quitarAviso = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _icono = null);
    });
  }

  void _alternarPausa() {
    _motor.value.isPlaying ? _motor.pause() : _motor.play();
    _programarOcultar();
    setState(() {});
  }

  // --- Doble toque ---------------------------------------------------------

  void _dobleToque(TapDownDetails d) {
    final double ancho = context.size?.width ?? 1;
    final bool adelante = d.localPosition.dx > ancho / 2;
    final int lado = adelante ? 1 : -1;
    // Si se cambia de lado, se empieza a contar de nuevo.
    if (_saltos.sign != lado) _saltos = 0;
    _saltos += lado;
    final Duration nueva = _motor.value.position + Duration(seconds: 10 * lado);
    _motor.seekTo(_acotar(nueva));
    unawaited(HapticFeedback.selectionClick());
    _avisar(
      adelante ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
      '${adelante ? '+' : '-'}${_saltos.abs() * 10} s',
    );
    _finSaltos?.cancel();
    _finSaltos = Timer(const Duration(milliseconds: 800), () => _saltos = 0);
  }

  Duration _acotar(Duration d) {
    final Duration total = _motor.value.duration;
    if (d < Duration.zero) return Duration.zero;
    return d > total ? total : d;
  }

  // --- Arrastres y pellizco, por un solo detector -----------------------------

  double _escalaInicial = 1;

  void _empezar(ScaleStartDetails d) {
    _eje = d.pointerCount > 1 ? _Eje.pellizco : _Eje.ninguno;
    _inicio = d.localFocalPoint;
    _escalaInicial = 1;
    final double ancho = context.size?.width ?? 1;
    _izquierda = d.localFocalPoint.dx < ancho / 2;
  }

  void _mover(ScaleUpdateDetails d) {
    if (d.pointerCount > 1) {
      _eje = _Eje.pellizco;
      _escalaInicial = d.scale;
      return;
    }
    final Offset recorrido = d.localFocalPoint - _inicio;
    if (_eje == _Eje.ninguno) {
      // Hasta haber recorrido un poco no se decide: un toque tiembla.
      if (recorrido.distance < 12) return;
      _eje = recorrido.dy.abs() > recorrido.dx.abs() ? _Eje.vertical : _Eje.horizontal;
      _valorInicial = _izquierda ? _brillo : _volumen;
      _destino = _motor.value.position;
    }
    final Size tam = context.size ?? const Size(1, 1);
    if (_eje == _Eje.vertical) {
      // Toda la altura de la pantalla es de 0 a 100 %.
      final double valor = (_valorInicial - recorrido.dy / (tam.height * 0.8)).clamp(0.0, 1.0);
      if (_izquierda) {
        _brillo = valor;
        unawaited(Nucleo.brillo(valor).catchError((Object _) => valor));
        _avisar(Icons.brightness_6_rounded, 'Brillo ${(valor * 100).round()} %', barra: valor);
      } else {
        _volumen = valor;
        unawaited(Nucleo.volumen(valor).catchError((Object _) => valor));
        _avisar(
          valor == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
          'Volumen ${(valor * 100).round()} %',
          barra: valor,
        );
      }
    } else if (_eje == _Eje.horizontal) {
      // Todo el ancho son 90 segundos: fino para ajustar, rapido para saltar.
      final int segundos = (recorrido.dx / tam.width * 90).round();
      _destino = _acotar(_motor.value.position + Duration(seconds: segundos));
      final Duration total = _motor.value.duration;
      _avisar(
        segundos >= 0 ? Icons.fast_forward_rounded : Icons.fast_rewind_rounded,
        '${formatoTiempo(_destino.inSeconds)} / ${formatoTiempo(total.inSeconds)}',
        barra: total.inMilliseconds == 0 ? null : _destino.inMilliseconds / total.inMilliseconds,
      );
    }
  }

  void _terminar(ScaleEndDetails d) {
    if (_eje == _Eje.horizontal) _motor.seekTo(_destino);
    if (_eje == _Eje.pellizco) {
      final bool llenar = _escalaInicial > 1;
      if (llenar != _llenar) {
        setState(() => _llenar = llenar);
        _avisar(
          llenar ? Icons.fit_screen_rounded : Icons.fullscreen_exit_rounded,
          llenar ? 'Llenar pantalla' : 'Ver entero',
        );
      }
    }
    _eje = _Eje.ninguno;
  }

  // --- Botones ----------------------------------------------------------------

  void _cambiarVelocidad() {
    final double ahora = _motor.value.playbackSpeed;
    final int i = _velocidades.indexOf(ahora);
    final double siguiente = _velocidades[(i + 1) % _velocidades.length];
    _motor.setPlaybackSpeed(siguiente);
    _avisar(Icons.speed_rounded, '${siguiente}x');
    _programarOcultar();
  }

  Future<void> _pantallaCompleta() async {
    if (widget.pantallaCompleta) {
      Navigator.of(context).pop();
      return;
    }
    await Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: true,
        pageBuilder: (_, _, _) => _PantallaCompleta(
          motor: _motor,
          titulo: widget.titulo,
          alVentanaFlotante: widget.alVentanaFlotante,
        ),
        transitionsBuilder: (_, Animation<double> a, _, Widget hijo) =>
            FadeTransition(opacity: a, child: hijo),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final Size tam = _motor.value.size;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // El video: entero, o recortado para llenar la pantalla.
          ClipRect(
            child: FittedBox(
              fit: _llenar ? BoxFit.cover : BoxFit.contain,
              child: SizedBox(
                width: tam.width > 0 ? tam.width : 16,
                height: tam.height > 0 ? tam.height : 9,
                child: VideoPlayer(_motor),
              ),
            ),
          ),
          // La capa que recoge los gestos.
          if (!_bloqueado)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _alternarControles,
              onDoubleTapDown: _dobleToque,
              onDoubleTap: () {},
              onScaleStart: _empezar,
              onScaleUpdate: _mover,
              onScaleEnd: _terminar,
            ),
          // Lo que se esta haciendo, en el centro.
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _icono == null ? 0 : 1,
              duration: Movimiento.de(context, Movimiento.corto),
              child: Center(child: _indicador()),
            ),
          ),
          // Controles.
          if (_bloqueado)
            _botonDesbloquear()
          else
            IgnorePointer(
              ignoring: !_controles,
              child: AnimatedOpacity(
                opacity: _controles ? 1 : 0,
                duration: Movimiento.de(context, Movimiento.medio),
                child: _capaControles(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _indicador() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(_icono ?? Icons.circle, size: 34, color: Colors.white),
            const SizedBox(height: 8),
            Text(_aviso, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (_barra case final double b) ...<Widget>[
              const SizedBox(height: 10),
              SizedBox(
                width: 140,
                child: LinearProgressIndicator(
                  value: b,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                  color: Tema.acento,
                  backgroundColor: Colors.white24,
                ),
              ),
            ],
          ],
        ),
      );

  Widget _botonDesbloquear() => SafeArea(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: IconButton.filledTonal(
              tooltip: 'Desbloquear',
              onPressed: () => setState(() {
                _bloqueado = false;
                _controles = true;
                _programarOcultar();
              }),
              icon: const Icon(Icons.lock_rounded),
            ),
          ),
        ),
      );

  Widget _capaControles() {
    return DecoratedBox(
      // Un velo arriba y abajo para que se lean los controles sobre el video.
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Color(0xAA000000), Color(0x00000000), Color(0x00000000), Color(0xCC000000)],
          stops: <double>[0, 0.25, 0.6, 1],
        ),
      ),
      child: SafeArea(
        child: ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _motor,
          builder: (BuildContext context, VideoPlayerValue valor, _) => Column(
            children: <Widget>[
              Padding(
                padding: EdgeInsets.fromLTRB(widget.pantallaCompleta ? 4 : 56, 4, 8, 0),
                child: Row(
                  children: <Widget>[
                    if (widget.pantallaCompleta)
                      IconButton(
                        tooltip: 'Salir de pantalla completa',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back_rounded),
                      ),
                    Expanded(
                      child: Text(
                        widget.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      onPressed: _cambiarVelocidad,
                      child: Text('${valor.playbackSpeed}x', style: const TextStyle(color: Colors.white)),
                    ),
                    IconButton(
                      tooltip: 'Bloquear los controles',
                      onPressed: () => setState(() {
                        _bloqueado = true;
                        _controles = false;
                      }),
                      icon: const Icon(Icons.lock_open_rounded),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  IconButton(
                    iconSize: 38,
                    onPressed: () => _motor.seekTo(_acotar(valor.position - const Duration(seconds: 10))),
                    icon: const Icon(Icons.replay_10_rounded),
                  ),
                  const SizedBox(width: 28),
                  AlPulsarEncoge(
                    child: IconButton.filled(
                      iconSize: 44,
                      style: IconButton.styleFrom(backgroundColor: Colors.white24),
                      onPressed: _alternarPausa,
                      icon: AnimatedSwitcher(
                        duration: Movimiento.de(context, Movimiento.corto),
                        child: Icon(
                          valor.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          key: ValueKey<bool>(valor.isPlaying),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 28),
                  IconButton(
                    iconSize: 38,
                    onPressed: () => _motor.seekTo(_acotar(valor.position + const Duration(seconds: 10))),
                    icon: const Icon(Icons.forward_10_rounded),
                  ),
                ],
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
                child: Row(
                  children: <Widget>[
                    Text(formatoTiempo(valor.position.inSeconds), style: const TextStyle(fontSize: 12)),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: VideoProgressIndicator(
                          _motor,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: Tema.acento,
                            bufferedColor: Colors.white24,
                            backgroundColor: Colors.white12,
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    Text(formatoTiempo(valor.duration.inSeconds), style: const TextStyle(fontSize: 12)),
                    IconButton(
                      tooltip: 'Ventana flotante',
                      onPressed: widget.alVentanaFlotante,
                      icon: const Icon(Icons.picture_in_picture_alt_rounded, size: 22),
                    ),
                    IconButton(
                      tooltip: widget.pantallaCompleta ? 'Salir de pantalla completa' : 'Pantalla completa',
                      onPressed: _pantallaCompleta,
                      icon: Icon(
                        widget.pantallaCompleta ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// El mismo reproductor, a toda pantalla y girado si el video es apaisado.
class _PantallaCompleta extends StatefulWidget {
  const _PantallaCompleta({required this.motor, required this.titulo, required this.alVentanaFlotante});

  final VideoPlayerController motor;
  final String titulo;
  final VoidCallback alVentanaFlotante;

  @override
  State<_PantallaCompleta> createState() => _PantallaCompletaState();
}

class _PantallaCompletaState extends State<_PantallaCompleta> {
  @override
  void initState() {
    super.initState();
    final double proporcion = widget.motor.value.aspectRatio;
    // Apaisado se gira; uno vertical (un reel, un short) se queda en vertical.
    if (proporcion >= 1) {
      SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    // Al salir, todo como estaba: vertical y con las barras del sistema.
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: ReproductorVideo(
          motor: widget.motor,
          titulo: widget.titulo,
          alVentanaFlotante: widget.alVentanaFlotante,
          pantallaCompleta: true,
        ),
      );
}

/// Donde se dejo cada video, para retomarlo.
///
/// Solo se guarda si se vio algo (mas de 10 segundos) y no se termino (le
/// quedaban mas de 15): un video acabado vuelve a empezar desde el principio.
class PosicionesVideo {
  PosicionesVideo._();

  static const String _clave = 'posiciones_video_v1';
  static const int _maximo = 60;

  static Future<Duration?> de(String uri) async {
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      final Map<String, dynamic> todas =
          jsonDecode(memoria.getString(_clave) ?? '{}') as Map<String, dynamic>;
      final int? ms = (todas[uri] as num?)?.toInt();
      return ms == null ? null : Duration(milliseconds: ms);
    } catch (_) {
      return null;
    }
  }

  static Future<void> guardar(String uri, Duration posicion, Duration total) async {
    try {
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      final Map<String, dynamic> todas =
          jsonDecode(memoria.getString(_clave) ?? '{}') as Map<String, dynamic>;
      todas.remove(uri);
      if (merece(posicion, total)) todas[uri] = posicion.inMilliseconds;
      // Las mas antiguas se olvidan: no hace falta recordar cien videos.
      while (todas.length > _maximo) {
        todas.remove(todas.keys.first);
      }
      await memoria.setString(_clave, jsonEncode(todas));
    } catch (_) {
      // Sin poder guardar, la proxima vez empieza desde el principio.
    }
  }

  @visibleForTesting
  static bool merece(Duration posicion, Duration total) =>
      posicion.inSeconds > 10 && (total - posicion).inSeconds > 15;
}
