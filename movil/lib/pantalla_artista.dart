import 'package:flutter/material.dart';

import 'estado_reproductor.dart';
import 'fila_pista.dart';
import 'formato.dart';
import 'nucleo.dart';
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

/// Todas las pistas de un artista.
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
      body: ListView.builder(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        itemCount: pistas.length,
        itemBuilder: (BuildContext context, int i) => FilaPista(
          elemento: pistas[i],
          enCola: pistas,
        ),
      ),
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
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
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
