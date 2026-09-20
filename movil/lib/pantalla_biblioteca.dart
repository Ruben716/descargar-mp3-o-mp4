import 'package:flutter/material.dart';

import 'catalogo.dart';
import 'estado_reproductor.dart';
import 'fila_pista.dart';
import 'formato.dart';
import 'listas.dart';
import 'nucleo.dart';
import 'pantalla_lista.dart';
import 'portadas.dart';
import 'tema.dart';

/// Por que criterio se ordena lo descargado.
enum Orden {
  reciente('Mas reciente'),
  alfabetico('A - Z'),
  duracion('Mas larga');

  const Orden(this.etiqueta);

  final String etiqueta;
}

/// Lo descargado, repartido en canciones, videos y listas.
///
/// Las listas tienen su propia pestania y no fichas sueltas: en cuanto pasan
/// de unas pocas, amontonarlas arriba deja la pantalla inservible.
class PantallaBiblioteca extends StatefulWidget {
  const PantallaBiblioteca({super.key});

  @override
  State<PantallaBiblioteca> createState() => PantallaBibliotecaState();
}

class PantallaBibliotecaState extends State<PantallaBiblioteca>
    with SingleTickerProviderStateMixin {
  final Listas _listas = Listas.instancia;
  late final TabController _pestanas = TabController(length: 3, vsync: this);
  final TextEditingController _busqueda = TextEditingController();

  List<Elemento> _elementos = <Elemento>[];
  Orden _orden = Orden.reciente;
  bool _cargando = true;
  String? _error;

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
    _busqueda.dispose();
    _pestanas.dispose();
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

  List<Elemento> get _canciones => _preparar(audio: true);
  List<Elemento> get _videos => _preparar(audio: false);

  /// Filtra por lo escrito y ordena por el criterio elegido.
  ///
  /// El orden por defecto es el que llega del telefono, que ya viene por fecha
  /// de descarga; por eso "mas reciente" no toca nada.
  List<Elemento> _preparar({required bool audio}) {
    final String consulta = _busqueda.text.trim();
    final List<Elemento> salida = _elementos
        .where((Elemento e) => e.audio == audio)
        .where((Elemento e) => consulta.isEmpty || coincide(e.nombre, consulta))
        .toList();
    switch (_orden) {
      case Orden.reciente:
        break;
      case Orden.alfabetico:
        salida.sort((Elemento a, Elemento b) =>
            sinTildes(nombreLimpio(a.nombre)).compareTo(sinTildes(nombreLimpio(b.nombre))));
      case Orden.duracion:
        salida.sort((Elemento a, Elemento b) => b.duracion.compareTo(a.duracion));
    }
    return salida;
  }

  /// Los nombres de lista que casan con la busqueda.
  List<String> get _nombresListas {
    final String consulta = _busqueda.text.trim();
    final List<String> nombres = _listas.nombres;
    if (consulta.isEmpty) return nombres;
    return nombres.where((String n) => coincide(n, consulta)).toList();
  }

  Future<void> _eliminar(Elemento elemento) async {
    final bool confirmado = await showDialog<bool>(
          context: context,
          builder: (BuildContext contexto) => AlertDialog(
            backgroundColor: Tema.superficieAlta,
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
      // La portada guardada ya no vale para nada y ocupa memoria.
      Nucleo.olvidarCaratula(elemento.uri);
      await EstadoReproductor.instancia.olvidarSiEs(elemento.uri);
      await _listas.olvidar(elemento.uri);
      // Sin esto el catalogo seguiria creyendo que la tenemos y no se
      // volveria a descargar nunca.
      await Catalogo.instancia.olvidar(elemento.uri);
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

  List<AccionPista> _accionesDe(Elemento elemento) => <AccionPista>[
    AccionPista(
      icono: Icons.playlist_add_rounded,
      texto: 'Anadir a lista',
      alElegir: () => _elegirLista(elemento),
    ),
    AccionPista(
      icono: Icons.delete_outline_rounded,
      texto: 'Eliminar descarga',
      alElegir: () => _eliminar(elemento),
      destacada: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Error: $_error'));

    return Column(
      children: <Widget>[
        _barraBusqueda(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: TabBar(
            controller: _pestanas,
            dividerColor: Colors.transparent,
            indicatorSize: TabBarIndicatorSize.tab,
            indicator: BoxDecoration(
              color: Tema.acento.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14),
            ),
            labelColor: Tema.acento,
            unselectedLabelColor: Colors.white54,
            labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: <Widget>[
              Tab(text: 'Canciones (${_canciones.length})'),
              Tab(text: 'Videos (${_videos.length})'),
              Tab(text: 'Listas (${_nombresListas.length})'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TabBarView(
            controller: _pestanas,
            children: <Widget>[
              _pistas(_canciones, 'Aqui apareceran las canciones que descargues.'),
              _pistas(_videos, 'Aqui apareceran los videos que descargues.'),
              _seccionListas(),
            ],
          ),
        ),
      ],
    );
  }

  /// Buscador y orden. Van fuera de las pestanias porque valen para las tres.
  Widget _barraBusqueda() {
    final bool buscando = _busqueda.text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _busqueda,
              textInputAction: TextInputAction.search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar en lo que tienes',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                isDense: true,
                suffixIcon: buscando
                    ? IconButton(
                        onPressed: () {
                          _busqueda.clear();
                          setState(() {});
                        },
                        icon: const Icon(Icons.close_rounded, size: 18),
                      )
                    : null,
              ),
            ),
          ),
          PopupMenuButton<Orden>(
            tooltip: 'Ordenar',
            color: Tema.superficieAlta,
            icon: Icon(
              Icons.swap_vert_rounded,
              color: _orden == Orden.reciente ? Colors.white54 : Tema.acento,
            ),
            onSelected: (Orden elegido) => setState(() => _orden = elegido),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<Orden>>[
              for (final Orden opcion in Orden.values)
                CheckedPopupMenuItem<Orden>(
                  value: opcion,
                  checked: _orden == opcion,
                  child: Text(opcion.etiqueta),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pistas(List<Elemento> elementos, String vacio) {
    if (elementos.isEmpty) {
      if (_busqueda.text.trim().isNotEmpty) {
        return const _Vacio(
          texto: 'Nada con ese nombre.',
          icono: Icons.search_off_rounded,
        );
      }
      return _Vacio(texto: vacio, icono: Icons.library_music_outlined);
    }
    return RefreshIndicator(
      onRefresh: recargar,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: elementos.length,
        itemBuilder: (BuildContext context, int i) => FilaPista(
          elemento: elementos[i],
          enCola: elementos,
          acciones: _accionesDe(elementos[i]),
        ),
      ),
    );
  }

  Widget _seccionListas() {
    final List<String> nombres = _nombresListas;
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _crearLista,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Nueva lista'),
            ),
          ),
        ),
        Expanded(
          child: nombres.isEmpty
              ? const _Vacio(
                  texto: 'Todavia no tienes listas.\n'
                      'Crea una, o baja una entera desde un enlace.',
                  icono: Icons.queue_music_rounded,
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: nombres.length,
                  itemBuilder: (BuildContext context, int i) => _FilaLista(
                    nombre: nombres[i],
                    biblioteca: _elementos,
                    alBorrar: () => _listas.borrar(nombres[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

/// Una lista en el listado: portada de su primera pista y cuantas tiene.
class _FilaLista extends StatelessWidget {
  const _FilaLista({
    required this.nombre,
    required this.biblioteca,
    required this.alBorrar,
  });

  final String nombre;
  final List<Elemento> biblioteca;
  final VoidCallback alBorrar;

  @override
  Widget build(BuildContext context) {
    final List<String> uris = Listas.instancia.contenido(nombre);
    final List<Elemento> pistas =
        biblioteca.where((Elemento e) => uris.contains(e.uri)).toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
      child: Material(
        color: Tema.superficie,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PantallaLista(nombre: nombre, biblioteca: biblioteca),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: <Widget>[
                if (pistas.isEmpty)
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      gradient: Tema.degradado,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.queue_music_rounded, color: Colors.black38),
                  )
                else
                  PortadaLocal(elemento: pistas.first, lado: 52, radio: 14),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        nombre,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${pistas.length} pistas',
                        style: const TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: alBorrar,
                  tooltip: 'Borrar la lista',
                  icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white38),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.texto, required this.icono});

  final String texto;
  final IconData icono;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(icono, size: 52, color: Colors.white24),
          const SizedBox(height: 14),
          Text(
            texto,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, height: 1.5),
          ),
        ],
      ),
    ),
  );
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
                'Todavia no has creado ninguna lista.\n'
                    'Cierra esto y crea una en la pestania Listas.',
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
/// morir con el. Crearlo fuera y liberarlo tras el await lo destruia mientras
/// el dialogo seguia cerrandose, y Flutter aborta por ello.
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
