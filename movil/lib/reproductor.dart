import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import 'formato.dart';
import 'nucleo.dart';

/// Reproduce un elemento de la biblioteca.
///
/// Audio y video usan motores distintos a proposito: just_audio da un control
/// de reproduccion comodo para musica, y video_player pinta imagen.
class Reproductor extends StatelessWidget {
  const Reproductor({required this.elemento, super.key});

  final Elemento elemento;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(elemento.nombre, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: elemento.audio ? _Audio(elemento: elemento) : _Video(elemento: elemento),
    );
  }
}

class _Audio extends StatefulWidget {
  const _Audio({required this.elemento});

  final Elemento elemento;

  @override
  State<_Audio> createState() => _AudioState();
}

class _AudioState extends State<_Audio> {
  final AudioPlayer _motor = AudioPlayer();
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    try {
      await _motor.setUrl(widget.elemento.uri);
      await _motor.play();
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _motor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _Fallo(mensaje: _error!);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.music_note, size: 96, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(
            widget.elemento.nombre,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 32),
          StreamBuilder<Duration>(
            stream: _motor.positionStream,
            builder: (BuildContext context, AsyncSnapshot<Duration> instante) {
              final Duration total = _motor.duration ?? Duration.zero;
              final Duration actual = instante.data ?? Duration.zero;
              return Column(
                children: <Widget>[
                  Slider(
                    value: actual.inMilliseconds.clamp(0, total.inMilliseconds).toDouble(),
                    max: total.inMilliseconds.toDouble().clamp(1, double.infinity),
                    onChanged: (double v) => _motor.seek(Duration(milliseconds: v.round())),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text(formatoTiempo(actual.inSeconds)),
                      Text(formatoTiempo(total.inSeconds)),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          StreamBuilder<PlayerState>(
            stream: _motor.playerStateStream,
            builder: (BuildContext context, AsyncSnapshot<PlayerState> estado) {
              final bool sonando = estado.data?.playing ?? false;
              return IconButton.filled(
                iconSize: 48,
                onPressed: () => sonando ? _motor.pause() : _motor.play(),
                icon: Icon(sonando ? Icons.pause : Icons.play_arrow),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Video extends StatefulWidget {
  const _Video({required this.elemento});

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
    // contentUri: lo descargado vive en MediaStore, no en una ruta de archivo.
    _motor = VideoPlayerController.contentUri(Uri.parse(widget.elemento.uri));
    _motor.initialize().then((_) {
      if (!mounted) return;
      setState(() => _listo = true);
      _motor.play();
    }).catchError((Object error) {
      if (mounted) setState(() => _error = '$error');
    });
  }

  @override
  void dispose() {
    _motor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return _Fallo(mensaje: _error!);
    if (!_listo) return const Center(child: CircularProgressIndicator());
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        AspectRatio(
          aspectRatio: _motor.value.aspectRatio,
          child: VideoPlayer(_motor),
        ),
        VideoProgressIndicator(_motor, allowScrubbing: true),
        const SizedBox(height: 12),
        ValueListenableBuilder<VideoPlayerValue>(
          valueListenable: _motor,
          builder: (BuildContext context, VideoPlayerValue valor, _) => Column(
            children: <Widget>[
              Text('${formatoTiempo(valor.position.inSeconds)} / '
                  '${formatoTiempo(valor.duration.inSeconds)}'),
              const SizedBox(height: 8),
              IconButton.filled(
                iconSize: 48,
                onPressed: () => valor.isPlaying ? _motor.pause() : _motor.play(),
                icon: Icon(valor.isPlaying ? Icons.pause : Icons.play_arrow),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Fallo extends StatelessWidget {
  const _Fallo({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            const Text('No se pudo reproducir este archivo.'),
            const SizedBox(height: 8),
            Text(mensaje, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          ],
        ),
      );
}
