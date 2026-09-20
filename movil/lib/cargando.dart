import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tema.dart';

/// Espera con barras de ecualizador en vez de una rueda gris.
///
/// Traer una lista larga tarda unos segundos y antes no se veia nada: parecia
/// que la app se hubiera quedado colgada.
class CargandoMusica extends StatefulWidget {
  const CargandoMusica({required this.texto, super.key});

  final String texto;

  @override
  State<CargandoMusica> createState() => _CargandoMusicaState();
}

class _CargandoMusicaState extends State<CargandoMusica> with SingleTickerProviderStateMixin {
  late final AnimationController _ritmo = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  /// Cada barra empieza en un punto distinto del ciclo; si no, subirian y
  /// bajarian todas a la vez y pareceria un bloque, no un ecualizador.
  static const List<double> _desfases = <double>[0.0, 0.18, 0.36, 0.54, 0.72];

  @override
  void dispose() {
    _ritmo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          AnimatedBuilder(
            animation: _ritmo,
            builder: (BuildContext context, _) => Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                for (final double desfase in _desfases)
                  _Barra(altura: _altura(desfase)),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            widget.texto,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white54, height: 1.5),
          ),
        ],
      ),
    );
  }

  /// Un seno desplazado da el vaiven; nunca baja del todo para que la barra
  /// siga viendose.
  double _altura(double desfase) {
    final double fase = (_ritmo.value + desfase) % 1.0;
    return 14 + 34 * (0.5 + 0.5 * math.sin(fase * 2 * math.pi));
  }
}

class _Barra extends StatelessWidget {
  const _Barra({required this.altura});

  final double altura;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: altura,
    margin: const EdgeInsets.symmetric(horizontal: 3),
    decoration: BoxDecoration(
      gradient: Tema.degradado,
      borderRadius: BorderRadius.circular(4),
    ),
  );
}
