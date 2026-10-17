import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'calidad.dart';
import 'catalogo.dart';
import 'descubre.dart';
import 'estado_reproductor.dart';
import 'favoritas.dart';
import 'formato.dart';
import 'hecho_para_ti.dart';
import 'listas.dart';
import 'nucleo.dart';
import 'pantalla_ajustes.dart';
import 'pantalla_descubre.dart';
import 'pantalla_explorar.dart';
import 'pantalla_lista.dart';
import 'pantalla_lista_auto.dart';
import 'pantalla_mix.dart';
import 'pantalla_previa.dart';
import 'pantalla_radio.dart';
import 'portadas.dart';
import 'posiciones.dart';
import 'radio_mundial.dart';
import 'reproductor.dart';
import 'ritmos.dart';
import 'secciones_inicio.dart';
import 'tema.dart';

/// Pantalla de entrada de la app.
///
/// Sigue lo que hacen las apps de musica: al abrir no se pide nada al usuario,
/// se le ofrece seguir donde lo dejo y lo que tiene a mano. Arriba lo personal
/// y de un toque (Pidele, los accesos, continuar), en medio lo que arma la app
/// (los mixes) y abajo lo de siempre. El formulario de descarga vive en su
/// pestania, que es donde se va a buscar algo nuevo.
///
/// Lo que sale del catalogo se pide sin esperarlo y no ocupa nada hasta que
/// llega: nada de ruedas girando, que en las pruebas el catalogo no responde
/// con el reloj de mentira y la pantalla nunca quedaria en reposo.
class PantallaInicio extends StatefulWidget {
  const PantallaInicio({
    required this.alIrADescargar,
    required this.alIrABiblioteca,
    super.key,
  });

  final VoidCallback alIrADescargar;
  final VoidCallback alIrABiblioteca;

  @override
  State<PantallaInicio> createState() => PantallaInicioState();
}

class PantallaInicioState extends State<PantallaInicio> {
  final Listas _listas = Listas.instancia;
  final EstadoReproductor _reproductor = EstadoReproductor.instancia;
  final RadiosFavoritas _radios = RadiosFavoritas.instancia;
  final Favoritas _favoritas = Favoritas.instancia;
  final Ritmos _ritmos = Ritmos.instancia;
  final Descubre _descubre = Descubre.instancia;

  List<Elemento> _elementos = <Elemento>[];

  /// Lo mas oido, de la pista mas escuchada a la que menos.
  List<Elemento> _masOidas = <Elemento>[];
  bool _cargando = true;

  /// Cada recarga lleva su numero: lo que llegue tarde de una anterior se tira.
  int _carga = 0;

  /// Mix diario, Redescubre... Vacio hasta que llegan las escuchas.
  List<Mix> _hechoParaTi = <Mix>[];

  /// Un «Mix de ...» por cada artista con canciones de sobra.
  List<Mix> _mixesArtista = <Mix>[];

  /// Lo que llego sin perdida, de lo ultimo a lo primero.
  List<Elemento> _sinPerdida = <Elemento>[];

  /// La calidad de origen de lo que se ensenia con sello.
  Map<String, CalidadAudio> _calidades = <String, CalidadAudio>{};

  /// Audios largos a medias, de lo ultimo que sono a lo mas antiguo.
  List<({Elemento elemento, Duration posicion})> _aMedias = <({Elemento elemento, Duration posicion})>[];

  // Los mixes de animo se rehacen solo si cambia lo analizado o la biblioteca.
  List<Mix> _animo = <Mix>[];
  int _animoAnalizadas = -1;
  List<Elemento>? _animoDe;

  @override
  void initState() {
    super.initState();
    _listas.addListener(_refrescar);
    _reproductor.addListener(_refrescar);
    _radios.addListener(_refrescar);
    _favoritas.addListener(_refrescar);
    _ritmos.addListener(_alCambiarRitmos);
    _descubre.addListener(_refrescar);
    _listas.cargar();
    // Lo guardado, no la red: se rehace de fondo una vez por semana.
    unawaited(_descubre.cargar());
    // De la memoria del telefono, no del catalogo: no hace esperar a nada.
    unawaited(_radios.cargar());
    recargar();
  }

  @override
  void dispose() {
    _listas.removeListener(_refrescar);
    _reproductor.removeListener(_refrescar);
    _radios.removeListener(_refrescar);
    _favoritas.removeListener(_refrescar);
    _ritmos.removeListener(_alCambiarRitmos);
    _descubre.removeListener(_refrescar);
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  /// El analisis avisa a menudo (cada cancion que empieza y acaba); solo se
  /// redibuja cuando de verdad hay una analizada mas.
  void _alCambiarRitmos() {
    if (mounted && _ritmos.analizadas != _animoAnalizadas) setState(() {});
  }

  /// Lee la biblioteca una sola vez y lanza a la vez todo lo demas.
  Future<void> recargar() async {
    final int esta = ++_carga;
    try {
      final List<Elemento> elementos = await Nucleo.biblioteca();
      if (!mounted || esta != _carga) return;
      setState(() {
        _elementos = elementos;
        _cargando = false;
      });
      // Lo demas va aparte y sin esperarlo: la pantalla no puede quedarse en
      // blanco por una consulta que solo sirve para un carrusel.
      unawaited(_cargarMasOidas(elementos, esta));
      unawaited(_cargarEscuchas(elementos, esta));
      unawaited(_cargarSinPerdida(elementos, esta));
      unawaited(_cargarCalidades(elementos.take(10), esta));
      unawaited(_cargarAMedias(elementos, esta));
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  bool _vigente(int esta) => mounted && esta == _carga;

  Future<void> _cargarMasOidas(List<Elemento> biblioteca, int esta) async {
    final List<Elemento> masOidas = await _ordenarPorEscuchas(biblioteca);
    if (_vigente(esta)) setState(() => _masOidas = masOidas);
  }

  /// Cruza el recuento de escuchas con lo que sigue en el telefono.
  ///
  /// Puede quedar corto o vacio: se cuentan las pistas que se han oido de
  /// verdad, y las que se borraron ya no estan en la biblioteca.
  static Future<List<Elemento>> _ordenarPorEscuchas(List<Elemento> biblioteca) async {
    try {
      final List<({String uri, int veces})> recuento =
          await Catalogo.instancia.masEscuchadas();
      final Map<String, Elemento> porUri = <String, Elemento>{
        for (final Elemento e in biblioteca) e.uri: e,
      };
      return <Elemento>[
        for (final ({String uri, int veces}) fila in recuento)
          if (porUri[fila.uri] != null) porUri[fila.uri]!,
      ];
    } catch (_) {
      // Quedarse sin estadisticas no puede dejar la pantalla en blanco.
      return <Elemento>[];
    }
  }

  /// Hecho para ti y los mixes de artista, con la semilla del dia: no
  /// cambian en cada recarga, solo de un dia a otro.
  Future<void> _cargarEscuchas(List<Elemento> biblioteca, int esta) async {
    Map<String, Escucha> escuchas = <String, Escucha>{};
    try {
      escuchas = await Catalogo.instancia.escuchasConFecha();
    } catch (_) {
      // Sin escuchas salen igual, por cuantas canciones tiene cada artista.
    }
    if (!_vigente(esta)) return;
    final DateTime ahora = DateTime.now();
    final int semilla = HechoParaTi.semillaDelDia(ahora);
    final Set<String> favoritas = <String>{
      for (final Elemento e in biblioteca)
        if (_favoritas.contiene(e.uri)) e.uri,
    };
    setState(() {
      _hechoParaTi = HechoParaTi.armar(
        biblioteca,
        escuchas: escuchas,
        favoritas: favoritas,
        ahora: ahora,
        azar: Random(semilla),
      );
      _mixesArtista = HechoParaTi.mixesDeArtista(
        biblioteca,
        escuchas: escuchas,
        favoritas: favoritas,
        azar: Random(semilla + 1),
      );
    });
  }

  Future<void> _cargarSinPerdida(List<Elemento> biblioteca, int esta) async {
    try {
      final List<String> uris = await Catalogo.instancia.sinPerdida();
      final Map<String, Elemento> porUri = <String, Elemento>{
        for (final Elemento e in biblioteca)
          if (e.audio) e.uri: e,
      };
      final List<Elemento> enteras = <Elemento>[for (final String u in uris) ?porUri[u]];
      if (!_vigente(esta)) return;
      setState(() => _sinPerdida = enteras);
      await _cargarCalidades(enteras.take(20), esta);
    } catch (_) {
      // Sin la tabla de calidades no hay estante: no pasa nada mas.
    }
  }

  /// La calidad de origen de [pistas], para sus sellos.
  Future<void> _cargarCalidades(Iterable<Elemento> pistas, int esta) async {
    try {
      final List<Elemento> cuales = pistas.toList();
      final List<CalidadAudio?> halladas =
          await Future.wait(cuales.map((Elemento e) => Catalogo.instancia.calidadDe(e.uri)));
      if (!_vigente(esta)) return;
      setState(() {
        _calidades = <String, CalidadAudio>{
          ..._calidades,
          for (int i = 0; i < cuales.length; i++)
            if (halladas[i] case final CalidadAudio c) cuales[i].uri: c,
        };
      });
    } catch (_) {
      // Sin sello, la tarjeta sale igual.
    }
  }

  Future<void> _cargarAMedias(List<Elemento> biblioteca, int esta) async {
    final Map<String, Duration> posiciones = await Posiciones.audio.todas();
    final Map<String, Elemento> largos = <String, Elemento>{
      for (final Elemento e in biblioteca)
        if (e.audio && e.duracion >= EstadoReproductor.largo.inSeconds) e.uri: e,
    };
    if (!_vigente(esta)) return;
    setState(() {
      _aMedias = <({Elemento elemento, Duration posicion})>[
        for (final MapEntry<String, Duration> p in posiciones.entries)
          if (largos[p.key] case final Elemento e) (elemento: e, posicion: p.value),
      ];
    });
  }

  /// Para moverse, Tranqui, Para concentrarte y Sesion DJ, si el DJ ya
  /// analizo bastante. Sale de la memoria, no del catalogo.
  List<Mix> get _mixesAnimo {
    final int analizadas = _ritmos.analizadas;
    if (analizadas != _animoAnalizadas || !identical(_animoDe, _elementos)) {
      _animoAnalizadas = analizadas;
      _animoDe = _elementos;
      _animo = analizadas < HechoParaTi.minimoAnalizadas
          ? <Mix>[]
          : HechoParaTi.mixesPorAnimo(
              _elementos,
              percentil: _ritmos.percentil,
              rasgos: _ritmos.rasgosDe,
              azar: Random(HechoParaTi.semillaDelDia(DateTime.now()) + 2),
            );
    }
    return _animo;
  }

  static String get _saludo {
    final int hora = DateTime.now().hour;
    if (hora < 6) return 'Buenas noches';
    if (hora < 13) return 'Buenos dias';
    if (hora < 21) return 'Buenas tardes';
    return 'Buenas noches';
  }

  /// Lo que estaba sonando, o lo ultimo descargado si aun no hubo nada.
  Elemento? get _continuar {
    final Elemento? sonando = _reproductor.actual?.elemento;
    if (sonando != null) return sonando;
    final Iterable<Elemento> audios = _elementos.where((Elemento e) => e.audio);
    return audios.isEmpty ? null : audios.first;
  }

  void _abrir(Widget pantalla) => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => pantalla),
      );

  void _abrirExplorar() => _abrir(const PantallaExplorar());

  void _abrirMix(Mix mix) => _abrir(PantallaMix(mix: mix));

  void _abrirListaAuto(ListaAuto lista) => _abrir(PantallaListaAuto(lista: lista, biblioteca: _elementos));

  /// Pone a sonar [elemento] con [cola] detras y abre el reproductor.
  void _oir(Elemento elemento, List<Elemento> cola) {
    if (elemento.audio) unawaited(_reproductor.reproducirLista(cola, max(0, cola.indexOf(elemento))));
    _abrir(Reproductor(elemento: elemento, arrancar: !elemento.audio));
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    final List<String> listas = _listas.nombres;
    final List<Elemento> canciones = _elementos.where((Elemento e) => e.audio).toList();
    final List<Mix> tusMixes = <Mix>[..._mixesArtista, ..._mixesAnimo];

    return RefreshIndicator(
      onRefresh: recargar,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          // El destello va con la cabecera y no fijo detras de la lista: asi
          // sube con ella al desplazar y se funde, como en YouTube Music.
          Resplandor(hijo: _cabecera(context, canciones.length, listas.length)),
          if (_elementos.isEmpty) ...<Widget>[
            _primerosPasos(context),
            _radioEnVivo(context),
            TarjetaFila(
              icono: Icons.explore_rounded,
              titulo: 'Descubre algo nuevo',
              subtitulo: 'Radio, podcasts y musica libre para empezar',
              alPulsar: _abrirExplorar,
            ),
          ] else ...<Widget>[
            const PastillaPidele(),
            RejillaAccesos(accesos: _accesos(canciones)),
            if (_continuar != null) _continuarEscuchando(context, _continuar!),
            if (_hechoParaTi.isNotEmpty) _estanteMixes('Hecho para ti', _hechoParaTi),
            if (_descubre.pistas.isNotEmpty) _carruselDescubre(),
            _recienDescargado(canciones),
            if (tusMixes.isNotEmpty) _estanteMixes('Tus mixes', tusMixes),
            if (_radios.todas.isNotEmpty) _radioFavorita(),
            _radioEnVivo(context),
            if (_masOidas.length >= 3) _carruselMasOidas(context),
            if (_sinPerdida.isNotEmpty) _carruselSinPerdida(),
            if (_aMedias.isNotEmpty) _carruselAMedias(),
            if (listas.isNotEmpty) _carruselListas(context, listas),
            TarjetaFila(
              icono: Icons.explore_rounded,
              titulo: 'Explora radio, podcasts y musica libre',
              subtitulo: 'Emisoras en vivo, programas y donde hay sin perdida',
              alPulsar: _abrirExplorar,
            ),
          ],
        ],
      ),
    );
  }

  Widget _cabecera(BuildContext context, int canciones, int listas) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 12, 18),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _saludo,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 26),
                ),
                const SizedBox(height: 4),
                Text(
                  _elementos.isEmpty
                      ? 'Tu biblioteca esta vacia'
                      : '$canciones canciones  ·  $listas listas',
                  style: const TextStyle(color: Colors.white54, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _abrirExplorar,
            tooltip: 'Explorar',
            icon: const Icon(Icons.explore_outlined),
          ),
          IconButton(
            onPressed: () => _abrir(const PantallaAjustes()),
            tooltip: 'Ajustes',
            icon: const Icon(Icons.settings_outlined),
          ),
          const SizedBox(width: 4),
          IconButton.filledTonal(
            onPressed: widget.alIrADescargar,
            tooltip: 'Buscar algo nuevo',
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
    );
  }

  /// Sin nada descargado no hay atajos que ofrecer: se explica que hacer.
  Widget _primerosPasos(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
      child: Column(
        children: <Widget>[
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: Tema.degradado,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Icon(Icons.music_note_rounded, size: 46, color: Color(0x73040814)),
          ),
          const SizedBox(height: 22),
          Text(
            'Empieza tu biblioteca',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20),
          ),
          const SizedBox(height: 8),
          const Text(
            'Busca una cancion, escuchala antes de\nbajarla, o pega el enlace de una lista entera.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white54, height: 1.5),
          ),
          const SizedBox(height: 22),
          BotonDegradado(
            texto: 'Buscar musica',
            icono: Icons.search_rounded,
            alPulsar: widget.alIrADescargar,
          ),
        ],
      ),
    );
  }

  /// Las fichas de arriba: lo que se abre a menudo, a un toque.
  ///
  /// Las vacias no salen; sin ninguna, la rejilla no ocupa nada.
  List<AccesoRapido> _accesos(List<Elemento> canciones) {
    final List<Elemento> gustan = <Elemento>[
      for (final Elemento e in canciones)
        if (_favoritas.contiene(e.uri)) e,
    ];
    // La ultima lista creada que tenga algo de lo que hay en el telefono.
    final Map<String, Elemento> porUri = <String, Elemento>{for (final Elemento e in _elementos) e.uri: e};
    ({String nombre, List<Elemento> pistas})? ultima;
    for (final MapEntry<String, List<String>> l in _listas.todas.entries) {
      final List<Elemento> pistas = <Elemento>[for (final String u in l.value) ?porUri[u]];
      if (pistas.isNotEmpty) ultima = (nombre: l.key, pistas: pistas);
    }
    final List<EstacionRadio> emisoras = _radios.todas;
    final EstacionRadio? radio = emisoras.isEmpty ? null : emisoras.first;
    final Mix? mix = _mixesArtista.isEmpty ? null : _mixesArtista.first;
    final ({String nombre, List<Elemento> pistas})? lista = ultima;
    return <AccesoRapido>[
      if (gustan.isNotEmpty)
        AccesoRapido(
          titulo: 'Tus me gusta',
          portada: const CuadroIcono(icono: Icons.favorite_rounded, lado: RejillaAccesos.alto, radio: 0),
          alPulsar: () => _abrirListaAuto(ListaAuto.meGusta),
        ),
      if (_masOidas.isNotEmpty)
        AccesoRapido(
          titulo: ListaAuto.masEscuchadas.titulo,
          portada: const CuadroIcono(icono: Icons.trending_up_rounded, lado: RejillaAccesos.alto, radio: 0),
          alPulsar: () => _abrirListaAuto(ListaAuto.masEscuchadas),
        ),
      if (_sinPerdida.isNotEmpty)
        AccesoRapido(
          titulo: ListaAuto.sinPerdida.titulo,
          portada: const CuadroIcono(icono: Icons.graphic_eq_rounded, lado: RejillaAccesos.alto, radio: 0),
          alPulsar: () => _abrirListaAuto(ListaAuto.sinPerdida),
        ),
      if (lista != null)
        AccesoRapido(
          titulo: lista.nombre,
          portada: MosaicoPortadas(pistas: lista.pistas, lado: RejillaAccesos.alto, radio: 0),
          alPulsar: () => _abrir(PantallaLista(nombre: lista.nombre, biblioteca: _elementos)),
        ),
      if (radio != null)
        AccesoRapido(
          titulo: radio.nombre,
          portada: LogoEmisora(emisora: radio, lado: RejillaAccesos.alto),
          activo: _reproductor.actual?.enVivo?.url == radio.url,
          alPulsar: () => _reproductor.reproducirEmisora(radio),
        ),
      if (mix != null)
        AccesoRapido(
          titulo: mix.titulo,
          portada: MosaicoPortadas(pistas: mix.pistas, lado: RejillaAccesos.alto, radio: 0),
          alPulsar: () => _abrirMix(mix),
        ),
    ];
  }

  Widget _continuarEscuchando(BuildContext context, Elemento elemento) {
    final bool sonando = _reproductor.esActual(elemento.uri) && _reproductor.sonando;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
      child: Material(
        color: Tema.superficie,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _abrir(Reproductor(elemento: elemento)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                PortadaLocal(elemento: elemento, lado: 62, radio: 16),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        sonando ? 'SONANDO AHORA' : 'CONTINUAR ESCUCHANDO',
                        style: Tema.antetitulo,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        elemento.etiqueta,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    gradient: Tema.degradado,
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: () => _reproductor.esActual(elemento.uri)
                        ? _reproductor.alternar()
                        : _reproductor.reproducirLista(
                            _elementos.where((Elemento e) => e.audio).toList(),
                            _elementos
                                .where((Elemento e) => e.audio)
                                .toList()
                                .indexOf(elemento),
                          ),
                    icon: Icon(
                      sonando ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: Tema.tinta,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Entrada a la radio en directo: miles de emisoras, algunas sin perdida.
  Widget _radioEnVivo(BuildContext context) {
    return TarjetaFila(
      icono: Icons.radio_rounded,
      titulo: 'Radio en vivo',
      subtitulo: 'Emisoras de todo el mundo, las de Peru y algunas en FLAC',
      alPulsar: () => _abrir(const PantallaRadio()),
    );
  }

  Widget _estanteMixes(String titulo, List<Mix> mixes) {
    return Estante(
      titulo: titulo,
      alto: TarjetaMix.alto,
      cuantos: mixes.length,
      construir: (BuildContext context, int i) => TarjetaMix(
        mix: mixes[i],
        alPulsar: () => _abrirMix(mixes[i]),
      ),
    );
  }

  /// Canciones que no tienes, de la radio de tus artistas. Es la lista
  /// guardada: abrir Inicio no sale a la red.
  Widget _carruselDescubre() {
    final List<Resultado> pistas = _descubre.pistas.take(12).toList();
    return Estante(
      titulo: 'Descubre',
      alVerTodo: () => _abrir(const PantallaDescubre()),
      cuantos: pistas.length,
      construir: (BuildContext context, int i) {
        final Resultado r = pistas[i];
        final ({String artista, String tema}) p = Descubre.partesDe(r);
        return TarjetaEstante(
          titulo: p.tema,
          subtitulo: p.artista,
          portada: PortadaRemota(url: Descubre.portadaDe(r), ancho: 130, alto: 130),
          alPulsar: () => _abrir(PantallaPrevia(resultado: r)),
        );
      },
    );
  }

  /// Lo ultimo que llego, sin filtrar por fecha: si no se sabe cuando llego
  /// (fecha 0), sale igual. Con su sello de calidad cuando se sabe.
  Widget _recienDescargado(List<Elemento> canciones) {
    final List<Elemento> recientes = _elementos.take(10).toList();
    final DateTime ahora = DateTime.now();
    return Estante(
      titulo: 'Recien descargado',
      alVerTodo: widget.alIrABiblioteca,
      alto: 204,
      cuantos: recientes.length,
      construir: (BuildContext context, int i) {
        final Elemento e = recientes[i];
        final CalidadAudio? calidad = _calidades[e.uri];
        return TarjetaEstante(
          elemento: e,
          subtitulo: <String>[?cuandoLlego(e.fecha, ahora), formatoTiempo(e.duracion)].join('  ·  '),
          sello: calidad == null ? null : SelloCalidad(calidad: calidad),
          alPulsar: () => _oir(e, canciones),
        );
      },
    );
  }

  /// Las emisoras del corazon, en vivo al tocarlas.
  Widget _radioFavorita() {
    final List<EstacionRadio> emisoras = _radios.todas;
    return Estante(
      titulo: 'Radio favorita',
      alto: TarjetaEmisora.alto,
      cuantos: emisoras.length,
      alVerTodo: () => _abrir(PantallaRadio(inicial: PantallaRadio.filtroDe('Favoritas'))),
      construir: (BuildContext context, int i) => TarjetaEmisora(emisora: emisoras[i]),
    );
  }

  /// Lo mas escuchado. Solo sale cuando ya hay unas cuantas, porque con una
  /// o dos no dice nada y ocupa lo mismo.
  Widget _carruselMasOidas(BuildContext context) {
    return Estante(
      titulo: 'Lo que mas oyes',
      alVerTodo: widget.alIrABiblioteca,
      cuantos: _masOidas.length,
      construir: (BuildContext context, int i) => TarjetaEstante(
        elemento: _masOidas[i],
        subtitulo: formatoTiempo(_masOidas[i].duracion),
        alPulsar: () {
          _reproductor.reproducirLista(_masOidas, i);
          _abrir(Reproductor(elemento: _masOidas[i], arrancar: false));
        },
      ),
    );
  }

  /// Lo que llego sin perdida de origen (un FLAC hecho desde YouTube no
  /// cuenta), con el camino para encontrar mas.
  Widget _carruselSinPerdida() {
    final List<Elemento> enteras = _sinPerdida.take(20).toList();
    return Estante(
      titulo: 'Sin perdida',
      alVerTodo: () => _abrirListaAuto(ListaAuto.sinPerdida),
      alto: 204,
      cuantos: enteras.length,
      construir: (BuildContext context, int i) {
        final CalidadAudio? calidad = _calidades[enteras[i].uri];
        return TarjetaEstante(
          elemento: enteras[i],
          subtitulo: formatoTiempo(enteras[i].duracion),
          sello: calidad == null ? null : SelloCalidad(calidad: calidad),
          alPulsar: () => _oir(enteras[i], enteras),
        );
      },
      pie: TextButton.icon(
        onPressed: _abrirExplorar,
        icon: const Icon(Icons.travel_explore_rounded, size: 18, color: Tema.oro),
        label: const Text('Encontrar mas sin perdida'),
      ),
    );
  }

  /// Episodios, mezclas y sesiones largas que se dejaron a medias: siguen
  /// donde se quedaron al tocarlos.
  Widget _carruselAMedias() {
    return Estante(
      titulo: 'Episodios a medias',
      alto: 196,
      cuantos: _aMedias.length,
      construir: (BuildContext context, int i) {
        final ({Elemento elemento, Duration posicion}) a = _aMedias[i];
        final double total = a.elemento.duracion;
        final int oido = a.posicion.inSeconds;
        return TarjetaEstante(
          elemento: a.elemento,
          progreso: total <= 0 ? 0 : oido / total,
          subtitulo: 'Quedan ${formatoTiempo(max(0, total - oido))}',
          alPulsar: () {
            _reproductor.reproducirLista(<Elemento>[a.elemento], 0);
            _abrir(Reproductor(elemento: a.elemento, arrancar: false));
          },
        );
      },
    );
  }

  Widget _carruselListas(BuildContext context, List<String> nombres) {
    return Estante(
      titulo: 'Tus listas',
      alVerTodo: widget.alIrABiblioteca,
      cuantos: nombres.length,
      construir: (BuildContext context, int i) {
        final List<String> uris = _listas.contenido(nombres[i]);
        final List<Elemento> pistas =
            _elementos.where((Elemento e) => uris.contains(e.uri)).toList();
        return TarjetaEstante(
          elemento: pistas.isEmpty ? null : pistas.first,
          titulo: nombres[i],
          subtitulo: '${pistas.length} pistas',
          alPulsar: () => _abrir(PantallaLista(nombre: nombres[i], biblioteca: _elementos)),
        );
      },
    );
  }
}
