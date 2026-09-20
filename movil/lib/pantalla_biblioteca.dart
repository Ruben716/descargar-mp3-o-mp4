import 'package:flutter/material.dart';

import 'estado_reproductor.dart';
import 'formato.dart';
import 'listas.dart';
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
  final Listas _listas = Listas.instancia;

  List<Elemento> _elementos = <Elemento>[];
  bool _cargando = true;
  String? _error;

  /// 'todo', 'musica', 'videos' o el nombre de una lista.
  String _filtro = 'todo';

  @override
  void initState() {
    super.initState();
    _listas.addListener(_refrescar);
    _listas.cargar();
    recargar();
  }

  @override
  void dispose() {
    _listas.removeListener(_refrescar);
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
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
        'todo' => _elementos,
        'musica' => _elementos.where((Elemento e) => e.audio).toList(),
        'videos' => _elementos.where((Elemento e) => !e.audio).toList(),
        _ => _elementos.where((Elemento e) => _listas.contiene(_filtro, e.uri)).toList(),
      };

  bool get _enLista => !<String>['todo', 'musica', 'videos'].contains(_filtro);

  Future<void> _eliminar(Elemento elemento) async {
    final bool confirmado = await showDialog<bool>(
          context: context,
          builder: (BuildContext contexto) => AlertDialog(
            title: const Text('Eliminar descarga'),
            content: Text('Se borrara "${elemento.nombre}" del telefono.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(contexto).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(contexto).pop(true),
                child: const Text('Eliminar'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmado) return;

    try {
      await Nucleo.eliminar(elemento.uri);
      await EstadoReproductor.instancia.olvidarSiEs(elemento.uri);
      await _listas.olvidar(elemento.uri);
      await recargar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Eliminado'), behavior: SnackBarBehavior.floating),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo eliminar: $error')),
        );
      }
    }
  }

  Future<void> _elegirLista(Elemento elemento) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tema.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (BuildContext contexto) => _HojaListas(elemento: elemento, listas: _listas),
    );
  }

  Future<void> _crearLista() async {
    final String? creada = await showDialog<String>(
      context: context,
      builder: (BuildContext contexto) => const _DialogoNuevaLista(),
    );
    if (creada != null) await _listas.crear(creada);
  }

  Future<void> _borrarLista(String nombre) async {
    await _listas.borrar(nombre);
    if (mounted) setState(() => _filtro = 'todo');
  }

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
                  _filtros(),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
          if (visibles.isEmpty)
            SliverFillRemaining(hasScrollBody: false, child: _vacio())
          else
            SliverList.builder(
              itemCount: visibles.length,
              itemBuilder: (BuildContext context, int i) => _Fila(
                elemento: visibles[i],
                enCola: visibles,
                posicion: i,
                enLista: _enLista ? _filtro : null,
                alEliminar: () => _eliminar(visibles[i]),
                alOrganizar: () => _elegirLista(visibles[i]),
                alQuitarDeLista: _enLista
                    ? () => _listas.alternar(_filtro, visibles[i].uri)
                    : null,
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }

  Widget _filtros() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        for (final (String clave, String etiqueta) in <(String, String)>[
          ('todo', 'Todo'),
          ('musica', 'Musica'),
          ('videos', 'Videos'),
        ])
          ChoiceChip(
            label: Text(etiqueta),
            selected: _filtro == clave,
            onSelected: (_) => setState(() => _filtro = clave),
            selectedColor: Tema.acento.withValues(alpha: 0.28),
            backgroundColor: Tema.superficie,
          ),
        for (final String nombre in _listas.nombres)
          InputChip(
            avatar: const Icon(Icons.queue_music_rounded, size: 17),
            label: Text(nombre),
            selected: _filtro == nombre,
            onSelected: (_) => setState(() => _filtro = nombre),
            // Solo se puede borrar la lista que se esta viendo, para no
            // cargarse otra por un toque descuidado.
            onDeleted: _filtro == nombre ? () => _borrarLista(nombre) : null,
            deleteIcon: const Icon(Icons.close_rounded, size: 16),
            selectedColor: Tema.acento.withValues(alpha: 0.28),
            backgroundColor: Tema.superficie,
          ),
        ActionChip(
          avatar: const Icon(Icons.add_rounded, size: 17),
          label: const Text('Lista'),
          onPressed: _crearLista,
          backgroundColor: Tema.superficieAlta,
        ),
      ],
    );
  }

  Widget _vacio() {
    final bool enLista = _enLista;
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(
            enLista ? Icons.queue_music_rounded : Icons.library_music_outlined,
            size: 56,
            color: Colors.white24,
          ),
          const SizedBox(height: 16),
          Text(
            enLista
                ? 'Esta lista esta vacia.\nUsa el menu de cada pista para anadirla.'
                : 'Aqui no hay nada todavia.\nBaja algo desde la otra pestania.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Fila extends StatelessWidget {
  const _Fila({
    required this.elemento,
    required this.enCola,
    required this.posicion,
    required this.enLista,
    required this.alEliminar,
    required this.alOrganizar,
    required this.alQuitarDeLista,
  });

  final Elemento elemento;

  /// Lo que se ve en pantalla pasa a ser la cola: al tocar una pista, las
  /// siguientes suenan detras sin tener que volver a la lista.
  final List<Elemento> enCola;
  final int posicion;
  final String? enLista;
  final VoidCallback alEliminar;
  final VoidCallback alOrganizar;
  final VoidCallback? alQuitarDeLista;

  @override
  Widget build(BuildContext context) {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    return ListenableBuilder(
      listenable: estado,
      builder: (BuildContext context, _) {
        final bool activo = estado.esActual(elemento.uri);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: Material(
            color: activo ? Tema.acento.withValues(alpha: 0.14) : Tema.superficie,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                if (elemento.audio) {
                  estado.reproducirLista(
                    enCola.where((Elemento e) => e.audio).toList(),
                    enCola.where((Elemento e) => e.audio).toList().indexOf(elemento),
                  );
                }
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => Reproductor(elemento: elemento)),
                );
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
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
                    if (activo && estado.sonando)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.equalizer_rounded, color: Tema.acento, size: 22),
                      ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert_rounded, color: Colors.white54),
                      color: Tema.superficieAlta,
                      onSelected: (String opcion) => switch (opcion) {
                        'listas' => alOrganizar(),
                        'quitar' => alQuitarDeLista?.call(),
                        _ => alEliminar(),
                      },
                      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'listas',
                          child: ListTile(
                            leading: Icon(Icons.playlist_add_rounded),
                            title: Text('Anadir a lista'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                        if (enLista != null)
                          PopupMenuItem<String>(
                            value: 'quitar',
                            child: ListTile(
                              leading: const Icon(Icons.playlist_remove_rounded),
                              title: Text('Quitar de $enLista'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        const PopupMenuItem<String>(
                          value: 'eliminar',
                          child: ListTile(
                            leading: Icon(Icons.delete_outline_rounded, color: Tema.acentoCalido),
                            title: Text('Eliminar descarga'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
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

/// Elige en que listas esta una pista.
class _HojaListas extends StatefulWidget {
  const _HojaListas({required this.elemento, required this.listas});

  final Elemento elemento;
  final Listas listas;

  @override
  State<_HojaListas> createState() => _HojaListasState();
}

class _HojaListasState extends State<_HojaListas> {
  @override
  Widget build(BuildContext context) {
    final List<String> nombres = widget.listas.nombres;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Anadir a lista', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Text(
            widget.elemento.nombre,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 12),
          ),
          const SizedBox(height: 16),
          if (nombres.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Todavia no has creado ninguna lista.\nCierra esto y pulsa "+ Lista".',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white54, height: 1.5),
              ),
            )
          else
            for (final String nombre in nombres)
              CheckboxListTile(
                value: widget.listas.contiene(nombre, widget.elemento.uri),
                onChanged: (_) async {
                  await widget.listas.alternar(nombre, widget.elemento.uri);
                  if (mounted) setState(() {});
                },
                title: Text(nombre),
                activeColor: Tema.acento,
                contentPadding: EdgeInsets.zero,
              ),
        ],
      ),
    );
  }
}


/// Dialogo para crear una lista.
///
/// Es un widget propio a proposito: el controlador del campo tiene que vivir y
/// morir con el. Crearlo en el metodo y liberarlo tras el await lo destruia
/// mientras el dialogo seguia cerrandose con su animacion, y Flutter aborta si
/// un campo de texto sigue usando un controlador ya liberado.
class _DialogoNuevaLista extends StatefulWidget {
  const _DialogoNuevaLista();

  @override
  State<_DialogoNuevaLista> createState() => _DialogoNuevaListaState();
}

class _DialogoNuevaListaState extends State<_DialogoNuevaLista> {
  final TextEditingController _nombre = TextEditingController();

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool valido = _nombre.text.trim().isNotEmpty;
    return AlertDialog(
      backgroundColor: Tema.superficieAlta,
      title: const Text('Nueva lista'),
      content: TextField(
        controller: _nombre,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        onChanged: (_) => setState(() {}),
        onSubmitted: valido ? (String v) => Navigator.of(context).pop(v) : null,
        decoration: const InputDecoration(hintText: 'Por ejemplo: Para correr'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: valido ? () => Navigator.of(context).pop(_nombre.text) : null,
          child: const Text('Crear'),
        ),
      ],
    );
  }
}
