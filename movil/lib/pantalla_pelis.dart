import 'dart:async';

import 'package:flutter/material.dart';

import 'fuente_pelis.dart';
import 'pantalla_web_fuente.dart';
import 'portadas.dart';
import 'tema.dart';

/// Catalogo de peliculas y series en espanol latino (PelisPlusHD).
///
/// Es la pestania «Peliculas» de Ver. Va sin Scaffold propio: se embebe en la
/// pestania, que ya trae el suyo.
class PantallaPelis extends StatefulWidget {
  const PantallaPelis({super.key});

  @override
  State<PantallaPelis> createState() => _PantallaPelisState();
}

class _PantallaPelisState extends State<PantallaPelis> {
  final TextEditingController _texto = TextEditingController();
  Timer? _espera;
  String _busqueda = '';
  int _seccion = 0; // 0 = peliculas, 1 = series
  late Future<List<Peli>> _datos = _delCatalogo();

  Future<List<Peli>> _delCatalogo() =>
      _seccion == 0 ? FuentePelis.peliculas() : FuentePelis.series();

  @override
  void dispose() {
    _espera?.cancel();
    _texto.dispose();
    super.dispose();
  }

  void _alEscribir(String texto) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      final String limpio = texto.trim();
      setState(() {
        _busqueda = limpio;
        _datos = limpio.isEmpty ? _delCatalogo() : FuentePelis.buscar(limpio);
      });
    });
  }

  void _cambiarSeccion(int cual) {
    if (cual == _seccion) return;
    setState(() {
      _seccion = cual;
      _texto.clear();
      _busqueda = '';
      _datos = _delCatalogo();
    });
  }

  void _reintentar() {
    setState(() {
      _datos = _busqueda.isEmpty ? _delCatalogo() : FuentePelis.buscar(_busqueda);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Peliculas y series')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
            controller: _texto,
            onChanged: _alEscribir,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText: 'Busca una pelicula o serie',
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
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: <Widget>[
              ChoiceChip(
                label: const Text('Peliculas'),
                selected: _seccion == 0,
                showCheckmark: false,
                onSelected: (_) => _cambiarSeccion(0),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Series'),
                selected: _seccion == 1,
                showCheckmark: false,
                onSelected: (_) => _cambiarSeccion(1),
              ),
            ],
          ),
        ),
        Expanded(child: _rejilla()),
        ],
      ),
    );
  }

  Widget _rejilla() {
    return FutureBuilder<List<Peli>>(
      future: _datos,
      builder: (BuildContext context, AsyncSnapshot<List<Peli>> estado) {
        if (estado.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (estado.hasError) {
          return _Error(mensaje: _textoDe(estado.error), alReintentar: _reintentar);
        }
        final List<Peli> lista = estado.data ?? const <Peli>[];
        if (lista.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _busqueda.isEmpty
                    ? 'El catalogo no devolvio nada.'
                    : 'No hay nada que se llame «$_busqueda».',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54),
              ),
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 150,
            crossAxisSpacing: 10,
            mainAxisSpacing: 14,
            childAspectRatio: 0.5,
          ),
          itemCount: lista.length,
          itemBuilder: (BuildContext context, int i) => _TarjetaPeli(peli: lista[i]),
        );
      },
    );
  }
}

class _TarjetaPeli extends StatelessWidget {
  const _TarjetaPeli({required this.peli});

  final Peli peli;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => PantallaDetallePeli(peli: peli),
      )),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: _Portada(url: peli.portada)),
          const SizedBox(height: 6),
          Text(
            peli.titulo,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12, height: 1.2),
          ),
        ],
      ),
    );
  }
}

/// Portada que rellena su hueco (2:3) sin depender de un tamano fijo.
class _Portada extends StatelessWidget {
  const _Portada({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: url.isEmpty
          ? const _SinPortada()
          : Image.network(
              url,
              fit: BoxFit.cover,
              width: double.infinity,
              loadingBuilder: (BuildContext context, Widget hijo, ImageChunkEvent? avance) =>
                  avance == null ? hijo : const _SinPortada(),
              errorBuilder: (_, _, _) => const _SinPortada(),
            ),
    );
  }
}

class _SinPortada extends StatelessWidget {
  const _SinPortada();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Tema.superficie,
      child: Center(child: Icon(Icons.movie_outlined, color: Colors.white24)),
    );
  }
}

/// La ficha de una pelicula o serie: cabecera y luego servidores o capitulos.
class PantallaDetallePeli extends StatefulWidget {
  const PantallaDetallePeli({required this.peli, super.key});

  final Peli peli;

  @override
  State<PantallaDetallePeli> createState() => _PantallaDetallePeliState();
}

class _PantallaDetallePeliState extends State<PantallaDetallePeli> {
  bool get _esSerie => widget.peli.tipo.toLowerCase().contains('serie');

  late Future<List<CapituloPeli>> _capitulos = FuentePelis.capitulos(widget.peli.url);
  late Future<List<ServidorPeli>> _servidores = FuentePelis.servidores(widget.peli.url);
  String? _temporada;

  void _reintentar() {
    setState(() {
      if (_esSerie) {
        _capitulos = FuentePelis.capitulos(widget.peli.url);
      } else {
        _servidores = FuentePelis.servidores(widget.peli.url);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.peli.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          _cabecera(),
          if (_esSerie) _seccionSerie() else _seccionPelicula(),
        ],
      ),
    );
  }

  Widget _cabecera() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          PortadaRemota(url: widget.peli.portada, ancho: 104, alto: 148),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  widget.peli.titulo,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, height: 1.15),
                ),
                const SizedBox(height: 6),
                if (widget.peli.tipo.isNotEmpty)
                  Text(
                    widget.peli.tipo,
                    style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                  ),
                const SizedBox(height: 10),
                const Text(
                  'Elige un servidor y se reproduce dentro de la app.',
                  style: TextStyle(color: Colors.white54, fontSize: 12.5, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _seccionPelicula() {
    return FutureBuilder<List<ServidorPeli>>(
      future: _servidores,
      builder: (BuildContext context, AsyncSnapshot<List<ServidorPeli>> estado) {
        if (estado.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (estado.hasError) {
          return _Error(mensaje: _textoDe(estado.error), alReintentar: _reintentar);
        }
        return _listaServidores(estado.data ?? const <ServidorPeli>[]);
      },
    );
  }

  Widget _seccionSerie() {
    return FutureBuilder<List<CapituloPeli>>(
      future: _capitulos,
      builder: (BuildContext context, AsyncSnapshot<List<CapituloPeli>> estado) {
        if (estado.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (estado.hasError) {
          return _Error(mensaje: _textoDe(estado.error), alReintentar: _reintentar);
        }
        final List<CapituloPeli> todos = estado.data ?? const <CapituloPeli>[];
        if (todos.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Esta serie no tiene capitulos todavia.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54),
            ),
          );
        }
        final List<String> temporadas =
            (todos.map((CapituloPeli c) => c.temporada).toSet().toList()..sort());
        final String actual = _temporada ?? temporadas.first;
        final List<CapituloPeli> visibles =
            todos.where((CapituloPeli c) => c.temporada == actual).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (temporadas.length > 1)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final String t in temporadas)
                      ChoiceChip(
                        label: Text('Temporada $t'),
                        selected: t == actual,
                        showCheckmark: false,
                        onSelected: (_) => setState(() => _temporada = t),
                      ),
                  ],
                ),
              ),
            for (final CapituloPeli capitulo in visibles)
              ListTile(
                leading: const Icon(Icons.play_circle_outline_rounded, color: Tema.acento),
                title: Text('Capitulo ${capitulo.numero}'),
                subtitle: Text(capitulo.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => PantallaServidoresPeli(
                    url: capitulo.url,
                    titulo: '${widget.peli.titulo} · T${capitulo.temporada}E${capitulo.numero}',
                  ),
                )),
              ),
          ],
        );
      },
    );
  }

  Widget _listaServidores(List<ServidorPeli> servidores) {
    if (servidores.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Text(
          'No hay servidores para esto todavia.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54),
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (final ServidorPeli servidor in servidores)
          ListTile(
            leading: const Icon(Icons.dns_outlined, color: Tema.acento),
            title: Text(servidor.nombre),
            trailing: const Icon(Icons.play_circle_outline_rounded),
            onTap: () => abrirEmbed(context, servidor.url, widget.peli.titulo),
          ),
      ],
    );
  }
}

/// Lista de servidores de un capitulo de serie.
class PantallaServidoresPeli extends StatefulWidget {
  const PantallaServidoresPeli({required this.url, required this.titulo, super.key});

  final String url;
  final String titulo;

  @override
  State<PantallaServidoresPeli> createState() => _PantallaServidoresPeliState();
}

class _PantallaServidoresPeliState extends State<PantallaServidoresPeli> {
  late Future<List<ServidorPeli>> _servidores = FuentePelis.servidores(widget.url);

  void _reintentar() => setState(() => _servidores = FuentePelis.servidores(widget.url));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: FutureBuilder<List<ServidorPeli>>(
        future: _servidores,
        builder: (BuildContext context, AsyncSnapshot<List<ServidorPeli>> estado) {
          if (estado.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (estado.hasError) {
            return _Error(mensaje: _textoDe(estado.error), alReintentar: _reintentar);
          }
          final List<ServidorPeli> lista = estado.data ?? const <ServidorPeli>[];
          if (lista.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Este capitulo no tiene servidores todavia.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: lista.length,
            itemBuilder: (BuildContext context, int i) => ListTile(
              leading: const Icon(Icons.dns_outlined, color: Tema.acento),
              title: Text(lista[i].nombre),
              trailing: const Icon(Icons.play_circle_outline_rounded),
              onTap: () => abrirEmbed(context, lista[i].url, widget.titulo),
            ),
          );
        },
      ),
    );
  }
}

/// Abre un embed dentro de la app (en iframe, porque muchos no dejan ser la
/// pagina principal).
void abrirEmbed(BuildContext context, String url, String titulo) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => PantallaWebFuente(url: url, titulo: titulo, enIframe: true),
  ));
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

String _textoDe(Object? error) => switch (error) {
      ErrorPelis e => e.mensaje,
      null => 'No se pudo cargar.',
      _ => '$error',
    };
