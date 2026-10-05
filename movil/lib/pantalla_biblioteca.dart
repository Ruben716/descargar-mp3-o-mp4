import 'package:flutter/material.dart';

import 'catalogo.dart';
import 'dialogo_etiquetas.dart';
import 'estado_reproductor.dart';
import 'dialogos.dart';
import 'favoritas.dart';
import 'fila_pista.dart';
import 'formato.dart';
import 'hoja_listas.dart';
import 'lista_secciones.dart';
import 'listas.dart';
import 'nucleo.dart';
import 'paleta.dart';
import 'pantalla_artista.dart';
import 'pantalla_lista.dart';
import 'pantalla_lista_auto.dart';
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

/// Que parte de la biblioteca se ve.
enum Seccion {
  canciones('Canciones'),
  artistas('Artistas'),
  videos('Videos'),
  listas('Listas');

  const Seccion(this.etiqueta);

  final String etiqueta;
}

/// Lo descargado, repartido en canciones, artistas, videos y listas.
///
/// Arriba van fichas y no pestanias, como en la biblioteca de Spotify: cuatro
/// pestanias con su cuenta entre parentesis no cabian en un telefono y la
/// ultima quedaba cortada. La cuenta va ahora en el resumen de debajo.
class PantallaBiblioteca extends StatefulWidget {
  const PantallaBiblioteca({super.key});

  @override
  State<PantallaBiblioteca> createState() => PantallaBibliotecaState();
}

class PantallaBibliotecaState extends State<PantallaBiblioteca> {
  final Listas _listas = Listas.instancia;
  final TextEditingController _busqueda = TextEditingController();
  Seccion _seccion = Seccion.canciones;

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
        // Se busca en lo que se ve (artista y tema limpios) y en el archivo.
        .where((Elemento e) => consulta.isEmpty || coincide('${e.etiqueta} ${e.nombre}', consulta))
        .toList();
    switch (_orden) {
      case Orden.reciente:
        break;
      case Orden.alfabetico:
        salida.sort((Elemento a, Elemento b) => sinTildes(a.tema).compareTo(sinTildes(b.tema)));
      case Orden.duracion:
        salida.sort((Elemento a, Elemento b) => b.duracion.compareTo(a.duracion));
    }
    return salida;
  }

  /// Las canciones repartidas por artista, respetando el buscador.
  Map<String, List<Elemento>> get _artistas => Artistas.agrupar(_canciones);

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
      Paleta.olvidar(elemento.uri);
      await EstadoReproductor.instancia.olvidarSiEs(elemento.uri);
      await _listas.olvidar(elemento.uri);
      Favoritas.instancia.olvidar(elemento.uri);
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

  Future<void> _elegirLista(Elemento elemento) => elegirListaPara(context, <Elemento>[elemento]);

  Future<void> _crearLista() async {
    final String? creada = await pedirNombreDeLista(context);
    if (creada != null) await _listas.crear(creada);
  }

  /// Borrar una lista entera pregunta antes, y aun asi se puede deshacer.
  ///
  /// Antes bastaba una «x» pequena junto al nombre, sin preguntar nada.
  Future<void> _borrarLista(String nombre) async {
    final int cuantas = _listas.contenido(nombre).length;
    final bool si = await confirmar(
      context,
      titulo: '¿Eliminar «$nombre»?',
      mensaje: 'Se borra la lista con sus $cuantas ${cuantas == 1 ? 'cancion' : 'canciones'}. '
          'Las canciones no se borran del telefono: siguen en tu biblioteca.',
      accion: 'Eliminar lista',
    );
    if (!si || !mounted) return;
    final List<String> tenia = await _listas.borrar(nombre);
    if (!mounted) return;
    avisarConDeshacer(context, 'Lista «$nombre» eliminada', () => _listas.restaurar(nombre, tenia));
  }

  // --- Seleccion de varias ----------------------------------------------------

  /// Las canciones marcadas, por URI. Vacio fuera del modo seleccion.
  final Set<String> _seleccion = <String>{};

  bool get _seleccionando => _seleccion.isNotEmpty;

  void _alternarSeleccion(Elemento e) => setState(() {
        if (!_seleccion.remove(e.uri)) _seleccion.add(e.uri);
      });

  void _salirDeSeleccion() => setState(_seleccion.clear);

  /// Lo marcado, en el orden en que se ve.
  List<Elemento> _marcadas(List<Elemento> visibles) =>
      visibles.where((Elemento e) => _seleccion.contains(e.uri)).toList();

  List<Elemento> get _visibles => _seccion == Seccion.videos ? _videos : _canciones;

  /// La barra de arriba mientras se elige: cuantas, todas, y que hacer con ellas.
  Widget _barraSeleccion() {
    final List<Elemento> visibles = _visibles;
    final List<Elemento> marcadas = _marcadas(visibles);
    final bool todas = marcadas.length == visibles.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 8, 2),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Cancelar',
            onPressed: _salirDeSeleccion,
            icon: const Icon(Icons.close_rounded),
          ),
          Expanded(
            child: Text(
              '${marcadas.length} ${marcadas.length == 1 ? 'seleccionada' : 'seleccionadas'}',
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
          IconButton(
            tooltip: todas ? 'Quitar todas' : 'Seleccionar todas',
            onPressed: () => setState(() {
              if (todas) {
                _seleccion.clear();
              } else {
                _seleccion.addAll(visibles.map((Elemento e) => e.uri));
              }
            }),
            icon: Icon(todas ? Icons.deselect_rounded : Icons.select_all_rounded),
          ),
          if (_seccion != Seccion.videos) ...<Widget>[
            IconButton(
              tooltip: 'Reproducir las elegidas',
              onPressed: marcadas.isEmpty
                  ? null
                  : () {
                      EstadoReproductor.instancia.reproducirEnOrden(marcadas);
                      _salirDeSeleccion();
                    },
              icon: const Icon(Icons.play_arrow_rounded),
            ),
            IconButton.filledTonal(
              tooltip: 'Anadir a lista',
              onPressed: marcadas.isEmpty
                  ? null
                  : () async {
                      await elegirListaPara(context, marcadas);
                      if (mounted) _salirDeSeleccion();
                    },
              icon: const Icon(Icons.playlist_add_rounded),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _etiquetar(Elemento elemento) async {
    if (await editarEtiquetas(context, elemento)) await recargar();
  }

  List<AccionPista> _accionesDe(Elemento elemento) => <AccionPista>[
    if (elemento.audio)
      AccionPista(
        icono: Favoritas.instancia.contiene(elemento.uri)
            ? Icons.favorite_rounded
            : Icons.favorite_border_rounded,
        texto: Favoritas.instancia.contiene(elemento.uri) ? 'Quitar de Me gusta' : 'Me gusta',
        alElegir: () => Favoritas.instancia.alternar(elemento.uri),
      ),
    AccionPista(
      icono: Icons.playlist_add_rounded,
      texto: 'Anadir a lista',
      alElegir: () => _elegirLista(elemento),
    ),
    // Solo en audio: en video no hay etiquetas que corregir que se vean.
    if (elemento.audio)
      AccionPista(
        icono: Icons.edit_rounded,
        texto: 'Editar etiquetas',
        alElegir: () => _etiquetar(elemento),
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

    return PopScope(
      // Con algo marcado, atras deja de marcar en vez de salir de la pantalla.
      canPop: !_seleccionando,
      onPopInvokedWithResult: (bool salio, _) {
        if (!salio) _salirDeSeleccion();
      },
      child: Column(
      children: <Widget>[
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _seleccionando
              ? KeyedSubtree(key: const ValueKey<String>('seleccion'), child: _barraSeleccion())
              : KeyedSubtree(key: const ValueKey<String>('busqueda'), child: _barraBusqueda()),
        ),
        _fichas(),
        const SizedBox(height: 4),
        Expanded(
          child: switch (_seccion) {
            Seccion.canciones =>
              _pistas(_canciones, 'Aqui apareceran las canciones que descargues.', conBotones: true),
            Seccion.artistas => _seccionArtistas(),
            Seccion.videos => _pistas(_videos, 'Aqui apareceran los videos que descargues.'),
            Seccion.listas => _seccionListas(),
          },
        ),
      ],
      ),
    );
  }

  Widget _fichas() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Row(
        children: <Widget>[
          for (final Seccion s in Seccion.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: _seccion == s,
                showCheckmark: false,
                label: Text(s.etiqueta),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _seccion == s ? Tema.acento : Colors.white70,
                ),
                selectedColor: Tema.acento.withValues(alpha: 0.2),
                backgroundColor: Tema.superficie,
                onSelected: (_) => setState(() {
                  _seccion = s;
                  _seleccion.clear();
                }),
              ),
            ),
        ],
      ),
    );
  }

  /// En que partes se corta la lista segun el orden elegido.
  ///
  /// Por fecha, por tramos de tiempo; de la A a la Z, por letras (y con el
  /// indice para saltar); por duracion no hay nada natural por lo que partir.
  String Function(Elemento)? get _seccionDe => switch (_orden) {
        Orden.reciente => (Elemento e) => seccionPorFecha(e.fecha, DateTime.now()),
        Orden.alfabetico => (Elemento e) => seccionPorLetra(e.tema),
        Orden.duracion => null,
      };

  /// Cuantas son, cuanto duran y cuanto ocupan, en una linea.
  static String resumen(List<Elemento> elementos, {required bool audio}) {
    final int n = elementos.length;
    final double segundos = elementos.fold(0, (double s, Elemento e) => s + e.duracion);
    final int tamano = elementos.fold(0, (int s, Elemento e) => s + e.tamano);
    final int horas = segundos ~/ 3600;
    final int minutos = (segundos % 3600) ~/ 60;
    final String duracion = horas > 0 ? '$horas h $minutos min' : '$minutos min';
    final String que = audio ? (n == 1 ? 'cancion' : 'canciones') : (n == 1 ? 'video' : 'videos');
    return '$n $que · $duracion · ${formatoTamano(tamano)}';
  }

  /// Reproducir, aleatorio y el resumen, encima de las canciones.
  Widget _botones(List<Elemento> canciones) {
    final EstadoReproductor reproductor = EstadoReproductor.instancia;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => reproductor.reproducirEnOrden(canciones),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Reproducir'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => reproductor.reproducirAleatorio(canciones),
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Aleatorio'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            resumen(canciones, audio: true),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ],
      ),
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

  Widget _pistas(List<Elemento> elementos, String vacio, {bool conBotones = false}) {
    if (elementos.isEmpty) {
      if (_busqueda.text.trim().isNotEmpty) {
        return const _Vacio(
          texto: 'Nada con ese nombre.',
          icono: Icons.search_off_rounded,
        );
      }
      return _Vacio(texto: vacio, icono: Icons.library_music_outlined);
    }
    return ListaConSecciones(
      // La clave cambia con el orden: asi la lista vuelve arriba al cambiarlo.
      key: ValueKey<Orden>(_orden),
      elementos: elementos,
      seccionDe: _seccionDe,
      indice: _orden == Orden.alfabetico,
      altoFila: FilaPista.alto,
      cabecera: conBotones && !_seleccionando ? _botones(elementos) : null,
      altoCabecera: conBotones && !_seleccionando ? 88 : 0,
      alRefrescar: recargar,
      fila: (Elemento e) => FilaPista(
        elemento: e,
        enCola: elementos,
        acciones: _accionesDe(e),
        seleccionada: _seleccionando ? _seleccion.contains(e.uri) : null,
        alSeleccionar: () => _alternarSeleccion(e),
        alPulsarLargo: () => _alternarSeleccion(e),
      ),
    );
  }

  Widget _seccionArtistas() {
    final Map<String, List<Elemento>> grupos = _artistas;
    if (grupos.isEmpty) {
      return _Vacio(
        texto: _busqueda.text.trim().isEmpty
            ? 'Aqui se agrupan tus canciones por quien las canta.'
            : 'Nada con ese nombre.',
        icono: Icons.person_outline_rounded,
      );
    }
    final List<String> nombres = grupos.keys.toList();
    return RefreshIndicator(
      onRefresh: recargar,
      child: ListView.builder(
        padding: const EdgeInsets.only(bottom: 20),
        itemCount: nombres.length,
        itemBuilder: (BuildContext context, int i) => FilaArtista(
          artista: nombres[i],
          pistas: grupos[nombres[i]]!,
        ),
      ),
    );
  }

  Widget _seccionListas() {
    final List<String> nombres = _nombresListas;
    return ListView(
      padding: const EdgeInsets.only(bottom: 20),
      children: <Widget>[
        // Las que se hacen solas, en fichas que se deslizan a los lados.
        SizedBox(
          height: 112,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: <Widget>[
              for (final ListaAuto lista in ListaAuto.values)
                _FichaListaAuto(lista: lista, biblioteca: _elementos),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            'TUS LISTAS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: Colors.white54,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: OutlinedButton.icon(
            onPressed: _crearLista,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Nueva lista'),
          ),
        ),
        if (nombres.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(32, 24, 32, 0),
            child: Text(
              'Todavia no tienes listas.\nCrea una, o baja una entera desde un enlace.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white54, height: 1.5),
            ),
          )
        else
          for (final String nombre in nombres)
            _FilaLista(
              nombre: nombre,
              biblioteca: _elementos,
              alBorrar: () => _borrarLista(nombre),
            ),
      ],
    );
  }
}

/// Una lista automatica, como ficha: su icono, su nombre y cuantas tiene.
class _FichaListaAuto extends StatelessWidget {
  const _FichaListaAuto({required this.lista, required this.biblioteca});

  final ListaAuto lista;
  final List<Elemento> biblioteca;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: lista.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PantallaListaAuto(lista: lista, biblioteca: biblioteca),
            ),
          ),
          child: SizedBox(
            width: 128,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Icon(lista.icono, color: lista.color, size: 28),
                  Text(
                    lista.titulo,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, height: 1.2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
                // Escondido en un menu y no a la vista: una «x» suelta junto al
                // nombre se tocaba sin querer y la lista se iba entera.
                PopupMenuButton<String>(
                  tooltip: 'Mas opciones',
                  color: Tema.superficieAlta,
                  icon: const Icon(Icons.more_vert_rounded, color: Colors.white54),
                  onSelected: (_) => alBorrar(),
                  itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'borrar',
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.delete_outline_rounded, color: Color(0xFFFF6B81)),
                          SizedBox(width: 12),
                          Text('Eliminar lista', style: TextStyle(color: Color(0xFFFF6B81))),
                        ],
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
