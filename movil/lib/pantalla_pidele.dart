import 'dart:async';

import 'package:flutter/material.dart';

import 'calidad.dart';
import 'catalogo.dart';
import 'dialogos.dart';
import 'estado_reproductor.dart';
import 'fila_pista.dart';
import 'formato.dart';
import 'hoja_listas.dart';
import 'listas.dart';
import 'nucleo.dart';
import 'pantalla_radio.dart';
import 'pidele.dart';
import 'ritmos.dart';
import 'tema.dart';

/// «Pidele a Tumbao»: escribe lo que quieres oir y la app arma la cola.
///
/// Funciona sin internet, con lo que hay en el telefono. Lo entendido sale en
/// fichas: tocar la x de una la quita y la cola se rehace al momento.
class PantallaPidele extends StatefulWidget {
  const PantallaPidele({super.key, this.frase = ''});

  /// Lo que ya viene escrito (un ejemplo tocado, un atajo).
  final String frase;

  @override
  State<PantallaPidele> createState() => _PantallaPideleState();
}

class _PantallaPideleState extends State<PantallaPidele> {
  late final TextEditingController _texto = TextEditingController(text: widget.frase);

  /// La biblioteca y lo que se sabe de ella; null mientras se carga.
  DatosBiblioteca? _datos;

  /// Lo pedido la ultima vez, para rehacerlo al quitar una ficha.
  String _frase = '';
  final Set<String> _quitadas = <String>{};
  Peticion? _peticion;
  Respuesta? _respuesta;

  @override
  void initState() {
    super.initState();
    Ritmos.instancia.addListener(_alAnalizar);
    unawaited(_cargar());
  }

  @override
  void dispose() {
    Ritmos.instancia.removeListener(_alAnalizar);
    _texto.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    List<Elemento> canciones = const <Elemento>[];
    Map<String, ({int veces, int ultima})> escuchas = const <String, ({int veces, int ultima})>{};
    Set<String> favoritas = const <String>{};
    Map<String, CalidadAudio> calidades = const <String, CalidadAudio>{};
    try {
      canciones = await Nucleo.biblioteca();
    } catch (_) {
      // Sin biblioteca solo queda buscar en internet.
    }
    try {
      escuchas = await Catalogo.instancia.escuchasConFecha();
      favoritas = (await Catalogo.instancia.favoritas()).toSet();
      calidades = await Catalogo.instancia.calidades();
    } catch (_) {
      // Sin catalogo se pide igual: solo se pierde lo que dependa de el.
    }
    if (!mounted) return;
    setState(() {
      _datos = DatosBiblioteca(
        canciones: canciones,
        rasgos: Ritmos.instancia.todos,
        escuchas: escuchas,
        favoritas: favoritas,
        calidades: calidades,
        percentil: Ritmos.instancia.percentil,
      );
    });
    if (widget.frase.trim().isNotEmpty) _pedir(widget.frase);
  }

  /// Llega un analisis nuevo: si lo pedido dependia del ritmo, se rehace.
  void _alAnalizar() {
    final DatosBiblioteca? d = _datos;
    if (d == null || !mounted) return;
    _datos = DatosBiblioteca(
      canciones: d.canciones,
      rasgos: Ritmos.instancia.todos,
      escuchas: d.escuchas,
      favoritas: d.favoritas,
      calidades: d.calidades,
      percentil: Ritmos.instancia.percentil,
    );
    if ((_peticion?.pideRitmo ?? false) && !Ritmos.instancia.trabajando) _rehacer();
  }

  void _pedir(String frase) {
    _frase = frase.trim();
    _quitadas.clear();
    _rehacer();
  }

  void _rehacer() {
    final DatosBiblioteca? d = _datos;
    if (d == null || _frase.isEmpty) {
      setState(() {
        _peticion = null;
        _respuesta = null;
      });
      return;
    }
    final Peticion p = interpretar(_frase, artistas: d.artistas, quitar: _quitadas);
    Respuesta r = aplicarPeticion(p, d);
    // Si no se entendio nada, quiza es un nombre: se busca en la biblioteca.
    if (p.vacia) {
      r = Respuesta(
        pistas: <Elemento>[
          for (final Elemento e in d.canciones)
            if (e.audio && coincide(e.nombre, _frase)) e,
        ],
      );
    }
    setState(() {
      _peticion = p;
      _respuesta = r;
    });
  }

  void _quitar(String etiqueta) {
    _quitadas.add(etiqueta);
    _rehacer();
  }

  Future<void> _reproducir(List<Elemento> pistas, Peticion p) async {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    if (p.modoDj != null) {
      await estado.reproducirDj(pistas, modo: p.modoDj!);
    } else if (p.orden == OrdenPeticion.aleatorio) {
      await estado.reproducirAleatorio(pistas);
    } else {
      await estado.reproducirEnOrden(pistas);
    }
  }

  Future<void> _guardar(List<Elemento> pistas) async {
    final String? nombre = await pedirNombreDeLista(context);
    if (nombre == null || nombre.trim().isEmpty || !mounted) return;
    final Listas listas = Listas.instancia;
    await listas.cargar();
    await listas.crear(nombre.trim());
    final int metidas = await listas.anadirVarias(nombre.trim(), <String>[for (final Elemento e in pistas) e.uri]);
    if (mounted) avisar(context, 'Lista «${nombre.trim()}» con $metidas canciones.');
  }

  /// Lo que no esta en el telefono se busca fuera: lo atiende Descargar.
  void _buscarFuera() {
    final String frase = _frase;
    unawaited(Navigator.of(context).maybePop());
    Nucleo.enlaceCompartido.value = frase;
  }

  @override
  Widget build(BuildContext context) {
    final Peticion? p = _peticion;
    final Respuesta? r = _respuesta;
    return Scaffold(
      backgroundColor: Tema.fondo,
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Pidele a Tumbao')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: <Widget>[
          TextField(
            controller: _texto,
            autofocus: widget.frase.isEmpty,
            textInputAction: TextInputAction.search,
            onSubmitted: _pedir,
            decoration: InputDecoration(
              hintText: 'Que quieres oir?',
              prefixIcon: const Icon(Icons.auto_awesome_rounded, color: Tema.acentoClaro),
              suffixIcon: IconButton(
                tooltip: 'Pedir',
                icon: const Icon(Icons.arrow_forward_rounded),
                onPressed: () => _pedir(_texto.text),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (p == null) ..._ejemplos() else ..._resultado(p, r!),
        ],
      ),
    );
  }

  List<Widget> _ejemplos() => <Widget>[
        const Text(
          'Pide como se lo pedirias a un amigo. Funciona sin internet, con tu musica.',
          style: TextStyle(color: Tema.textoSecundario, height: 1.4),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final String ejemplo in <String>{
              ...ejemplosPara(DateTime.now()),
              'lo que mas escucho',
              'algo para estudiar',
              'mis favoritas sin perdida',
            })
              ActionChip(
                avatar: const Icon(Icons.north_east_rounded, size: 16),
                label: Text(ejemplo),
                onPressed: () {
                  _texto.text = ejemplo;
                  _pedir(ejemplo);
                },
              ),
          ],
        ),
      ];

  List<Widget> _resultado(Peticion p, Respuesta r) {
    final List<Elemento> pistas = r.pistas;
    final int segundos = pistas.fold(0, (int s, Elemento e) => s + e.duracion.round());
    return <Widget>[
      if (p.entendido.isNotEmpty)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: <Widget>[
            for (final String etiqueta in p.entendido)
              if (!_quitadas.contains(etiqueta))
                InputChip(
                  label: Text(etiqueta),
                  onDeleted: () => _quitar(etiqueta),
                  deleteButtonTooltipMessage: 'Quitar $etiqueta',
                ),
          ],
        ),
      for (final String aviso in r.avisos)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('Para que salga algo: $aviso', style: const TextStyle(color: Tema.oro, fontSize: 12)),
        ),
      if (r.sinAnalizar > 0)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Faltan ${r.sinAnalizar} por analizar: entraran cuando el DJ las escuche.',
                  style: const TextStyle(color: Tema.textoTenue, fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: Ritmos.instancia.trabajando
                    ? null
                    : () => Ritmos.instancia.analizarTodas(
                          <String>[for (final Elemento e in _datos!.canciones) if (e.audio) e.uri],
                          urgente: true,
                        ),
                child: const Text('Analizar'),
              ),
            ],
          ),
        ),
      if (p.radio)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const PantallaRadio()),
            ),
            icon: const Icon(Icons.radio_rounded),
            label: const Text('Escuchar radio en vivo'),
          ),
        ),
      const SizedBox(height: 14),
      if (pistas.isEmpty) ...<Widget>[
        const Text(
          'En tu telefono no hay nada que encaje.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          onPressed: _buscarFuera,
          icon: const Icon(Icons.travel_explore_rounded),
          label: const Text('Buscar en internet'),
        ),
      ] else ...<Widget>[
        Text(
          '${pistas.length == 1 ? '1 cancion' : '${pistas.length} canciones'}  ·  ${formatoTiempo(segundos)}',
          style: const TextStyle(color: Tema.textoTenue, fontSize: 12),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _reproducir(pistas, p),
                icon: const Icon(Icons.play_arrow_rounded),
                label: Text(p.modoDj == null ? 'Reproducir' : 'Poner la mezcla'),
              ),
            ),
            const SizedBox(width: 8),
            if (p.modoDj == null && pistas.length >= 3) ...<Widget>[
              IconButton.filledTonal(
                tooltip: 'Mezcla DJ',
                onPressed: () => EstadoReproductor.instancia.reproducirDj(pistas),
                icon: const Icon(Icons.queue_music_rounded),
              ),
              const SizedBox(width: 8),
            ],
            IconButton.filledTonal(
              tooltip: 'Guardar como lista',
              onPressed: () => _guardar(pistas),
              icon: const Icon(Icons.playlist_add_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final Elemento e in pistas.take(60)) FilaPista(elemento: e, enCola: pistas),
        if (pistas.length > 60)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('y ${pistas.length - 60} mas', style: const TextStyle(color: Tema.textoTenue)),
          ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _buscarFuera,
          icon: const Icon(Icons.travel_explore_rounded),
          label: const Text('Buscar tambien en internet'),
        ),
      ],
    ];
  }
}
