import 'dart:async';

import 'package:flutter/material.dart';

import 'anime.dart';
import 'animaciones.dart';
import 'canales_oficiales.dart';
import 'nucleo.dart';
import 'pantalla_anime.dart';
import 'pantalla_fuente.dart';
import 'pantalla_serie.dart';
import 'portadas.dart';
import 'tema.dart';

/// Lo que se puede ver en la pestania Ver. Cada seccion es independiente:
/// sumar otra (series, documentales...) es anadirla aqui y su pantalla.
enum SeccionVer {
  anime('Anime', Icons.animation_rounded),
  peliculas('Peliculas', Icons.movie_outlined);

  const SeccionVer(this.titulo, this.icono);

  final String titulo;
  final IconData icono;
}

/// Ver sin descargar: anime de canales oficiales y, pronto, peliculas.
class PantallaVer extends StatefulWidget {
  const PantallaVer({super.key});

  @override
  State<PantallaVer> createState() => _PantallaVerState();
}

class _PantallaVerState extends State<PantallaVer> {
  SeccionVer _seccion = SeccionVer.anime;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            children: <Widget>[
              for (final SeccionVer seccion in SeccionVer.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(seccion.icono, size: 18),
                    label: Text(seccion.titulo),
                    selected: _seccion == seccion,
                    showCheckmark: false,
                    onSelected: (_) => setState(() => _seccion = seccion),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: Movimiento.de(context, Movimiento.medio),
            child: switch (_seccion) {
              SeccionVer.anime => const _SeccionAnime(key: ValueKey<SeccionVer>(SeccionVer.anime)),
              SeccionVer.peliculas =>
                const _PeliculasPronto(key: ValueKey<SeccionVer>(SeccionVer.peliculas)),
            },
          ),
        ),
      ],
    );
  }
}

class _SeccionAnime extends StatefulWidget {
  const _SeccionAnime({super.key});

  @override
  State<_SeccionAnime> createState() => _SeccionAnimeState();
}

class _SeccionAnimeState extends State<_SeccionAnime> {
  final TextEditingController _texto = TextEditingController();
  Timer? _espera;
  String _busqueda = '';
  Future<List<Anime>>? _resultados;

  late Future<List<Resultado>> _series = CanalesOficiales.seriesCompletas();
  late Future<List<Anime>> _temporada = AniList.temporada();
  late Future<List<Anime>> _populares = AniList.populares();

  @override
  void dispose() {
    _espera?.cancel();
    _texto.dispose();
    super.dispose();
  }

  /// Se busca al dejar de escribir, no con cada letra: AniList limita las
  /// consultas por minuto.
  void _alEscribir(String texto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() {
        _busqueda = texto.trim();
        _resultados = _busqueda.isEmpty ? null : AniList.buscar(_busqueda);
      });
    });
  }

  void _reintentar() => setState(() {
        _series = CanalesOficiales.seriesCompletas();
        _temporada = AniList.temporada();
        _populares = AniList.populares();
        if (_busqueda.isNotEmpty) _resultados = AniList.buscar(_busqueda);
      });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
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
        if (_busqueda.isEmpty) ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
            child: _AccesoFuente(),
          ),
          _Fila<Resultado>(
            titulo: 'COMPLETAS Y GRATIS',
            subtitulo: 'Series enteras de canales oficiales',
            datos: _series,
            alto: 176,
            alReintentar: _reintentar,
            construir: (Resultado serie) => _TarjetaSerie(serie: serie),
          ),
          _Fila<Anime>(
            titulo: 'ESTA TEMPORADA',
            datos: _temporada,
            alto: 230,
            alReintentar: _reintentar,
            construir: (Anime anime) => _TarjetaAnime(anime: anime),
          ),
          _Fila<Anime>(
            titulo: 'LOS MAS POPULARES',
            datos: _populares,
            alto: 230,
            alReintentar: _reintentar,
            construir: (Anime anime) => _TarjetaAnime(anime: anime),
          ),
        ] else
          _Resultados(datos: _resultados!, busqueda: _busqueda, alReintentar: _reintentar),
      ],
    );
  }
}

/// Una fila que se desliza a los lados, con su titulo y su estado de carga.
class _Fila<T> extends StatelessWidget {
  const _Fila({
    required this.titulo,
    required this.datos,
    required this.alto,
    required this.construir,
    required this.alReintentar,
    this.subtitulo,
  });

  final String titulo;
  final String? subtitulo;
  final Future<List<T>> datos;
  final double alto;
  final Widget Function(T) construir;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 2),
          child: Text(
            titulo,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Colors.white54,
            ),
          ),
        ),
        if (subtitulo != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
            child: Text(subtitulo!, style: const TextStyle(color: Colors.white38, fontSize: 12)),
          ),
        const SizedBox(height: 8),
        SizedBox(
          height: alto,
          child: FutureBuilder<List<T>>(
            future: datos,
            builder: (BuildContext context, AsyncSnapshot<List<T>> estado) {
              if (estado.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (estado.hasError) {
                return _ErrorFila(error: estado.error!, alReintentar: alReintentar);
              }
              final List<T> lista = estado.data ?? <T>[];
              if (lista.isEmpty) {
                return const Center(
                  child: Text('Nada por aqui ahora mismo.', style: TextStyle(color: Colors.white38)),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: lista.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (BuildContext context, int i) =>
                    AparecerEscalonado(indice: i, child: construir(lista[i])),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ErrorFila extends StatelessWidget {
  const _ErrorFila({required this.error, required this.alReintentar});

  final Object error;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    final String mensaje = error is ErrorCatalogo
        ? (error as ErrorCatalogo).mensaje
        : error is ErrorNucleo
            ? (error as ErrorNucleo).mensaje
            : 'No se pudo cargar.';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(mensaje, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
          TextButton(onPressed: alReintentar, child: const Text('Reintentar')),
        ],
      ),
    );
  }
}

class _TarjetaAnime extends StatelessWidget {
  const _TarjetaAnime({required this.anime, this.ancho = 124});

  final Anime anime;

  /// En las filas es fijo; en la rejilla se reparte el ancho de la pantalla.
  final double ancho;

  @override
  Widget build(BuildContext context) {
    return AlPulsarEncoge(
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => PantallaAnime(anime: anime)),
        ),
        child: SizedBox(
          width: ancho,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Stack(
                children: <Widget>[
                  // Proporcion de caratula (unos 2:3), sea cual sea el ancho.
                  PortadaRemota(url: anime.portada, ancho: ancho, alto: ancho * 1.42),
                  if (anime.nota != null)
                    Positioned(
                      left: 6,
                      top: 6,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              const Icon(Icons.star_rounded, size: 12, color: Color(0xFFFFC857)),
                              const SizedBox(width: 2),
                              Text(
                                '${anime.nota}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                anime.titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.25),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TarjetaSerie extends StatelessWidget {
  const _TarjetaSerie({required this.serie});

  final Resultado serie;

  @override
  Widget build(BuildContext context) {
    return AlPulsarEncoge(
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => PantallaSerie(lista: serie)),
        ),
        child: SizedBox(
          width: 204,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PortadaRemota(url: serie.miniatura, ancho: 204, alto: 115),
              const SizedBox(height: 6),
              Text(
                serie.titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, height: 1.25),
              ),
              Text(
                '${serie.autor} · ${CanalesOficiales.idiomaDe(serie.autor)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white54, fontSize: 11.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lo encontrado al buscar, en rejilla.
class _Resultados extends StatelessWidget {
  const _Resultados({required this.datos, required this.busqueda, required this.alReintentar});

  final Future<List<Anime>> datos;
  final String busqueda;
  final VoidCallback alReintentar;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Anime>>(
      future: datos,
      builder: (BuildContext context, AsyncSnapshot<List<Anime>> estado) {
        if (estado.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.only(top: 48),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (estado.hasError) {
          return SizedBox(height: 200, child: _ErrorFila(error: estado.error!, alReintentar: alReintentar));
        }
        final List<Anime> lista = estado.data ?? const <Anime>[];
        if (lista.isEmpty) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              'No hay ningun anime que se llame «$busqueda».',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          // Tres columnas que llenan el ancho (dos en pantallas muy estrechas):
          // con un ancho fijo sobraba un hueco a la derecha.
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints limites) {
              const double hueco = 10;
              final int columnas = limites.maxWidth >= 330 ? 3 : 2;
              final double ancho = (limites.maxWidth - hueco * (columnas - 1)) / columnas;
              return Wrap(
                spacing: hueco,
                runSpacing: 14,
                children: <Widget>[
                  for (final (int i, Anime anime) in lista.indexed)
                    AparecerEscalonado(indice: i, child: _TarjetaAnime(anime: anime, ancho: ancho)),
                ],
              );
            },
          ),
        );
      },
    );
  }
}

/// El sitio de las peliculas, preparado para lo que viene.
class _PeliculasPronto extends StatelessWidget {
  const _PeliculasPronto({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      children: const <Widget>[
        Icon(Icons.movie_filter_outlined, size: 56, color: Tema.acento),
        SizedBox(height: 14),
        Text(
          'Peliculas: muy pronto',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
        ),
        SizedBox(height: 8),
        Text(
          'Esta seccion se esta preparando. Todo lo que tendra es gratis y legal:',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white60, height: 1.4),
        ),
        SizedBox(height: 22),
        _Pronto(
          icono: Icons.account_balance_outlined,
          titulo: 'Clasicos de dominio publico',
          texto: 'Peliculas de Internet Archive que ya son de todos: verlas y descargarlas.',
        ),
        _Pronto(
          icono: Icons.public_rounded,
          titulo: 'Cine con licencia libre',
          texto: 'Peliculas hechas para compartirse, como las de la Fundacion Blender.',
        ),
        _Pronto(
          icono: Icons.travel_explore_rounded,
          titulo: 'Buscador de cualquier pelicula',
          texto: 'Su ficha, su trailer y en que plataforma se ve en Peru, gratis o de pago.',
        ),
      ],
    );
  }
}

class _Pronto extends StatelessWidget {
  const _Pronto({required this.icono, required this.titulo, required this.texto});

  final IconData icono;
  final String titulo;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(color: Tema.superficie, borderRadius: BorderRadius.circular(16)),
        child: ListTile(
          leading: Icon(icono, color: Tema.acento),
          title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Text(texto, style: const TextStyle(height: 1.35)),
        ),
      ),
    );
  }
}

/// Acceso al catalogo completo en espanol (fuente externa, aparte de la legal).
class _AccesoFuente extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Tema.superficieAlta,
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.language_rounded, color: Tema.acento, size: 30),
        title: const Text('Anime en espanol (catalogo completo)'),
        subtitle: const Text(
          'JKanime: subtitulado y latino. Fuente externa, no oficial.',
          style: TextStyle(height: 1.3),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const PantallaFuente()),
        ),
      ),
    );
  }
}
