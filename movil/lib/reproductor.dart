import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';

import 'estado_reproductor.dart';
import 'formato.dart';
import 'hoja_cola.dart';
import 'hoja_ecualizador.dart';
import 'hoja_suenio.dart';
import 'nucleo.dart';
import 'panel_letras.dart';
import 'portadas.dart';
import 'tema.dart';

/// Reproduce un elemento de la biblioteca a pantalla completa.
class Reproductor extends StatefulWidget {
  const Reproductor({required this.elemento, super.key});

  final Elemento elemento;

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

  @override
  Widget build(BuildContext context) {
    final Elemento elemento = widget.elemento;
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

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              elemento.audio ? 'Reproduciendo' : 'Video',
              style: const TextStyle(fontSize: 14, color: Colors.white70),
            ),
            actions: <Widget>[
              if (elemento.audio) ...<Widget>[
                IconButton(
                  tooltip: _letras ? 'Ver la caratula' : 'Ver la letra',
                  onPressed: () => setState(() => _letras = !_letras),
                  icon: Icon(
                    _letras ? Icons.lyrics_rounded : Icons.lyrics_outlined,
                    size: 22,
                    color: _letras ? Tema.acento : null,
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
      },
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
        // Velo oscuro: sin el, el texto sobre la caratula no se lee.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[Color(0xCC08070C), Color(0xF208070C), Tema.fondo],
            ),
          ),
        ),
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

  @override
  void initState() {
    super.initState();
    if (!_estado.esActual(widget.elemento.uri)) {
      _estado.reproducirElemento(widget.elemento);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AudioPlayer motor = _estado.motor;
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 28),
      child: Column(
        children: <Widget>[
          if (widget.letras)
            Expanded(child: PanelLetras(elemento: widget.elemento))
          else ...<Widget>[
            const Spacer(),
            Hero(
              tag: widget.elemento.uri,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.6),
                      blurRadius: 48,
                      offset: const Offset(0, 20),
                    ),
                  ],
                ),
                child: PortadaLocal(
                  elemento: widget.elemento,
                  lado: MediaQuery.of(context).size.width - 96,
                  radio: 28,
                ),
              ),
            ),
            const Spacer(),
          ],
          Text(
            _sinExtension(widget.elemento.nombre),
            maxLines: 2,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            formatoTamano(widget.elemento.tamano),
            style: const TextStyle(color: Colors.white54),
          ),
          const SizedBox(height: 28),
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
                            style: const TextStyle(color: Colors.white60, fontSize: 12)),
                        Text(formatoTiempo(total.inSeconds),
                            style: const TextStyle(color: Colors.white60, fontSize: 12)),
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
            builder: (BuildContext context, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                _BotonAleatorio(estado: _estado),
                _BotonRepeticion(estado: _estado),
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
                  color: _estado.hayAnterior ? Colors.white70 : Colors.white24,
                  onPressed: _estado.anterior,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                IconButton(
                  iconSize: 30,
                  color: Colors.white70,
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
                  color: Colors.white70,
                  onPressed: () => _estado.saltar(const Duration(seconds: 10)),
                  icon: const Icon(Icons.forward_10),
                ),
                IconButton(
                  iconSize: 30,
                  color: _estado.haySiguiente ? Colors.white70 : Colors.white24,
                  onPressed: _estado.haySiguiente ? _estado.siguiente : null,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BotonGrande extends StatelessWidget {
  const _BotonGrande({required this.sonando, required this.alPulsar});

  final bool sonando;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: alPulsar,
      child: Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          gradient: Tema.degradado,
          shape: BoxShape.circle,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Tema.acento.withValues(alpha: 0.45),
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

  Widget _completo(BuildContext context) {
    return Column(
      children: <Widget>[
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() => _motor.value.isPlaying ? _motor.pause() : _motor.play()),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: AspectRatio(
              aspectRatio: _motor.value.aspectRatio,
              child: VideoPlayer(_motor),
            ),
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: _motor,
            builder: (BuildContext context, VideoPlayerValue valor, _) => Column(
              children: <Widget>[
                Text(
                  _sinExtension(widget.elemento.nombre),
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 14),
                VideoProgressIndicator(
                  _motor,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(playedColor: Tema.acento),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(formatoTiempo(valor.position.inSeconds),
                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                    Text(formatoTiempo(valor.duration.inSeconds),
                        style: const TextStyle(color: Colors.white60, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    IconButton(
                      iconSize: 34,
                      color: Colors.white70,
                      onPressed: () => _motor.seekTo(valor.position - const Duration(seconds: 10)),
                      icon: const Icon(Icons.replay_10),
                    ),
                    const SizedBox(width: 20),
                    _BotonGrande(
                      sonando: valor.isPlaying,
                      alPulsar: () => valor.isPlaying ? _motor.pause() : _motor.play(),
                    ),
                    const SizedBox(width: 20),
                    IconButton(
                      iconSize: 34,
                      color: Colors.white70,
                      onPressed: () => _motor.seekTo(valor.position + const Duration(seconds: 10)),
                      icon: const Icon(Icons.forward_10),
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      iconSize: 26,
                      color: Colors.white54,
                      tooltip: 'Ventana flotante',
                      onPressed: () => Nucleo.pedirVentanaFlotante(
                        ancho: _motor.value.size.width.round(),
                        alto: _motor.value.size.height.round(),
                      ),
                      icon: const Icon(Icons.picture_in_picture_alt_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
    return TextButton.icon(
      onPressed: estado.alternarAleatorio,
      icon: Icon(
        Icons.shuffle_rounded,
        size: 20,
        color: estado.aleatorio ? Tema.acento : Colors.white38,
      ),
      label: Text(
        estado.aleatorio ? 'Aleatorio' : 'En orden',
        style: TextStyle(
          fontSize: 12,
          color: estado.aleatorio ? Tema.acento : Colors.white38,
        ),
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
    return TextButton.icon(
      onPressed: estado.alternarRepeticion,
      icon: Icon(
        estado.repeticion == LoopMode.one
            ? Icons.repeat_one_rounded
            : Icons.repeat_rounded,
        size: 20,
        color: activa ? Tema.acento : Colors.white38,
      ),
      label: Text(
        switch (estado.repeticion) {
          LoopMode.off => 'Sin repetir',
          LoopMode.all => 'Repetir la lista',
          LoopMode.one => 'Repetir esta',
        },
        style: TextStyle(
          fontSize: 12,
          color: activa ? Tema.acento : Colors.white38,
        ),
      ),
    );
  }
}
