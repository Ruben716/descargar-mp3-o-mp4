import 'package:flutter/material.dart';

import 'anime.dart';
import 'animaciones.dart';
import 'canales_oficiales.dart';
import 'dialogos.dart';
import 'nucleo.dart';
import 'pantalla_episodio.dart';
import 'pantalla_serie.dart';
import 'portadas.dart';
import 'tema.dart';

/// La ficha de un anime: de que va y donde verlo gratis y legal.
class PantallaAnime extends StatefulWidget {
  const PantallaAnime({required this.anime, super.key});

  final Anime anime;

  @override
  State<PantallaAnime> createState() => _PantallaAnimeState();
}

class _PantallaAnimeState extends State<PantallaAnime> {
  late final Future<OfertaGratis> _oferta = CanalesOficiales.buscar(widget.anime);
  bool _sinopsisEntera = false;

  Anime get _anime => widget.anime;

  Color get _tono => _anime.color != null ? Color(_anime.color!) : Tema.acento;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            backgroundColor: Tema.fondo,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (_anime.banner.isNotEmpty || _anime.portada.isNotEmpty)
                    Image.network(
                      _anime.banner.isNotEmpty ? _anime.banner : _anime.portada,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(color: _tono.withValues(alpha: 0.3)),
                    ),
                  // Para que el titulo y la flecha se lean sobre cualquier imagen.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[Color(0x66000000), Color(0x00000000), Tema.fondo],
                        stops: <double>[0, 0.45, 1],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(child: _cabecera()),
          SliverToBoxAdapter(child: _sinopsis()),
          SliverToBoxAdapter(child: _gratis()),
          SliverToBoxAdapter(child: _dondeVerla()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _cabecera() {
    final List<String> datos = <String>[
      if (_anime.formatoLegible.isNotEmpty) _anime.formatoLegible,
      if (_anime.anio != null) '${_anime.anio}',
      if (_anime.episodios != null) '${_anime.episodios} ep.',
      if (_anime.estadoLegible.isNotEmpty) _anime.estadoLegible,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          PortadaRemota(url: _anime.portada, ancho: 104, alto: 148),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _anime.titulo,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, height: 1.15),
                ),
                if (_anime.titulo != _anime.romaji) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(_anime.romaji, style: const TextStyle(color: Colors.white54, fontSize: 12.5)),
                ],
                const SizedBox(height: 8),
                Text(datos.join('  ·  '), style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                if (_anime.nota != null) ...<Widget>[
                  const SizedBox(height: 6),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.star_rounded, size: 18, color: Color(0xFFFFC857)),
                      const SizedBox(width: 4),
                      Text('${_anime.nota}%', style: const TextStyle(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sinopsis() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (_anime.generos.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: <Widget>[
                for (final String genero in _anime.generos)
                  Chip(
                    label: Text(genero, style: const TextStyle(fontSize: 12)),
                    visualDensity: VisualDensity.compact,
                    side: BorderSide.none,
                    backgroundColor: _tono.withValues(alpha: 0.16),
                  ),
              ],
            ),
          if (_anime.sinopsis.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            AnimatedSize(
              duration: Movimiento.de(context, Movimiento.medio),
              alignment: Alignment.topCenter,
              child: Text(
                _anime.sinopsis,
                maxLines: _sinopsisEntera ? null : 4,
                overflow: _sinopsisEntera ? null : TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, height: 1.45),
              ),
            ),
            TextButton(
              onPressed: () => setState(() => _sinopsisEntera = !_sinopsisEntera),
              child: Text(_sinopsisEntera ? 'Ver menos' : 'Ver mas'),
            ),
          ],
          if (_anime.trailerYoutube != null)
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => PantallaEpisodio(
                  episodio: Resultado(
                    titulo: 'Trailer de ${_anime.titulo}',
                    autor: 'Trailer oficial',
                    duracion: 0,
                    url: 'https://www.youtube.com/watch?v=${_anime.trailerYoutube}',
                    miniatura: 'https://i.ytimg.com/vi/${_anime.trailerYoutube}/hqdefault.jpg',
                  ),
                ),
              )),
              icon: const Icon(Icons.play_circle_outline_rounded),
              label: const Text('Ver trailer'),
            ),
        ],
      ),
    );
  }

  Widget _gratis() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Titulo('GRATIS Y LEGAL'),
          const SizedBox(height: 4),
          const Text(
            'Solo de canales oficiales de YouTube, subidos por quien tiene los derechos.',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          FutureBuilder<OfertaGratis>(
            future: _oferta,
            builder: (BuildContext context, AsyncSnapshot<OfertaGratis> estado) {
              if (estado.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    children: <Widget>[
                      SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2.5)),
                      SizedBox(width: 14),
                      Text('Buscando en los canales oficiales...', style: TextStyle(color: Colors.white60)),
                    ],
                  ),
                );
              }
              final OfertaGratis oferta = estado.data ?? const OfertaGratis();
              if (oferta.vacia) return const _NoEstaGratis();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (final (int i, Resultado serie) in oferta.series.indexed)
                    AparecerEscalonado(indice: i, child: _FilaSerie(serie: serie)),
                  for (final (int i, Resultado episodio) in oferta.episodios.indexed)
                    AparecerEscalonado(
                      indice: oferta.series.length + i,
                      child: _FilaVideoSuelto(
                        episodio: episodio,
                        siguientes: oferta.episodios.sublist(i + 1),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _dondeVerla() {
    if (_anime.enlaces.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const _Titulo('DONDE VERLA'),
          const SizedBox(height: 4),
          const Text(
            'Plataformas oficiales. Algunas piden suscripcion.',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final EnlaceLegal enlace in _anime.enlaces)
                ActionChip(
                  avatar: const Icon(Icons.open_in_new_rounded, size: 16),
                  label: Text(enlace.sitio),
                  onPressed: () async {
                    try {
                      await Nucleo.abrirEnlace(enlace.url);
                    } on ErrorNucleo catch (error) {
                      if (mounted) avisar(context, error.mensaje);
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Titulo extends StatelessWidget {
  const _Titulo(this.texto);

  final String texto;

  @override
  Widget build(BuildContext context) => Text(
        texto,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Colors.white54,
        ),
      );
}

/// Una serie o temporada entera de un canal oficial.
class _FilaSerie extends StatelessWidget {
  const _FilaSerie({required this.serie});

  final Resultado serie;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Tema.superficieAlta,
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.video_library_rounded, color: Tema.acento, size: 30),
        title: Text(serie.titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text('Lista oficial · ${serie.autor}'),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => PantallaSerie(lista: serie)),
        ),
      ),
    );
  }
}

/// Un episodio suelto, completo, de un canal oficial.
class _FilaVideoSuelto extends StatelessWidget {
  const _FilaVideoSuelto({required this.episodio, required this.siguientes});

  final Resultado episodio;
  final List<Resultado> siguientes;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PantallaEpisodio(episodio: episodio, siguientes: siguientes),
      )),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            PortadaRemota(url: episodio.miniatura, ancho: 120, alto: 68),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(episodio.titulo, maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(episodio.autor, style: const TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoEstaGratis extends StatelessWidget {
  const _NoEstaGratis();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Tema.superficie,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Icon(Icons.info_outline_rounded, color: Colors.white54),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Ahora mismo no esta gratis en los canales oficiales. Los canales '
                'suben y quitan series segun sus licencias: vuelve a mirar mas adelante.',
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
