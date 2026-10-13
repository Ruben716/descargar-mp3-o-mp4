import 'package:flutter/material.dart';

import 'estado_reproductor.dart';
import 'fila_pista.dart';
import 'formato.dart';
import 'hecho_para_ti.dart';
import 'nucleo.dart';
import 'pantalla_mix.dart';
import 'portadas.dart';
import 'tema.dart';

/// Agrupa lo descargado por quien lo canta.
///
/// El artista sale del nombre del archivo, que desde que se limpian las
/// etiquetas viene como «Artista - Tema». Lo que no lleve guion se queda en un
/// grupo aparte en vez de inventarle un nombre.
class Artistas {
  const Artistas._();

  static const String sinNombre = 'Sin artista';

  /// El artista de una pista, o [sinNombre] si el nombre no lo dice.
  static String de(Elemento elemento) {
    final String artista = elemento.artista;
    return artista.isEmpty ? sinNombre : artista;
  }

  /// Reparte las pistas por artista, en orden alfabetico y sin tildes.
  ///
  /// «Sin artista» va siempre al final: es un cajon de sastre, no un artista,
  /// y encabezando la lista solo estorbaria.
  static Map<String, List<Elemento>> agrupar(List<Elemento> pistas) {
    final Map<String, List<Elemento>> grupos = <String, List<Elemento>>{};
    for (final Elemento pista in pistas) {
      grupos.putIfAbsent(de(pista), () => <Elemento>[]).add(pista);
    }
    final List<String> nombres = grupos.keys.toList()
      ..sort((String a, String b) {
        if (a == sinNombre) return 1;
        if (b == sinNombre) return -1;
        return sinTildes(a).compareTo(sinTildes(b));
      });
    return <String, List<Elemento>>{for (final String n in nombres) n: grupos[n]!};
  }
}

/// Los discos de un artista: lo que lleva album, agrupado y en su orden.
class Albumes {
  const Albumes._();

  /// Las pistas repartidas por disco y, dentro, por su numero de pista.
  ///
  /// Lo suelto (sin album) va al final y tal cual estaba: no es un disco.
  /// Un «disco» de una sola cancion tampoco: casi siempre es un single.
  static List<({String album, List<Elemento> pistas})> agrupar(List<Elemento> pistas) {
    final Map<String, List<Elemento>> discos = <String, List<Elemento>>{};
    for (final Elemento p in pistas) {
      if (p.album.isNotEmpty) discos.putIfAbsent(p.album, () => <Elemento>[]).add(p);
    }
    discos.removeWhere((String _, List<Elemento> l) => l.length < 2);
    final List<String> nombres = discos.keys.toList()..sort((String a, String b) => sinTildes(a).compareTo(sinTildes(b)));
    final Set<String> enDisco = <String>{for (final List<Elemento> l in discos.values) ...l.map((Elemento e) => e.uri)};
    return <({String album, List<Elemento> pistas})>[
      for (final String n in nombres)
        (album: n, pistas: discos[n]!..sort((Elemento a, Elemento b) => a.pista.compareTo(b.pista))),
      if (pistas.any((Elemento e) => !enDisco.contains(e.uri)))
        (album: '', pistas: pistas.where((Elemento e) => !enDisco.contains(e.uri)).toList()),
    ];
  }
}

/// Todas las pistas de un artista, con sus discos en orden si los tiene.
class PantallaArtista extends StatelessWidget {
  const PantallaArtista({required this.artista, required this.pistas, super.key});

  final String artista;
  final List<Elemento> pistas;

  @override
  Widget build(BuildContext context) {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    return Scaffold(
      appBar: AppBar(
        title: Text(artista, style: const TextStyle(fontSize: 16)),
        actions: <Widget>[
          // Su mix: lo suyo de lo mas oido a lo menos, con Mezcla DJ y la
          // opcion de guardarlo como lista.
          TextButton.icon(
            onPressed: pistas.isEmpty
                ? null
                : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => PantallaMix(
                          mix: HechoParaTi.mixDeArtista(artista, pistas, pistas),
                        ),
                      ),
                    ),
            icon: const Icon(Icons.auto_awesome_rounded, size: 18),
            label: const Text('Mix'),
          ),
          IconButton(
            tooltip: 'Escuchar en aleatorio',
            onPressed: pistas.isEmpty
                ? null
                : () async {
                    await estado.reproducirLista(pistas, 0);
                    if (!estado.aleatorio) await estado.alternarAleatorio();
                  },
            icon: const Icon(Icons.shuffle_rounded),
          ),
        ],
      ),
      body: Builder(builder: (BuildContext context) {
        final List<({String album, List<Elemento> pistas})> grupos = Albumes.agrupar(pistas);
        // Sin discos, la lista de siempre, sin cabeceras que no dicen nada.
        if (grupos.length == 1 && grupos.first.album.isEmpty) {
          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            itemCount: pistas.length,
            itemBuilder: (BuildContext context, int i) => FilaPista(
              elemento: pistas[i],
              enCola: pistas,
            ),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 24),
          children: <Widget>[
            for (final ({String album, List<Elemento> pistas}) g in grupos) ...<Widget>[
              _CabeceraDisco(
                titulo: g.album.isEmpty ? 'Sueltas' : g.album,
                pistas: g.pistas,
                // Un disco se oye en su orden; lo suelto, como venga.
                enOrden: g.album.isNotEmpty,
              ),
              for (final Elemento p in g.pistas) FilaPista(elemento: p, enCola: g.pistas),
            ],
          ],
        );
      }),
    );
  }
}

/// Fila del listado de artistas: la portada de una de sus pistas y cuantas son.
class FilaArtista extends StatelessWidget {
  const FilaArtista({
    required this.artista,
    required this.pistas,
    super.key,
  });

  final String artista;
  final List<Elemento> pistas;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: Tema.superficie,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PantallaArtista(artista: artista, pistas: pistas),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: <Widget>[
                ClipOval(child: PortadaLocal(elemento: pistas.first, lado: 52, radio: 0)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        artista,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        pistas.length == 1 ? '1 cancion' : '${pistas.length} canciones',
                        style: const TextStyle(color: Tema.textoTenue, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Colors.white24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El nombre de un disco, cuanto dura y un boton para oirlo entero.
class _CabeceraDisco extends StatelessWidget {
  const _CabeceraDisco({required this.titulo, required this.pistas, required this.enOrden});

  final String titulo;
  final List<Elemento> pistas;
  final bool enOrden;

  @override
  Widget build(BuildContext context) {
    final int segundos = pistas.fold(0, (int s, Elemento e) => s + e.duracion.round());
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(titulo, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                Text(
                  '${pistas.length} canciones  ·  ${formatoTiempo(segundos)}',
                  style: const TextStyle(color: Tema.textoTenue, fontSize: 11),
                ),
              ],
            ),
          ),
          if (enOrden)
            IconButton(
              tooltip: 'Oir el disco entero',
              icon: const Icon(Icons.album_rounded),
              onPressed: () => EstadoReproductor.instancia.reproducirEnOrden(pistas),
            ),
        ],
      ),
    );
  }
}
