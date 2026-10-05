import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'control_descarga.dart';
import 'formato.dart';
import 'nucleo.dart';
import 'portadas.dart';
import 'tema.dart';
import 'video_pro.dart';

/// Un episodio de un canal oficial, visto al vuelo sin descargarlo.
///
/// Usa el mismo reproductor que los videos de la biblioteca (gestos de
/// brillo, volumen, saltos, pantalla completa) y recuerda donde se quedo.
class PantallaEpisodio extends StatefulWidget {
  const PantallaEpisodio({required this.episodio, this.siguientes = const <Resultado>[], super.key});

  final Resultado episodio;

  /// Los que vienen detras en la misma lista, para pasar al siguiente.
  final List<Resultado> siguientes;

  @override
  State<PantallaEpisodio> createState() => _PantallaEpisodioState();
}

class _PantallaEpisodioState extends State<PantallaEpisodio> {
  VideoPlayerController? _motor;
  String? _error;
  bool _terminado = false;

  @override
  void initState() {
    super.initState();
    unawaited(_preparar());
  }

  Future<void> _preparar() async {
    try {
      final Previsualizacion pista =
          await Nucleo.previsualizar(widget.episodio.url, soloAudio: false);
      if (!mounted) return;
      final VideoPlayerController motor = VideoPlayerController.networkUrl(
        Uri.parse(pista.url),
        httpHeaders: pista.cabeceras,
        // El manifiesto de YouTube no acaba en .m3u8: sin la pista no se
        // reconoce como HLS.
        formatHint: pista.url.contains('m3u8') || pista.url.contains('manifest')
            ? VideoFormat.hls
            : null,
      );
      await motor.initialize();
      if (!mounted) {
        await motor.dispose();
        return;
      }
      final Duration? antes = await PosicionesVideo.de(widget.episodio.url);
      if (antes != null && antes < motor.value.duration) await motor.seekTo(antes);
      motor.addListener(_alAvanzar);
      setState(() => _motor = motor);
      unawaited(motor.play());
      if (antes != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Retomado en ${formatoTiempo(antes.inSeconds)}'),
          action: SnackBarAction(label: 'Desde el principio', onPressed: () => motor.seekTo(Duration.zero)),
        ));
      }
    } on ErrorNucleo catch (error) {
      if (mounted) setState(() => _error = error.mensaje);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  /// Al acabar se ofrece el siguiente, como en cualquier plataforma.
  void _alAvanzar() {
    final VideoPlayerController? motor = _motor;
    if (motor == null) return;
    final bool fin = motor.value.duration > Duration.zero &&
        motor.value.position >= motor.value.duration - const Duration(milliseconds: 500);
    if (fin != _terminado && mounted) setState(() => _terminado = fin);
  }

  void _siguiente() {
    if (widget.siguientes.isEmpty) return;
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => PantallaEpisodio(
        episodio: widget.siguientes.first,
        siguientes: widget.siguientes.sublist(1),
      ),
    ));
  }

  @override
  void dispose() {
    final VideoPlayerController? motor = _motor;
    if (motor != null) {
      unawaited(PosicionesVideo.guardar(widget.episodio.url, motor.value.position, motor.value.duration));
      motor.removeListener(_alAvanzar);
      unawaited(motor.dispose());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Nucleo.enVentanaFlotante,
      builder: (BuildContext context, bool flotando, _) {
        final VideoPlayerController? motor = _motor;
        // En la ventana flotante solo cabe la imagen.
        if (flotando && motor != null) {
          return ColoredBox(
            color: Colors.black,
            child: Center(
              child: AspectRatio(aspectRatio: motor.value.aspectRatio, child: VideoPlayer(motor)),
            ),
          );
        }
        return Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            title: Text(
              widget.episodio.autor,
              style: const TextStyle(fontSize: 13, color: Colors.white60),
            ),
          ),
          body: Column(
            children: <Widget>[
              Expanded(child: _video(motor)),
              _barra(context),
            ],
          ),
        );
      },
    );
  }

  Widget _video(VideoPlayerController? motor) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(Icons.portable_wifi_off_rounded, size: 48, color: Colors.white38),
              const SizedBox(height: 14),
              const Text(
                'No se pudo reproducir este episodio',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    if (motor == null) {
      // La miniatura mientras YouTube prepara el video: sin hueco negro.
      return Stack(
        alignment: Alignment.center,
        children: <Widget>[
          if (widget.episodio.miniatura.isNotEmpty)
            Opacity(
              opacity: 0.5,
              child: PortadaRemota(url: widget.episodio.miniatura, ancho: 360, alto: 202),
            ),
          const CircularProgressIndicator(),
        ],
      );
    }
    return ReproductorVideo(
      motor: motor,
      titulo: widget.episodio.titulo,
      alVentanaFlotante: () => Nucleo.pedirVentanaFlotante(
        ancho: motor.value.size.width.round(),
        alto: motor.value.size.height.round(),
      ),
    );
  }

  Widget _barra(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              widget.episodio.titulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(child: BotonDescargarVideo(url: widget.episodio.url)),
                if (widget.siguientes.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 10),
                  _terminado
                      ? FilledButton.icon(
                          onPressed: _siguiente,
                          icon: const Icon(Icons.skip_next_rounded),
                          label: const Text('Siguiente'),
                        )
                      : OutlinedButton.icon(
                          onPressed: _siguiente,
                          icon: const Icon(Icons.skip_next_rounded),
                          label: const Text('Siguiente'),
                        ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Bajar como video lo que se esta viendo, con su progreso en el sitio.
///
/// Siempre como video: si la app esta puesta en musica, un episodio de anime
/// en MP3 no le serviria a nadie. Los ajustes guardados no se tocan.
class BotonDescargarVideo extends StatelessWidget {
  const BotonDescargarVideo({required this.url, this.texto = 'Descargar', super.key});

  final String url;
  final String texto;

  @override
  Widget build(BuildContext context) {
    final ControlDescarga control = ControlDescarga.instancia;
    return ListenableBuilder(
      listenable: control,
      builder: (BuildContext context, _) {
        if (control.activa) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              LinearProgressIndicator(
                value: control.porcentaje,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 6),
              Text(
                control.progresoLote.isEmpty ? control.estado : '${control.progresoLote} · ${control.estado}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60, fontSize: 12),
              ),
            ],
          );
        }
        return FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Tema.acento,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          onPressed: () => descargarComoVideo(<String>[url]),
          icon: const Icon(Icons.download_rounded),
          label: Text(texto),
        );
      },
    );
  }
}

/// Baja una o varias como video, con la calidad elegida en la app.
Future<void> descargarComoVideo(List<String> urls) {
  final ControlDescarga control = ControlDescarga.instancia;
  return control.iniciarVarios(urls, con: control.ajustes.copiar(soloAudio: false));
}
