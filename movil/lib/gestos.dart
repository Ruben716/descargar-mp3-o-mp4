import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Deslizar a los lados para pasar de cancion, como en Spotify o YouTube Music.
///
/// Lo de dentro sigue al dedo. Si se suelta lejos o rapido, sale por ese lado,
/// se cambia la cancion y lo nuevo entra por el contrario; si no, vuelve a su
/// sitio. Hacia la izquierda es la siguiente; hacia la derecha, la anterior.
/// Sin anterior o siguiente, el gesto se frena como contra una pared.
class DeslizarParaCambiar extends StatefulWidget {
  const DeslizarParaCambiar({
    required this.child,
    this.alSiguiente,
    this.alAnterior,
    super.key,
  });

  final Widget child;
  final VoidCallback? alSiguiente;
  final VoidCallback? alAnterior;

  /// Que parte del ancho hay que arrastrar para que cuente.
  static const double umbral = 0.28;

  /// O con que rapidez, en pixeles por segundo.
  static const double velocidad = 700;

  @override
  State<DeslizarParaCambiar> createState() => _DeslizarParaCambiarState();
}

class _DeslizarParaCambiarState extends State<DeslizarParaCambiar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this);
  double _x = 0;
  double _ancho = 1;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() => setState(() => _x = _anim.value));
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  Future<void> _ir(double hasta, {required Duration duracion, Curve curva = Curves.easeOut}) {
    _anim.value = _x;
    return _anim.animateTo(hasta, duration: duracion, curve: curva);
  }

  void _arrastrar(DragUpdateDetails d) {
    _anim.stop();
    final bool haciaSiguiente = _x + d.delta.dx < 0;
    final bool posible = haciaSiguiente ? widget.alSiguiente != null : widget.alAnterior != null;
    // Contra la pared el dedo arrastra mucho menos: se nota que no hay mas.
    setState(() => _x += d.delta.dx * (posible ? 1 : 0.25));
  }

  Future<void> _soltar(DragEndDetails d) async {
    final double v = d.primaryVelocity ?? 0;
    final bool lejos = _x.abs() > _ancho * DeslizarParaCambiar.umbral;
    final bool rapido = v.abs() > DeslizarParaCambiar.velocidad && v.sign == _x.sign;
    final VoidCallback? accion = _x < 0 ? widget.alSiguiente : widget.alAnterior;
    _anim.value = _x;
    if (accion == null || !(lejos || rapido)) {
      await _ir(0, duracion: const Duration(milliseconds: 380), curva: Curves.elasticOut);
      return;
    }
    final double lado = _x.sign;
    unawaited(HapticFeedback.lightImpact());
    await _ir(lado * _ancho, duracion: const Duration(milliseconds: 160));
    accion();
    if (!mounted) return;
    // Lo nuevo entra por el lado contrario.
    setState(() => _x = -lado * _ancho * 0.35);
    await _ir(0, duracion: const Duration(milliseconds: 260), curva: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints limites) {
        _ancho = limites.maxWidth.isFinite ? limites.maxWidth : MediaQuery.of(context).size.width;
        final double avance = (_x.abs() / _ancho).clamp(0.0, 1.0);
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragUpdate: _arrastrar,
          onHorizontalDragEnd: _soltar,
          child: Opacity(
            opacity: 1 - avance * 0.5,
            child: Transform.translate(
              offset: Offset(_x, 0),
              child: Transform.rotate(angle: _x / _ancho * 0.06, child: widget.child),
            ),
          ),
        );
      },
    );
  }
}
