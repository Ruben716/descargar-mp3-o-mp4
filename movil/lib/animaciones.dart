import 'dart:math';

import 'package:flutter/material.dart';

import 'tema.dart';

/// Duraciones de la app, en un solo sitio.
///
/// Siguen las pautas de Material: cortas para responder a un toque, algo mas
/// largas para cambiar de pantalla. Si el sistema pide reducir animaciones
/// (ajustes de accesibilidad), todas se quedan en nada.
class Movimiento {
  Movimiento._();

  static const Duration corto = Duration(milliseconds: 150);
  static const Duration medio = Duration(milliseconds: 250);
  static const Duration largo = Duration(milliseconds: 400);

  static bool reducido(BuildContext context) => MediaQuery.of(context).disableAnimations;

  static Duration de(BuildContext context, Duration d) => reducido(context) ? Duration.zero : d;
}

/// Aparece subiendo un poco y haciendose visible, con un retraso segun su sitio.
///
/// Para listas que llegan de golpe (resultados de busqueda): en vez de saltar
/// todas a la vez, entran una tras otra y el ojo sigue el orden. Solo las
/// primeras se retrasan; las de mas abajo ya estan fuera de la vista.
class AparecerEscalonado extends StatelessWidget {
  const AparecerEscalonado({required this.indice, required this.child, super.key});

  final int indice;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Movimiento.reducido(context)) return child;
    final int retraso = min(indice, 8) * 40;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: 280 + retraso),
      curve: Interval(retraso / (280 + retraso), 1, curve: Curves.easeOutCubic),
      builder: (BuildContext context, double t, Widget? hijo) => Opacity(
        opacity: t,
        child: Transform.translate(offset: Offset(0, (1 - t) * 18), child: hijo),
      ),
      child: child,
    );
  }
}

/// Tres barras que suben y bajan: lo que esta sonando ahora mismo.
///
/// Sustituye al icono quieto del ecualizador. Parado, se quedan bajas.
class BarrasSonando extends StatefulWidget {
  const BarrasSonando({required this.sonando, this.color = Tema.acento, this.alto = 16, super.key});

  final bool sonando;
  final Color color;
  final double alto;

  @override
  State<BarrasSonando> createState() => _BarrasSonandoState();
}

class _BarrasSonandoState extends State<BarrasSonando> with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.sonando) _anim.repeat();
  }

  @override
  void didUpdateWidget(BarrasSonando antes) {
    super.didUpdateWidget(antes);
    if (widget.sonando && !_anim.isAnimating) _anim.repeat();
    if (!widget.sonando && _anim.isAnimating) _anim.stop();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool quieto = Movimiento.reducido(context);
    return SizedBox(
      width: widget.alto,
      height: widget.alto,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (BuildContext context, _) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (int i = 0; i < 3; i++)
              Container(
                width: widget.alto / 4.5,
                // Cada barra con su desfase, para que no suban a la vez.
                height: widget.alto *
                    (quieto || !widget.sonando
                        ? 0.35
                        : 0.3 + 0.7 * (0.5 + 0.5 * sin((_anim.value + i * 0.33) * 2 * pi)).abs()),
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Encoge un poco al pulsar, como un boton fisico, y vuelve al soltar.
class AlPulsarEncoge extends StatefulWidget {
  const AlPulsarEncoge({required this.child, super.key});

  final Widget child;

  @override
  State<AlPulsarEncoge> createState() => _AlPulsarEncogeState();
}

class _AlPulsarEncogeState extends State<AlPulsarEncoge> {
  bool _pulsado = false;

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => setState(() => _pulsado = true),
        onPointerUp: (_) => setState(() => _pulsado = false),
        onPointerCancel: (_) => setState(() => _pulsado = false),
        child: AnimatedScale(
          scale: _pulsado ? 0.94 : 1,
          duration: Movimiento.de(context, Movimiento.corto),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}
