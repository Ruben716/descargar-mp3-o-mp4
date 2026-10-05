import 'package:flutter/material.dart';

import 'dialogos.dart';
import 'estado_reproductor.dart';
import 'fila_pista.dart';
import 'formato.dart';
import 'listas.dart';
import 'nucleo.dart';
import 'tema.dart';

/// El contenido de una lista, con su propia pantalla.
///
/// Con muchas listas no caben como fichas en la biblioteca; cada una necesita
/// su sitio, como en cualquier app de musica.
class PantallaLista extends StatefulWidget {
  const PantallaLista({required this.nombre, required this.biblioteca, super.key});

  final String nombre;

  /// Todo lo descargado; de aqui se sacan las pistas que pertenecen a la lista.
  final List<Elemento> biblioteca;

  @override
  State<PantallaLista> createState() => _PantallaListaState();
}

class _PantallaListaState extends State<PantallaLista> {
  final Listas _listas = Listas.instancia;

  List<Elemento> get _pistas {
    final List<String> uris = _listas.contenido(widget.nombre);
    return <Elemento>[
      for (final String uri in uris)
        ...widget.biblioteca.where((Elemento e) => e.uri == uri),
    ];
  }

  /// Quita la cancion de la lista (no del telefono) y deja deshacerlo.
  Future<void> _quitar(Elemento pista) async {
    final int sitio = await _listas.quitar(widget.nombre, pista.uri);
    if (!mounted || sitio < 0) return;
    avisarConDeshacer(
      context,
      'Quitada de «${widget.nombre}»',
      () => _listas.reponer(widget.nombre, pista.uri, sitio),
    );
  }

  Future<void> _reproducirTodo() async {
    final List<Elemento> soloAudio =
        _pistas.where((Elemento e) => e.audio).toList();
    if (soloAudio.isEmpty) return;
    await EstadoReproductor.instancia.reproducirLista(soloAudio, 0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _listas,
      builder: (BuildContext context, _) {
        final List<Elemento> pistas = _pistas;
        final Duration total = Duration(
          seconds: pistas.fold(0, (int s, Elemento e) => s + e.duracion.round()),
        );
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.nombre, overflow: TextOverflow.ellipsis),
            backgroundColor: Colors.transparent,
          ),
          body: pistas.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Text(
                      'Esta lista esta vacia.\nUsa el menu de cada pista para anadirla.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54, height: 1.5),
                    ),
                  ),
                )
              : Column(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              '${pistas.length} pistas  ·  ${formatoTiempo(total.inSeconds)}',
                              style: const TextStyle(color: Colors.white54, fontSize: 12),
                            ),
                          ),
                          FilledButton.icon(
                            onPressed: _reproducirTodo,
                            icon: const Icon(Icons.play_arrow_rounded, size: 20),
                            label: const Text('Reproducir'),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: pistas.length,
                        itemBuilder: (BuildContext context, int i) => FilaPista(
                          elemento: pistas[i],
                          enCola: pistas,
                          acciones: <AccionPista>[
                            AccionPista(
                              icono: Icons.playlist_remove_rounded,
                              texto: 'Quitar de ${widget.nombre}',
                              alElegir: () => _quitar(pistas[i]),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
          backgroundColor: Tema.fondo,
        );
      },
    );
  }
}
