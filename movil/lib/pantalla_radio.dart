import 'dart:async';

import 'package:flutter/material.dart';

import 'cargando.dart';
import 'estado_reproductor.dart';
import 'radio_mundial.dart';
import 'tema.dart';

/// Un atajo de la pantalla de radio: que se busca al tocarlo.
class FiltroRadio {
  const FiltroRadio(this.etiqueta, {this.pais = '', this.genero = '', this.sinPerdida = false, this.favoritas = false});

  final String etiqueta;
  final String pais;
  final String genero;
  final bool sinPerdida;
  final bool favoritas;
}

/// Radio en directo de todo el mundo: las de Peru, las de un genero, las
/// que emiten en FLAC... Se escucha al momento, sin bajar nada.
class PantallaRadio extends StatefulWidget {
  const PantallaRadio({this.inicial, super.key});

  /// Con que atajo se abre (Sin perdida, Favoritas, un genero...). Sin el,
  /// las mas votadas.
  final FiltroRadio? inicial;

  /// El atajo de [filtros] que se llama asi, o el primero si no hay ninguno.
  static FiltroRadio filtroDe(String etiqueta) => filtros.firstWhere(
        (FiltroRadio f) => f.etiqueta == etiqueta,
        orElse: () => filtros.first,
      );

  /// Los atajos, en el orden en que se ensenian.
  static const List<FiltroRadio> filtros = <FiltroRadio>[
    FiltroRadio('Populares'),
    FiltroRadio('Favoritas', favoritas: true),
    FiltroRadio('Peru', pais: 'PE'),
    FiltroRadio('Sin perdida', sinPerdida: true),
    FiltroRadio('Lofi', genero: 'lofi'),
    FiltroRadio('Salsa', genero: 'salsa'),
    FiltroRadio('Reggaeton', genero: 'reggaeton'),
    FiltroRadio('Rock', genero: 'rock'),
    FiltroRadio('Pop', genero: 'pop'),
    FiltroRadio('Jazz', genero: 'jazz'),
    FiltroRadio('Clasica', genero: 'classical'),
    FiltroRadio('Noticias', genero: 'news'),
  ];

  @override
  State<PantallaRadio> createState() => _PantallaRadioState();
}

class _PantallaRadioState extends State<PantallaRadio> {
  final TextEditingController _texto = TextEditingController();
  final EstadoReproductor _reproductor = EstadoReproductor.instancia;
  final RadiosFavoritas _favoritas = RadiosFavoritas.instancia;

  late FiltroRadio _filtro = widget.inicial ?? PantallaRadio.filtros.first;

  /// La ficha del atajo con que se abrio, para llevarla a la vista: los
  /// generos quedan fuera de la pantalla, a la derecha.
  final GlobalKey _fichaInicial = GlobalKey();
  List<EstacionRadio> _emisoras = <EstacionRadio>[];
  bool _cargando = false;
  String? _fallo;
  int _peticion = 0;

  @override
  void initState() {
    super.initState();
    _favoritas.cargar();
    unawaited(_buscar());
    if (widget.inicial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final BuildContext? ficha = _fichaInicial.currentContext;
        if (ficha != null && mounted) Scrollable.ensureVisible(ficha, alignment: 0.5);
      });
    }
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _buscar() async {
    final int esta = ++_peticion;
    if (_filtro.favoritas) {
      setState(() {
        _fallo = null;
        _cargando = false;
      });
      return;
    }
    setState(() {
      _cargando = true;
      _fallo = null;
    });
    try {
      final List<EstacionRadio> halladas = await RadioMundial.buscar(
        nombre: _texto.text,
        paisCodigo: _filtro.pais,
        etiqueta: _filtro.genero,
        soloSinPerdida: _filtro.sinPerdida,
      );
      if (!mounted || esta != _peticion) return;
      setState(() {
        _emisoras = halladas;
        _cargando = false;
      });
    } catch (error) {
      if (!mounted || esta != _peticion) return;
      setState(() {
        _cargando = false;
        _fallo = error is ErrorRadio ? error.mensaje : 'No se pudo buscar: $error';
      });
    }
  }

  void _elegir(FiltroRadio filtro) {
    setState(() => _filtro = filtro);
    unawaited(_buscar());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Tema.fondo,
      appBar: AppBar(title: const Text('Radio en vivo'), backgroundColor: Colors.transparent),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _texto,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _buscar(),
              decoration: const InputDecoration(
                hintText: 'Busca una emisora: RPP, Radio Paradise...',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: <Widget>[
                for (final FiltroRadio f in PantallaRadio.filtros)
                  Padding(
                    key: f.etiqueta == widget.inicial?.etiqueta ? _fichaInicial : null,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(f.etiqueta),
                      selected: f.etiqueta == _filtro.etiqueta,
                      onSelected: (_) => _elegir(f),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[_reproductor, _favoritas]),
              builder: (BuildContext context, _) => _lista(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lista() {
    if (_cargando) return const Center(child: CargandoMusica(texto: 'Sintonizando emisoras...'));
    if (_fallo case final String fallo) {
      return _aviso(Icons.wifi_off_rounded, fallo);
    }
    final List<EstacionRadio> emisoras = _filtro.favoritas ? _favoritas.todas : _emisoras;
    if (emisoras.isEmpty) {
      return _aviso(
        _filtro.favoritas ? Icons.favorite_border_rounded : Icons.radio_rounded,
        _filtro.favoritas
            ? 'Toca el corazon de una emisora\ny la tendras aqui.'
            : 'Ninguna emisora con eso. Prueba otro nombre.',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      itemCount: emisoras.length,
      itemBuilder: (BuildContext context, int i) => _FilaEmisora(
        emisora: emisoras[i],
        sonando: _reproductor.actual?.enVivo?.url == emisoras[i].url,
        favorita: _favoritas.contiene(emisoras[i]),
        alPulsar: () => _reproductor.reproducirEmisora(emisoras[i]),
        alCorazon: () => _favoritas.alternar(emisoras[i]),
      ),
    );
  }

  Widget _aviso(IconData icono, String texto) => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icono, size: 40, color: Colors.white24),
              const SizedBox(height: 12),
              Text(texto, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, height: 1.5)),
            ],
          ),
        ),
      );
}

class _FilaEmisora extends StatelessWidget {
  const _FilaEmisora({
    required this.emisora,
    required this.sonando,
    required this.favorita,
    required this.alPulsar,
    required this.alCorazon,
  });

  final EstacionRadio emisora;
  final bool sonando;
  final bool favorita;
  final VoidCallback alPulsar;
  final VoidCallback alCorazon;

  @override
  Widget build(BuildContext context) {
    final Color tono = emisora.sinPerdida ? Tema.oro : Colors.white54;
    return ListTile(
      onTap: alPulsar,
      leading: LogoEmisora(emisora: emisora, lado: 48),
      title: Text(
        emisora.nombre,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontWeight: FontWeight.w700, color: sonando ? Tema.acento : null),
      ),
      subtitle: Text(
        <String>[if (emisora.pais.isNotEmpty) emisora.pais, emisora.sello].join('  ·  '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 12, color: tono),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (sonando) const Icon(Icons.graphic_eq_rounded, color: Tema.acento),
          IconButton(
            tooltip: favorita ? 'Quitar de favoritas' : 'Guardar en favoritas',
            onPressed: alCorazon,
            icon: Icon(
              favorita ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: favorita ? Tema.meGusta : Colors.white38,
            ),
          ),
        ],
      ),
    );
  }
}

/// El logo de la emisora, o un icono de radio si no tiene o no carga.
class LogoEmisora extends StatelessWidget {
  const LogoEmisora({required this.emisora, required this.lado, super.key});

  final EstacionRadio emisora;
  final double lado;

  @override
  Widget build(BuildContext context) {
    final Widget reserva = Container(
      width: lado,
      height: lado,
      decoration: BoxDecoration(gradient: Tema.degradado, borderRadius: BorderRadius.circular(lado / 4)),
      child: Icon(Icons.radio_rounded, color: const Color(0x730B0B0C), size: lado / 2),
    );
    if (!emisora.logo.startsWith('http')) return reserva;
    return ClipRRect(
      borderRadius: BorderRadius.circular(lado / 4),
      child: Image.network(
        emisora.logo,
        width: lado,
        height: lado,
        fit: BoxFit.cover,
        errorBuilder: (BuildContext context, Object _, StackTrace? _) => reserva,
      ),
    );
  }
}
