import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'control_descarga.dart';
import 'formato.dart';
import 'nucleo.dart';
import 'tema.dart';

/// Vista previa a pantalla completa: se ve y se oye antes de descargar.
///
/// Reproduce el manifiesto HLS que prepara el nucleo, porque YouTube ya casi
/// nunca ofrece un formato con imagen y sonido juntos y ese manifiesto los
/// combina. Mientras carga se muestra la miniatura, para que no haya un hueco
/// negro esperando.
class PantallaPrevia extends StatefulWidget {
  const PantallaPrevia({required this.resultado, super.key});

  final Resultado resultado;

  @override
  State<PantallaPrevia> createState() => _PantallaPreviaState();
}

class _PantallaPreviaState extends State<PantallaPrevia> {
  VideoPlayerController? _motor;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _preparar();
  }

  Future<void> _preparar() async {
    try {
      final Previsualizacion pista = await Nucleo.previsualizar(
        widget.resultado.url,
        soloAudio: false,
      );
      if (!mounted) return;
      final VideoPlayerController motor = VideoPlayerController.networkUrl(
        Uri.parse(pista.url),
        httpHeaders: pista.cabeceras,
        // La URL del manifiesto no acaba en .m3u8, asi que sin esta pista el
        // reproductor no adivina que es HLS.
        formatHint: _esHls(pista.url) ? VideoFormat.hls : null,
      );
      await motor.initialize();
      if (!mounted) {
        await motor.dispose();
        return;
      }
      motor.addListener(_alCambiar);
      await motor.play();
      setState(() {
        _motor = motor;
        _cargando = false;
      });
    } on ErrorNucleo catch (error) {
      _fallar(error.mensaje);
    } catch (error) {
      _fallar('$error');
    }
  }

  static bool _esHls(String url) => url.contains('m3u8') || url.contains('manifest');

  void _fallar(String mensaje) {
    if (!mounted) return;
    setState(() {
      _error = mensaje;
      _cargando = false;
    });
  }

  void _alCambiar() {
    if (mounted) setState(() {});
  }

  Future<void> _saltar(Duration desplazamiento) async {
    final VideoPlayerController? motor = _motor;
    if (motor == null) return;
    final Duration destino = motor.value.position + desplazamiento;
    final Duration total = motor.value.duration;
    await motor.seekTo(
      destino < Duration.zero ? Duration.zero : (destino > total ? total : destino),
    );
  }

  @override
  void dispose() {
    _motor?.removeListener(_alCambiar);
    _motor?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Nucleo.enVentanaFlotante,
      builder: (BuildContext context, bool flotando, _) =>
          flotando ? _soloVideo() : _completo(context),
    );
  }

  /// En la ventana flotante sobra todo lo demas: solo la imagen.
  Widget _soloVideo() {
    final VideoPlayerController? motor = _motor;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: motor == null
            ? const CircularProgressIndicator()
            : AspectRatio(aspectRatio: motor.value.aspectRatio, child: VideoPlayer(motor)),
      ),
    );
  }

  Widget _completo(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'VISTA PREVIA',
          style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w800),
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Compartir el enlace',
            onPressed: () => Nucleo.compartirEnlace(
              widget.resultado.url,
              titulo: widget.resultado.titulo,
            ),
            icon: const Icon(Icons.share_rounded, size: 20),
          ),
          if (_motor != null)
            IconButton(
              tooltip: 'Ventana flotante',
              onPressed: () => Nucleo.pedirVentanaFlotante(
                ancho: _motor!.value.size.width.round(),
                alto: _motor!.value.size.height.round(),
              ),
              icon: const Icon(Icons.picture_in_picture_alt_rounded),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (widget.resultado.miniatura.isNotEmpty)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 52, sigmaY: 52),
              child: Image.network(widget.resultado.miniatura, fit: BoxFit.cover),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xCC08070C), Color(0xF208070C), Tema.fondo],
              ),
            ),
          ),
          SafeArea(child: _contenido(context)),
        ],
      ),
    );
  }

  Widget _contenido(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints limites) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: limites.maxHeight - 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              _pantalla(),
              const SizedBox(height: 22),
              Text(
                widget.resultado.titulo,
                maxLines: 3,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style:
                    Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '${widget.resultado.autor}  ·  ${formatoTiempo(widget.resultado.duracion)}',
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 24),
              if (_error != null)
                _Fallo(mensaje: _error!)
              else ...<Widget>[
                _barra(),
                const SizedBox(height: 10),
                _controles(),
              ],
              const SizedBox(height: 22),
              _Descarga(resultado: widget.resultado),
              const SizedBox(height: 8),
              const Text(
                'Todavia no esta en tu telefono',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// El video, o la miniatura mientras se prepara.
  Widget _pantalla() {
    final VideoPlayerController? motor = _motor;
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: AspectRatio(
        aspectRatio: motor?.value.aspectRatio ?? 16 / 9,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (widget.resultado.miniatura.isNotEmpty)
              Image.network(widget.resultado.miniatura, fit: BoxFit.cover)
            else
              const ColoredBox(color: Tema.superficieAlta),
            if (motor != null)
              GestureDetector(
                onTap: () => motor.value.isPlaying ? motor.pause() : motor.play(),
                child: VideoPlayer(motor),
              ),
            if (_cargando)
              const ColoredBox(
                color: Colors.black45,
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _barra() {
    final VideoPlayerController? motor = _motor;
    final Duration actual = motor?.value.position ?? Duration.zero;
    final Duration total = motor?.value.duration ?? Duration.zero;
    final double maximo = total.inMilliseconds.toDouble();
    return Column(
      children: <Widget>[
        Slider(
          value: actual.inMilliseconds.clamp(0, maximo.toInt()).toDouble(),
          max: maximo <= 0 ? 1 : maximo,
          onChanged: motor == null
              ? null
              : (double v) => motor.seekTo(Duration(milliseconds: v.round())),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                formatoTiempo(actual.inSeconds),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
              Text(
                formatoTiempo(total.inSeconds),
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _controles() {
    final VideoPlayerController? motor = _motor;
    final bool sonando = motor?.value.isPlaying ?? false;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        IconButton(
          iconSize: 32,
          color: Colors.white70,
          onPressed: motor == null ? null : () => _saltar(const Duration(seconds: -10)),
          icon: const Icon(Icons.replay_10),
        ),
        const SizedBox(width: 18),
        GestureDetector(
          onTap: motor == null ? null : () => sonando ? motor.pause() : motor.play(),
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              gradient: Tema.degradado,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Tema.acento.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: _cargando
                ? const Padding(
                    padding: EdgeInsets.all(22),
                    child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black54),
                  )
                : Icon(
                    sonando ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 38,
                    color: Colors.black87,
                  ),
          ),
        ),
        const SizedBox(width: 18),
        IconButton(
          iconSize: 32,
          color: Colors.white70,
          onPressed: motor == null ? null : () => _saltar(const Duration(seconds: 10)),
          icon: const Icon(Icons.forward_10),
        ),
      ],
    );
  }
}

class _Fallo extends StatelessWidget {
  const _Fallo({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0x33FF6B81),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      children: <Widget>[
        const Icon(Icons.error_outline_rounded),
        const SizedBox(height: 8),
        const Text(
          'No se pudo preparar la vista previa',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          mensaje,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, height: 1.4),
        ),
      ],
    ),
  );
}

/// Descargar lo que se esta viendo, sin volver atras a buscarlo otra vez.
class _Descarga extends StatelessWidget {
  const _Descarga({required this.resultado});

  final Resultado resultado;

  @override
  Widget build(BuildContext context) {
    final ControlDescarga control = ControlDescarga.instancia;
    return ListenableBuilder(
      listenable: control,
      builder: (BuildContext context, _) {
        if (control.activa) {
          return Column(
            children: <Widget>[
              LinearProgressIndicator(
                value: control.porcentaje,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
              Text(control.estado, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          );
        }
        if (control.mensaje.isNotEmpty && !control.fallo) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.check_circle_rounded, color: Color(0xFF57D9A3)),
              const SizedBox(width: 8),
              Text(control.mensaje, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          );
        }
        return BotonDegradado(
          texto: control.ajustes.soloAudio ? 'Descargar MP3' : 'Descargar video',
          icono: Icons.arrow_downward_rounded,
          alPulsar: () => control.iniciar(resultado.url),
        );
      },
    );
  }
}
