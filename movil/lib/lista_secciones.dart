import 'dart:math';

import 'package:flutter/material.dart';

import 'formato.dart';
import 'nucleo.dart';
import 'tema.dart';

const List<String> _meses = <String>[
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio',
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

/// En que tramo de tiempo cae una descarga: «Hoy», «Esta semana», «Agosto 2026».
///
/// [fecha] va en segundos desde 1970, como la da Android. Sin fecha, «Antes».
String seccionPorFecha(int fecha, DateTime ahora) {
  if (fecha <= 0) return 'Antes';
  final DateTime cuando = DateTime.fromMillisecondsSinceEpoch(fecha * 1000);
  final DateTime hoy = DateTime(ahora.year, ahora.month, ahora.day);
  final DateTime dia = DateTime(cuando.year, cuando.month, cuando.day);
  final int dias = hoy.difference(dia).inDays;
  if (dias <= 0) return 'Hoy';
  if (dias == 1) return 'Ayer';
  if (dias < 7) return 'Esta semana';
  if (cuando.year == ahora.year && cuando.month == ahora.month) return 'Este mes';
  return '${_meses[cuando.month - 1]} ${cuando.year}';
}

/// La letra bajo la que va un tema en orden alfabetico.
///
/// Sin tildes («Ángel» va en la A) y con lo que no empieza por letra latina
/// (numeros, coreano, simbolos) junto bajo «#», como hacen las agendas.
String seccionPorLetra(String tema) {
  final String limpio = sinTildes(tema.trim()).toUpperCase();
  final Match? letra = RegExp('[A-Z]').matchAsPrefix(limpio);
  return letra == null ? '#' : letra.group(0)!;
}

/// Una lista de pistas partida en secciones, con indice lateral si se pide.
///
/// Todas las filas miden lo mismo y todas las cabeceras tambien: asi se sabe
/// donde empieza cada seccion sin haberla pintado, que es lo que permite
/// saltar a una letra en una lista que solo construye lo que se ve.
class ListaConSecciones extends StatefulWidget {
  const ListaConSecciones({
    required this.elementos,
    required this.seccionDe,
    required this.fila,
    required this.altoFila,
    this.cabecera,
    this.altoCabecera = 0,
    this.indice = false,
    this.alRefrescar,
    super.key,
  });

  final List<Elemento> elementos;

  /// El nombre de la seccion de cada pista, o null para no partir.
  final String Function(Elemento)? seccionDe;
  final Widget Function(Elemento) fila;
  final double altoFila;

  /// Lo que va encima de todo (los botones de reproducir), si hay.
  final Widget? cabecera;
  final double altoCabecera;

  /// Si se ensenia la tira de letras a la derecha para saltar.
  final bool indice;
  final Future<void> Function()? alRefrescar;

  static const double altoSeccion = 40;

  @override
  State<ListaConSecciones> createState() => _ListaConSeccionesState();
}

/// Lo que ocupa cada hueco de la lista.
sealed class _Hueco {
  const _Hueco();
}

class _HuecoCabecera extends _Hueco {
  const _HuecoCabecera();
}

class _HuecoSeccion extends _Hueco {
  const _HuecoSeccion(this.titulo);
  final String titulo;
}

class _HuecoFila extends _Hueco {
  const _HuecoFila(this.elemento);
  final Elemento elemento;
}

class _ListaConSeccionesState extends State<ListaConSecciones> {
  final ScrollController _desplazamiento = ScrollController();

  /// La letra que se esta senialando en el indice, para ensenarla grande.
  String? _letra;

  @override
  void dispose() {
    _desplazamiento.dispose();
    super.dispose();
  }

  List<_Hueco> get _huecos {
    final List<_Hueco> salida = <_Hueco>[if (widget.cabecera != null) const _HuecoCabecera()];
    String? anterior;
    for (final Elemento e in widget.elementos) {
      final String? seccion = widget.seccionDe?.call(e);
      if (seccion != null && seccion != anterior) {
        salida.add(_HuecoSeccion(seccion));
        anterior = seccion;
      }
      salida.add(_HuecoFila(e));
    }
    return salida;
  }

  double _alto(_Hueco hueco, double fila) => switch (hueco) {
        _HuecoCabecera() => widget.altoCabecera,
        _HuecoSeccion() => ListaConSecciones.altoSeccion,
        _HuecoFila() => fila,
      };

  /// Lleva la lista al principio de la seccion [titulo].
  void _saltarA(String titulo, List<_Hueco> huecos, double fila) {
    double hasta = 0;
    for (final _Hueco h in huecos) {
      if (h is _HuecoSeccion && h.titulo == titulo) break;
      hasta += _alto(h, fila);
    }
    if (!_desplazamiento.hasClients) return;
    _desplazamiento.jumpTo(min(hasta, _desplazamiento.position.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    // Con la letra del sistema mas grande, las filas crecen: se tiene en
    // cuenta para que los saltos del indice sigan cayendo en su sitio.
    final double escala = MediaQuery.textScalerOf(context).scale(1);
    final double fila = widget.altoFila + max(0, escala - 1) * 34;
    final List<_Hueco> huecos = _huecos;
    final List<String> letras = <String>[
      for (final _Hueco h in huecos)
        if (h is _HuecoSeccion) h.titulo,
    ];

    Widget lista = ListView.builder(
      controller: _desplazamiento,
      padding: const EdgeInsets.only(bottom: 20),
      itemCount: huecos.length,
      itemExtentBuilder: (int i, _) => i < huecos.length ? _alto(huecos[i], fila) : null,
      itemBuilder: (BuildContext context, int i) => switch (huecos[i]) {
        _HuecoCabecera() => widget.cabecera!,
        _HuecoSeccion(:final String titulo) => _TituloSeccion(titulo: titulo),
        _HuecoFila(:final Elemento elemento) => widget.fila(elemento),
      },
    );
    if (widget.alRefrescar != null) {
      lista = RefreshIndicator(onRefresh: widget.alRefrescar!, child: lista);
    }
    if (!widget.indice || letras.length < 2) return lista;

    return Stack(
      children: <Widget>[
        Padding(padding: const EdgeInsets.only(right: 18), child: lista),
        Positioned(
          right: 0,
          top: widget.altoCabecera,
          bottom: 0,
          child: _Indice(
            letras: letras,
            alSenialar: (String letra) {
              setState(() => _letra = letra);
              _saltarA(letra, huecos, fila);
            },
            alSoltar: () => setState(() => _letra = null),
          ),
        ),
        if (_letra case final String letra)
          Center(
            child: Container(
              width: 84,
              height: 84,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Tema.superficieAlta.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(
                letra,
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: Tema.acento),
              ),
            ),
          ),
      ],
    );
  }
}

class _TituloSeccion extends StatelessWidget {
  const _TituloSeccion({required this.titulo});

  final String titulo;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
        child: Text(
          titulo.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: Colors.white54,
          ),
        ),
      );
}

/// La tira de letras: se toca o se arrastra el dedo por ella para saltar.
class _Indice extends StatelessWidget {
  const _Indice({required this.letras, required this.alSenialar, required this.alSoltar});

  final List<String> letras;
  final void Function(String) alSenialar;
  final VoidCallback alSoltar;

  void _senialar(BuildContext context, double y) {
    final double alto = (context.findRenderObject()! as RenderBox).size.height;
    final int i = (y / alto * letras.length).floor().clamp(0, letras.length - 1);
    alSenialar(letras[i]);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Indice alfabetico',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: (DragStartDetails d) => _senialar(context, d.localPosition.dy),
        onVerticalDragUpdate: (DragUpdateDetails d) => _senialar(context, d.localPosition.dy),
        onVerticalDragEnd: (_) => alSoltar(),
        onTapDown: (TapDownDetails d) => _senialar(context, d.localPosition.dy),
        onTapUp: (_) => alSoltar(),
        child: SizedBox(
          width: 18,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              for (final String letra in letras)
                Flexible(
                  child: FittedBox(
                    child: Text(
                      letra,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Tema.acento,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
