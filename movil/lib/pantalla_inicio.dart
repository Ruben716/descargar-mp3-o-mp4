import 'dart:async';

import 'package:flutter/material.dart';

import 'catalogo.dart';
import 'estado_reproductor.dart';
import 'formato.dart';
import 'listas.dart';
import 'nucleo.dart';
import 'pantalla_lista.dart';
import 'portadas.dart';
import 'reproductor.dart';
import 'tema.dart';

/// Pantalla de entrada de la app.
///
/// Sigue lo que hacen las apps de musica: al abrir no se pide nada al usuario,
/// se le ofrece seguir donde lo dejo y lo que tiene a mano. El formulario de
/// descarga vive en su pestania, que es donde se va a buscar algo nuevo.
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

  List<Elemento> _elementos = <Elemento>[];

  /// Lo mas oido, de la pista mas escuchada a la que menos.
  List<Elemento> _masOidas = <Elemento>[];
  bool _cargando = true;

  @override
  void initState() {
    super.initState();
    _listas.addListener(_refrescar);
    _reproductor.addListener(_refrescar);
    _listas.cargar();
    recargar();
  }

  @override
  void dispose() {
    _listas.removeListener(_refrescar);
    _reproductor.removeListener(_refrescar);
    super.dispose();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  Future<void> recargar() async {
    try {
      final List<Elemento> elementos = await Nucleo.biblioteca();
      if (!mounted) return;
      setState(() {
        _elementos = elementos;
        _cargando = false;
      });
      // El recuento va aparte y sin esperarlo: la pantalla no puede quedarse
      // en blanco por una consulta que solo sirve para un carrusel.
      unawaited(_cargarMasOidas(elementos));
    } catch (_) {
      if (mounted) setState(() => _cargando = false);
    }
  }

  Future<void> _cargarMasOidas(List<Elemento> biblioteca) async {
    final List<Elemento> masOidas = await _ordenarPorEscuchas(biblioteca);
    if (mounted) setState(() => _masOidas = masOidas);
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

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());

    final List<String> listas = _listas.nombres;
    final int canciones = _elementos.where((Elemento e) => e.audio).length;

    return RefreshIndicator(
      onRefresh: recargar,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: <Widget>[
          _cabecera(context, canciones, listas.length),
          if (_elementos.isEmpty)
            _primerosPasos(context)
          else ...<Widget>[
            if (_continuar != null) _continuarEscuchando(context, _continuar!),
            if (_masOidas.length >= 3) _carruselMasOidas(context),
            _carruselPistas(context),
            if (listas.isNotEmpty) _carruselListas(context, listas),
          ],
        ],
      ),
    );
  }

  Widget _cabecera(BuildContext context, int canciones, int listas) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
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
            child: const Icon(Icons.music_note_rounded, size: 46, color: Colors.black38),
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

  Widget _continuarEscuchando(BuildContext context, Elemento elemento) {
    final bool sonando = _reproductor.esActual(elemento.uri) && _reproductor.sonando;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
      child: Material(
        color: Tema.superficie,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => Reproductor(elemento: elemento)),
          ),
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
                        style: const TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.1,
                          fontWeight: FontWeight.w800,
                          color: Tema.acento,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        nombreLimpio(elemento.nombre),
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
                      color: Colors.black87,
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

  Widget _carruselPistas(BuildContext context) {
    final List<Elemento> recientes = _elementos.take(10).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _tituloSeccion(context, 'Anadido recientemente', widget.alIrABiblioteca),
        SizedBox(
          height: 186,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: recientes.length,
            itemBuilder: (BuildContext context, int i) => _Tarjeta(
              elemento: recientes[i],
              subtitulo: formatoTiempo(recientes[i].duracion),
              alPulsar: () {
                if (recientes[i].audio) {
                  final List<Elemento> canciones =
                      _elementos.where((Elemento e) => e.audio).toList();
                  _reproductor.reproducirLista(
                    canciones,
                    canciones.indexOf(recientes[i]),
                  );
                }
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Reproductor(elemento: recientes[i]),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }

  /// Lo mas escuchado. Solo sale cuando ya hay unas cuantas, porque con una
  /// o dos no dice nada y ocupa lo mismo.
  Widget _carruselMasOidas(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _tituloSeccion(context, 'Lo que mas oyes', widget.alIrABiblioteca),
        SizedBox(
          height: 186,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _masOidas.length,
            itemBuilder: (BuildContext context, int i) => _Tarjeta(
              elemento: _masOidas[i],
              subtitulo: formatoTiempo(_masOidas[i].duracion),
              alPulsar: () {
                _reproductor.reproducirLista(_masOidas, i);
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => Reproductor(elemento: _masOidas[i]),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 26),
      ],
    );
  }

  Widget _carruselListas(BuildContext context, List<String> nombres) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _tituloSeccion(context, 'Tus listas', widget.alIrABiblioteca),
        SizedBox(
          height: 186,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: nombres.length,
            itemBuilder: (BuildContext context, int i) {
              final List<String> uris = _listas.contenido(nombres[i]);
              final List<Elemento> pistas =
                  _elementos.where((Elemento e) => uris.contains(e.uri)).toList();
              return _Tarjeta(
                elemento: pistas.isEmpty ? null : pistas.first,
                titulo: nombres[i],
                subtitulo: '${pistas.length} pistas',
                alPulsar: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PantallaLista(
                      nombre: nombres[i],
                      biblioteca: _elementos,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _tituloSeccion(BuildContext context, String texto, VoidCallback alVerTodo) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              texto,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 17),
            ),
          ),
          TextButton(onPressed: alVerTodo, child: const Text('Ver todo')),
        ],
      ),
    );
  }
}

/// Tarjeta cuadrada de un carrusel.
class _Tarjeta extends StatelessWidget {
  const _Tarjeta({
    required this.elemento,
    required this.subtitulo,
    required this.alPulsar,
    this.titulo,
  });

  final Elemento? elemento;
  final String? titulo;
  final String subtitulo;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    final Elemento? pista = elemento;
    return Padding(
      padding: const EdgeInsets.only(right: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: alPulsar,
        child: SizedBox(
          width: 130,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (pista == null)
                Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    gradient: Tema.degradado,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(Icons.queue_music_rounded, color: Colors.black38, size: 40),
                )
              else
                PortadaLocal(elemento: pista, lado: 130, radio: 18),
              const SizedBox(height: 8),
              Text(
                titulo ?? nombreLimpio(pista!.nombre),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 2),
              Text(
                subtitulo,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
