import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'dialogos.dart';
import 'fuente_anime.dart';
import 'nucleo.dart';
import 'pantalla_web_fuente.dart';
import 'portadas.dart';
import 'tema.dart';
import 'video_pro.dart';

/// Catalogo completo de anime en espanol desde una fuente externa.
///
/// Es una seccion aparte de «gratis y legal»: aqui el catalogo lo pone
/// JKanime. La app solo busca, lista y reproduce lo que esa fuente sirve.
class PantallaFuente extends StatefulWidget {
  const PantallaFuente({super.key});

  @override
  State<PantallaFuente> createState() => _PantallaFuenteState();
}

class _PantallaFuenteState extends State<PantallaFuente> {
  final TextEditingController _texto = TextEditingController();
  Timer? _espera;
  String _busqueda = '';
  int _catalogo = 0; // 0 = populares, 1 = en emision
  late Future<List<AnimeFuente>> _datos = _delCatalogo();

  Future<List<AnimeFuente>> _delCatalogo() =>
      _catalogo == 0 ? FuenteAnime.populares() : FuenteAnime.emision();

  void _cambiarCatalogo(int cual) {
    if (cual == _catalogo) return;
    setState(() {
      _catalogo = cual;
      _datos = _delCatalogo();
    });
  }

  @override
  void dispose() {
    _espera?.cancel();
    _texto.dispose();
    super.dispose();
  }

  /// Se busca al dejar de escribir, no con cada letra.
  void _alEscribir(String texto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      final String limpio = texto.trim();
      setState(() {
        _busqueda = limpio;
        _datos = limpio.isEmpty ? _delCatalogo() : FuenteAnime.buscar(limpio);
      });
    });
  }

  void _reintentar() {
    setState(() {
      _datos = _busqueda.isEmpty ? _delCatalogo() : FuenteAnime.buscar(_busqueda);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Anime en espanol')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              controller: _texto,
              onChanged: _alEscribir,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Busca un anime',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _busqueda.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Borrar',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _texto.clear();
                          _alEscribir('');
                        },
                      ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Fuente: JKanime. Subtitulado y latino.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ),
          if (_busqueda.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: <Widget>[
                  ChoiceChip(
                    label: const Text('Populares'),
                    selected: _catalogo == 0,
                    showCheckmark: false,
                    onSelected: (_) => _cambiarCatalogo(0),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('En emision'),
                    selected: _catalogo == 1,
                    showCheckmark: false,
                    onSelected: (_) => _cambiarCatalogo(1),
                  ),
                ],
              ),
            ),
          Expanded(child: _lista()),
        ],
      ),
    );
  }
  Widget _lista() {
    return FutureBuilder<List<AnimeFuente>>(
      future: _datos,
      builder: (BuildContext context, AsyncSnapshot<List<AnimeFuente>> estado) {
        if (estado.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (estado.hasError) {
          return _Error(mensaje: _textoDe(estado.error), alReintentar: _reintentar);
        }
        final List<AnimeFuente> lista = estado.data ?? const <AnimeFuente>[];
        if (lista.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _busqueda.isEmpty
                    ? 'La fuente no devolvio nada.'
                    : 'No hay ningun anime que se llame «$_busqueda».',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: lista.length,
          itemBuilder: (BuildContext context, int i) => _FilaAnime(anime: lista[i]),
        );
      },
    );
  }
}

class _FilaAnime extends StatelessWidget {
  const _FilaAnime({required this.anime});

  final AnimeFuente anime;

  @override
  Widget build(BuildContext context) {
    final List<String> datos = <String>[
      if (anime.tipo.isNotEmpty) anime.tipo,
      if (anime.estado.isNotEmpty) anime.estado,
    ];
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PantallaFichaFuente(anime: anime),
      )),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: <Widget>[
            PortadaRemota(url: anime.portada, ancho: 84, alto: 118),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    anime.titulo,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, height: 1.25),
                  ),
                  const SizedBox(height: 6),
                  if (datos.isNotEmpty)
                    Text(
                      datos.join('  ·  '),
                      style: const TextStyle(color: Colors.white54, fontSize: 12),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

/// La ficha de un anime de la fuente, con su lista de episodios.
class PantallaFichaFuente extends StatefulWidget {
  const PantallaFichaFuente({required this.anime, super.key});

  final AnimeFuente anime;

  @override
  State<PantallaFichaFuente> createState() => _PantallaFichaFuenteState();
}

class _PantallaFichaFuenteState extends State<PantallaFichaFuente> {
  late Future<List<EpisodioFuente>> _episodios = FuenteAnime.episodios(widget.anime.url);

  void _reintentar() =>
      setState(() => _episodios = FuenteAnime.episodios(widget.anime.url));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.anime.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<List<EpisodioFuente>>(
        future: _episodios,
        builder: (BuildContext context, AsyncSnapshot<List<EpisodioFuente>> estado) {
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: <Widget>[
              _cabecera(),
              if (estado.connectionState != ConnectionState.done)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (estado.hasError)
                _Error(mensaje: _textoDe(estado.error), alReintentar: _reintentar)
              else if ((estado.data ?? const <EpisodioFuente>[]).isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                    'Esta ficha no tiene episodios todavia.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              else
                for (final EpisodioFuente episodio in estado.data!)
                  _FilaEpisodio(episodio: episodio, titulo: widget.anime.titulo),
            ],
          );
        },
      ),
    );
  }

  Widget _cabecera() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PortadaRemota(url: widget.anime.portada, ancho: 104, alto: 148),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.anime.titulo,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, height: 1.15),
                ),
                const SizedBox(height: 6),
                if (widget.anime.tipo.isNotEmpty || widget.anime.estado.isNotEmpty)
                  Text(
                    <String>[
                      if (widget.anime.tipo.isNotEmpty) widget.anime.tipo,
                      if (widget.anime.estado.isNotEmpty) widget.anime.estado,
                    ].join('  ·  '),
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                const SizedBox(height: 12),
                const Text(
                  'Elige un episodio. Despues, dentro, eliges servidor.',
                  style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FilaEpisodio extends StatelessWidget {
  const _FilaEpisodio({required this.episodio, required this.titulo});

  final EpisodioFuente episodio;
  final String titulo;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.play_circle_outline_rounded, color: Tema.acento),
      title: Text('Episodio ${episodio.numero}'),
      subtitle: Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PantallaVerFuente(url: episodio.url, titulo: '$titulo · Ep ${episodio.numero}'),
      )),
    );
  }
}

/// Elige servidor para un episodio y lo reproduce dentro de la app.
class PantallaVerFuente extends StatefulWidget {
  const PantallaVerFuente({required this.url, required this.titulo, super.key});

  final String url;
  final String titulo;

  @override
  State<PantallaVerFuente> createState() => _PantallaVerFuenteState();
}

class _PantallaVerFuenteState extends State<PantallaVerFuente> {
  late Future<List<ServidorFuente>> _servidores = FuenteAnime.servidores(widget.url);
  VideoPlayerController? _motor;
  String? _error;
  bool _cargando = false;

  @override
  void dispose() {
    final VideoPlayerController? motor = _motor;
    if (motor != null) unawaited(motor.dispose());
    super.dispose();
  }

  void _reintentar() => setState(() {
        _servidores = FuenteAnime.servidores(widget.url);
        _error = null;
      });

  Future<void> _abrir(ServidorFuente servidor) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final StreamResuelto resuelto = await FuenteAnime.resolver(servidor.url);
      final VideoPlayerController motor = VideoPlayerController.networkUrl(
        Uri.parse(resuelto.url),
        httpHeaders: resuelto.cabeceras,
        formatHint: resuelto.url.contains('m3u8') ? VideoFormat.hls : null,
      );
      await motor.initialize().timeout(const Duration(seconds: 20));
      if (!mounted) {
        await motor.dispose();
        return;
      }
      await _motor?.dispose();
      setState(() {
        _motor = motor;
        _cargando = false;
      });
      unawaited(motor.play());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = null;
        _cargando = false;
      });
      // No se pudo sacar el enlace directo (o el servidor no lo tiene):
      // se reproduce dentro con el reproductor de la propia web.
      _abrirWeb(servidor);
    }
  }

  /// Reproduce el servidor con su reproductor, dentro de la app (WebView).
  void _abrirWeb(ServidorFuente servidor) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PantallaWebFuente(
        url: servidor.url,
        titulo: '${widget.titulo} · ${servidor.nombre}',
      ),
    ));
  }

  Future<void> _navegador(ServidorFuente servidor) async {
    try {
      await Nucleo.abrirEnlace(servidor.url);
    } on ErrorNucleo catch (error) {
      if (mounted) avisar(context, error.mensaje);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: Column(
        children: <Widget>[
          _reproductor(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFF9E9E)),
                textAlign: TextAlign.center,
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SERVIDORES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: Colors.white54,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Toca uno para verlo. Si el enlace directo no sale, se abre dentro '
                'con el reproductor de la propia web.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ),
          Expanded(child: _listaServidores()),
        ],
      ),
    );
  }

  Widget _reproductor() {
    final VideoPlayerController? motor = _motor;
    if (_cargando) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (motor == null || !motor.value.isInitialized) {
      return const AspectRatio(
        aspectRatio: 16 / 9,
        child: Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Elige un servidor abajo para empezar a ver.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          ),
        ),
      );
    }
    return Expanded(
      child: ReproductorVideo(
        motor: motor,
        titulo: widget.titulo,
        alVentanaFlotante: () => Nucleo.pedirVentanaFlotante(
          ancho: motor.value.size.width.round(),
          alto: motor.value.size.height.round(),
        ),
      ),
    );
  }

  Widget _listaServidores() {
    return FutureBuilder<List<ServidorFuente>>(
      future: _servidores,
      builder: (BuildContext context, AsyncSnapshot<List<ServidorFuente>> estado) {
        if (estado.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (estado.hasError) {
          return _Error(mensaje: _textoDe(estado.error), alReintentar: _reintentar);
        }
        final List<ServidorFuente> lista = estado.data ?? const <ServidorFuente>[];
        if (lista.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Este episodio no tiene servidores todavia.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54),
              ),
            ),
          );
        }
        return ListView.builder(
          itemCount: lista.length,
          itemBuilder: (BuildContext context, int i) {
            final ServidorFuente servidor = lista[i];
            return ListTile(
              leading: const Icon(Icons.dns_outlined, color: Tema.acento),
              title: Text(servidor.nombre),
              subtitle: Text(servidor.idioma),
              trailing: IconButton(
                tooltip: 'Abrir en el navegador',
                icon: const Icon(Icons.open_in_new_rounded),
                onPressed: () => _navegador(servidor),
              ),
              onTap: () => _abrir(servidor),
            );
          },
        );
      },
    );
  }
}

class _Error extends StatelessWidget {
  const _Error({required this.mensaje, required this.alReintentar});

  final String mensaje;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_rounded, size: 44, color: Colors.white38),
            const SizedBox(height: 12),
            Text(mensaje, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 14),
            OutlinedButton(onPressed: alReintentar, child: const Text('Reintentar')),
          ],
        ),
      ),
    );
  }
}

/// Un mensaje entendible para cualquier fallo de la fuente.
String _textoDe(Object? error) => switch (error) {
      ErrorFuente e => e.mensaje,
      ErrorNucleo e => e.mensaje,
      null => 'No se pudo cargar.',
      _ => '$error',
    };
