import 'package:flutter/material.dart';

import 'catalogo.dart';
import 'estado_reproductor.dart';
import 'letras.dart';
import 'nucleo.dart';
import 'tema.dart';

/// La letra de lo que suena, resaltando la linea que toca.
class PanelLetras extends StatefulWidget {
  const PanelLetras({required this.elemento, super.key});

  final Elemento elemento;

  @override
  State<PanelLetras> createState() => _PanelLetrasState();
}

class _PanelLetrasState extends State<PanelLetras> {
  final EstadoReproductor _estado = EstadoReproductor.instancia;
  final ScrollController _desplazamiento = ScrollController();

  /// Alto fijo por linea: hace falta saberlo para poder centrar la que suena
  /// sin medir el texto, que con lineas de dos renglones seria un lio.
  static const double _alto = 46;

  Letra? _letra;
  int _resaltada = -1;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(PanelLetras anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.elemento.uri != widget.elemento.uri) _cargar();
  }

  @override
  void dispose() {
    _desplazamiento.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    setState(() {
      _letra = null;
      _resaltada = -1;
    });
    final Letra letra = await Letras.de(
      uri: widget.elemento.uri,
      nombre: widget.elemento.nombre,
      duracion: widget.elemento.duracion,
    );
    if (mounted) setState(() => _letra = letra);
  }

  /// Corre la letra medio segundo y lo guarda para esta pista.
  Future<void> _ajustar(Duration cuanto) async {
    final Letra? letra = _letra;
    if (letra == null) return;
    final Duration nuevo = letra.desfase + cuanto;
    setState(() {
      _letra = letra.conDesfase(nuevo);
      // Sin esto la linea resaltada no se movería hasta el siguiente cambio.
      _resaltada = -1;
    });
    await Catalogo.instancia.guardarDesfase(widget.elemento.uri, nuevo.inMilliseconds);
  }

  void _seguir(Letra letra, Duration instante) {
    final int toca = letra.lineaEn(instante);
    if (toca == _resaltada) return;
    _resaltada = toca;
    if (toca < 0 || !_desplazamiento.hasClients) return;

    // La linea que canta se lleva al centro; el resto queda arriba y abajo,
    // que es lo que deja seguir la cancion sin buscar donde va.
    final double alto = _desplazamiento.position.viewportDimension;
    final double destino = (toca * _alto) - (alto / 2) + (_alto / 2);
    _desplazamiento.animateTo(
      destino.clamp(0, _desplazamiento.position.maxScrollExtent),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Letra? letra = _letra;
    if (letra == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (letra.vacia) {
      return const _SinLetra();
    }
    if (!letra.sincronizada) {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 40),
        child: Text(
          letra.texto,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white70, height: 1.9, fontSize: 16),
        ),
      );
    }

    return Column(
      children: <Widget>[
        Expanded(child: _versos(letra)),
        _ControlSincronia(desfase: letra.desfase, alAjustar: _ajustar),
      ],
    );
  }

  Widget _versos(Letra letra) {
    return StreamBuilder<Duration>(
      stream: _estado.motor.positionStream,
      builder: (BuildContext context, AsyncSnapshot<Duration> instante) {
        final Duration ahora = instante.data ?? Duration.zero;
        // El desplazamiento se pide para despues del fotograma: moverlo
        // mientras se construye la lista es un error en Flutter.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _seguir(letra, ahora);
        });
        final int activa = letra.lineaEn(ahora);

        return ListView.builder(
          controller: _desplazamiento,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          itemCount: letra.lineas.length,
          itemExtent: _alto,
          itemBuilder: (BuildContext context, int i) {
            final bool suena = i == activa;
            return GestureDetector(
              // Tocar una linea salta a ese momento: es la forma mas comoda
              // de repetir el trozo que no se pillo.
              onTap: () => _estado.motor.seek(letra.lineas[i].desde),
              behavior: HitTestBehavior.opaque,
              child: Align(
                alignment: Alignment.center,
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: suena ? 19 : 16,
                    height: 1.25,
                    fontWeight: suena ? FontWeight.w800 : FontWeight.w500,
                    color: suena
                        ? Tema.acento
                        : (i < activa ? Colors.white24 : Colors.white60),
                  ),
                  child: Text(
                    letra.lineas[i].texto.isEmpty ? '·' : letra.lineas[i].texto,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Corrige a mano la sincronia de la letra.
///
/// Hace falta aunque la letra sea la correcta: las marcas que da el servidor
/// son del disco, y el video de YouTube casi nunca arranca en el mismo punto
/// porque suele llevar una entradilla.
class _ControlSincronia extends StatelessWidget {
  const _ControlSincronia({required this.desfase, required this.alAjustar});

  static const Duration paso = Duration(milliseconds: 500);

  final Duration desfase;
  final Future<void> Function(Duration) alAjustar;

  String get _etiqueta {
    if (desfase == Duration.zero) return 'A la par';
    final double segundos = desfase.inMilliseconds / 1000;
    final String signo = segundos > 0 ? '+' : '';
    return '$signo${segundos.toStringAsFixed(1)} s';
  }

  @override
  Widget build(BuildContext context) {
    final bool ajustada = desfase != Duration.zero;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton(
                onPressed: () => alAjustar(-paso),
                tooltip: 'La letra va atrasada',
                icon: const Icon(Icons.fast_rewind_rounded, size: 20),
                color: Colors.white54,
              ),
              SizedBox(
                width: 84,
                child: TextButton(
                  onPressed: ajustada ? () => alAjustar(-desfase) : null,
                  child: Text(
                    _etiqueta,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ajustada ? Tema.acento : Colors.white38,
                    ),
                  ),
                ),
              ),
              IconButton(
                onPressed: () => alAjustar(paso),
                tooltip: 'La letra va adelantada',
                icon: const Icon(Icons.fast_forward_rounded, size: 20),
                color: Colors.white54,
              ),
            ],
          ),
          Text(
            ajustada ? 'Toca el valor para dejarlo como estaba' : 'Ajusta si no va a la par',
            style: const TextStyle(color: Colors.white24, fontSize: 10),
          ),
        ],
      ),
    );
  }
}

class _SinLetra extends StatelessWidget {
  const _SinLetra();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.lyrics_outlined, size: 48, color: Colors.white24),
          SizedBox(height: 14),
          Text(
            'No hay letra para esta.',
            style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 6),
          Text(
            'Se busca por el nombre del archivo, asi que\n'
            'si viene raro puede que no aparezca.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    ),
  );
}
