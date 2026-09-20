import 'package:flutter/material.dart';

import 'estado_reproductor.dart';
import 'formato.dart';
import 'nucleo.dart';
import 'portadas.dart';
import 'reproductor.dart';
import 'tema.dart';

/// Lo descargado, leido de la biblioteca del telefono.
class PantallaBiblioteca extends StatefulWidget {
  const PantallaBiblioteca({super.key});

  @override
  State<PantallaBiblioteca> createState() => PantallaBibliotecaState();
}

class PantallaBibliotecaState extends State<PantallaBiblioteca> {
  List<Elemento> _elementos = <Elemento>[];
  bool _cargando = true;
  String? _error;
  int _filtro = 0; // 0 todo, 1 musica, 2 video

  @override
  void initState() {
    super.initState();
    recargar();
  }

  Future<void> recargar() async {
    if (mounted) setState(() => _cargando = _elementos.isEmpty);
    try {
      final List<Elemento> elementos = await Nucleo.biblioteca();
      if (!mounted) return;
      setState(() {
        _elementos = elementos;
        _error = null;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _cargando = false;
      });
    }
  }

  List<Elemento> get _visibles => switch (_filtro) {
        1 => _elementos.where((Elemento e) => e.audio).toList(),
        2 => _elementos.where((Elemento e) => !e.audio).toList(),
        _ => _elementos,
      };

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error'));

    final int musica = _elementos.where((Elemento e) => e.audio).length;
    final List<Elemento> visibles = _visibles;

    return RefreshIndicator(
      onRefresh: recargar,
      child: CustomScrollView(
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text('Biblioteca', style: Theme.of(context).textTheme.displaySmall),
                  const SizedBox(height: 4),
                  Text(
                    '$musica pistas  ·  ${_elementos.length - musica} videos',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: <Widget>[
                      for (final (int i, String etiqueta)
                          in <String>['Todo', 'Musica', 'Videos'].indexed)
                        ChoiceChip(
                          label: Text(etiqueta),
                          selected: _filtro == i,
                          onSelected: (_) => setState(() => _filtro = i),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          if (visibles.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.library_music_outlined, size: 56, color: Colors.white24),
                    SizedBox(height: 16),
                    Text(
                      'Aqui no hay nada todavia.\nBaja algo desde la otra pestania.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white54),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList.builder(
              itemCount: visibles.length,
              itemBuilder: (BuildContext context, int i) => _Fila(elemento: visibles[i]),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({required this.elemento});

  final Elemento elemento;

  @override
  Widget build(BuildContext context) {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    return ListenableBuilder(
      listenable: estado,
      builder: (BuildContext context, _) {
        final bool activo = estado.actual?.uri == elemento.uri;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Material(
            color: activo ? Tema.acento.withValues(alpha: 0.14) : Tema.superficie,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (elemento.audio) {
                  estado.reproducir(elemento);
                }
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => Reproductor(elemento: elemento)),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  children: <Widget>[
                    Hero(
                      tag: elemento.uri,
                      child: PortadaLocal(elemento: elemento, lado: 58, radio: 16),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            elemento.nombre,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: <Widget>[
                              Icon(
                                elemento.audio ? Icons.graphic_eq : Icons.movie_outlined,
                                size: 13,
                                color: Colors.white38,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${formatoTiempo(elemento.duracion)}  ·  '
                                '${formatoTamano(elemento.tamano)}',
                                style: const TextStyle(color: Colors.white54, fontSize: 12),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      activo && estado.sonando ? Icons.equalizer_rounded : Icons.play_arrow_rounded,
                      color: activo ? Tema.acento : Colors.white54,
                      size: 28,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
