import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'animaciones.dart';
import 'dj.dart';
import 'estado_reproductor.dart';
import 'nucleo.dart';
import 'ritmos.dart';
import 'tema.dart';

/// Lo que late con la cancion: el golpe de cada pulso y, en una mezcla DJ al
/// compas, la cuenta del ultimo compas.
///
/// Sale del analisis del DJ (BPM y primer pulso) y de la posicion del motor,
/// no de un ritmo inventado: si la cancion no tiene pulso, no late.
class Latido {
  /// 1 justo en el pulso; baja a 0 antes del siguiente.
  final ValueNotifier<double> golpe = ValueNotifier<double>(0);

  /// 4, 3, 2, 1 en el ultimo compas antes del corte de una mezcla DJ; null si no.
  final ValueNotifier<int?> cuenta = ValueNotifier<int?>(null);

  /// De 0 a 1 en ese ultimo compas: cuanto se ve ya la siguiente.
  final ValueNotifier<double> mezcla = ValueNotifier<double>(0);

  void _quieto() {
    golpe.value = 0;
    cuenta.value = null;
    mezcla.value = 0;
  }

  void dispose() {
    golpe.dispose();
    cuenta.dispose();
    mezcla.dispose();
  }

  /// Lo que la salida de audio tarda en sonar: el brillo va con lo que se oye.
  static const Duration retraso = Duration(milliseconds: 70);

  /// El golpe en [posicion] (absoluta en el archivo): sube de golpe en cada
  /// pulso y cae deprisa, como el ataque de un bombo.
  static double golpeEn({required Duration posicion, required double periodoMs, required int pulsoInicioMs}) {
    final double t = (posicion - retraso).inMilliseconds - pulsoInicioMs.toDouble();
    if (t < 0 || periodoMs <= 0) return 0;
    final double fase = (t % periodoMs) / periodoMs;
    return exp(-fase * 6);
  }

  /// Cuantos pulsos quedan hasta el corte, si son 4 o menos.
  static int? cuentaEn({required Duration restante, required double periodoMs}) {
    if (periodoMs <= 0) return null;
    final double pulsos = restante.inMilliseconds / periodoMs;
    if (pulsos <= 0 || pulsos > 4) return null;
    return pulsos.ceil();
  }

  /// El latido de lo que suena, para los que estan debajo de [ConLatido].
  static Latido? de(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_LatidoHeredado>()?.latido;
}

class _LatidoHeredado extends InheritedWidget {
  const _LatidoHeredado({required this.latido, required super.child});

  final Latido latido;

  @override
  bool updateShouldNotify(_LatidoHeredado viejo) => viejo.latido != latido;
}

/// Un solo reloj para todo el reproductor. Solo corre mientras suena una
/// cancion con pulso y se permiten animaciones: parado no gasta nada.
class ConLatido extends StatefulWidget {
  const ConLatido({required this.child, super.key});

  final Widget child;

  @override
  State<ConLatido> createState() => _ConLatidoState();
}

class _ConLatidoState extends State<ConLatido> with SingleTickerProviderStateMixin {
  final Latido _latido = Latido();
  final EstadoReproductor _estado = EstadoReproductor.instancia;
  late final Ticker _reloj = createTicker(_alPaso);
  bool _permitido = false;

  @override
  void initState() {
    super.initState();
    _estado.addListener(_decidir);
    Ritmos.instancia.addListener(_decidir);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _permitido = Movimiento.continuas(context);
    _decidir();
  }

  @override
  void dispose() {
    _estado.removeListener(_decidir);
    Ritmos.instancia.removeListener(_decidir);
    _reloj.dispose();
    _latido.dispose();
    super.dispose();
  }

  Rasgos? get _rasgos {
    final Elemento? e = _estado.actual?.elemento;
    return e == null ? null : Ritmos.instancia.rasgosDe(e.uri);
  }

  void _decidir() {
    final bool debeLatir = _permitido && _estado.sonando && (_rasgos?.conPulso ?? false);
    if (debeLatir && !_reloj.isActive) {
      _reloj.start();
    } else if (!debeLatir && _reloj.isActive) {
      _reloj.stop();
      _latido._quieto();
    }
  }

  void _alPaso(Duration _) {
    final Elemento? e = _estado.actual?.elemento;
    final Rasgos? r = _rasgos;
    final double? periodo = r?.periodoMs;
    if (e == null || r == null || periodo == null) return;
    final Duration posicion = _estado.motor.position;
    final Duration absoluta = posicion + _estado.inicioDelTramo(e);
    _latido.golpe.value = Latido.golpeEn(
      posicion: absoluta,
      periodoMs: periodo,
      pulsoInicioMs: r.pulsoInicioMs ?? 0,
    );
    // La cuenta solo en una mezcla DJ al compas, que es cuando el corte cae en el pulso.
    final CorteAlCompas? corte = _estado.modoDj == null ? null : _estado.corteCargado(e);
    final Duration? total = _estado.motor.duration;
    if (corte == null || total == null || _estado.siguienteElemento == null) {
      _latido.cuenta.value = null;
      _latido.mezcla.value = 0;
      return;
    }
    final Duration restante = total - posicion;
    final int? cuenta = Latido.cuentaEn(restante: restante, periodoMs: periodo);
    _latido.cuenta.value = cuenta;
    _latido.mezcla.value =
        cuenta == null ? 0 : (1 - restante.inMilliseconds / (4 * periodo)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) => _LatidoHeredado(latido: _latido, child: widget.child);
}

/// La barra de progreso: lo escuchado ondula mientras suena y se aplana al
/// pausar, como la de Android 16 (Material 3 Expressive).
class BarraOndulada extends StatefulWidget {
  const BarraOndulada({
    required this.valor,
    required this.alSoltar,
    required this.sonando,
    super.key,
  });

  /// De 0 a 1.
  final double valor;

  /// A donde se arrastro o se toco, de 0 a 1.
  final ValueChanged<double> alSoltar;
  final bool sonando;

  @override
  State<BarraOndulada> createState() => _BarraOnduladaState();
}

class _BarraOnduladaState extends State<BarraOndulada> with TickerProviderStateMixin {
  late final AnimationController _amplitud = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
    value: widget.sonando ? 1 : 0,
  );
  late final AnimationController _fase = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  double? _arrastre;
  bool _continuas = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _continuas = Movimiento.continuas(context);
    _ajustar();
  }

  @override
  void didUpdateWidget(BarraOndulada vieja) {
    super.didUpdateWidget(vieja);
    if (vieja.sonando != widget.sonando) _ajustar();
  }

  void _ajustar() {
    if (!_continuas) {
      _fase.stop();
      _amplitud.value = 0;
      return;
    }
    _amplitud.animateTo(widget.sonando ? 1 : 0, curve: Curves.easeOutCubic);
    if (widget.sonando) {
      if (!_fase.isAnimating) _fase.repeat();
    } else {
      _fase.stop();
    }
  }

  @override
  void dispose() {
    _amplitud.dispose();
    _fase.dispose();
    super.dispose();
  }

  double _fraccion(Offset local, double ancho) => ((local.dx - 8) / max(1, ancho - 16)).clamp(0.0, 1.0);

  @override
  Widget build(BuildContext context) {
    final ColorScheme colores = Theme.of(context).colorScheme;
    final double valor = _arrastre ?? widget.valor;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints limites) {
        final double ancho = limites.maxWidth;
        return Semantics(
          slider: true,
          label: 'Posicion de la cancion',
          value: '${(valor * 100).round()} %',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (DragStartDetails d) =>
                setState(() => _arrastre = _fraccion(d.localPosition, ancho)),
            onHorizontalDragUpdate: (DragUpdateDetails d) =>
                setState(() => _arrastre = _fraccion(d.localPosition, ancho)),
            onHorizontalDragEnd: (_) {
              final double? hasta = _arrastre;
              setState(() => _arrastre = null);
              if (hasta != null) widget.alSoltar(hasta);
            },
            onTapUp: (TapUpDetails d) => widget.alSoltar(_fraccion(d.localPosition, ancho)),
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(ancho, 36),
                painter: _PintorOnda(
                  valor: valor,
                  amplitud: _amplitud,
                  fase: _fase,
                  color: colores.primary,
                  pista: Tema.pista.withValues(alpha: 0.55),
                  arrastrando: _arrastre != null,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PintorOnda extends CustomPainter {
  _PintorOnda({
    required this.valor,
    required this.amplitud,
    required this.fase,
    required this.color,
    required this.pista,
    required this.arrastrando,
  }) : super(repaint: Listenable.merge(<Listenable>[amplitud, fase]));

  final double valor;
  final Animation<double> amplitud;
  final Animation<double> fase;
  final Color color;
  final Color pista;
  final bool arrastrando;

  static const double _onda = 30;
  static const double _alto = 3.2;

  @override
  void paint(Canvas canvas, Size size) {
    final double medio = size.height / 2;
    const double x0 = 8;
    final double x1 = size.width - 8;
    final double xp = x0 + (x1 - x0) * valor.clamp(0.0, 1.0);
    final Paint linea = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    // Lo que falta, recto y tenue.
    if (x1 > xp + 8) {
      canvas.drawLine(Offset(xp + 8, medio), Offset(x1, medio), linea..color = pista);
    }
    // Lo escuchado, ondulado mientras suena.
    final double a = _alto * amplitud.value;
    final Path camino = Path()..moveTo(x0, medio);
    final double desfase = fase.value * 2 * pi;
    for (double x = x0; x <= xp; x += 2) {
      camino.lineTo(x, medio + sin((x - x0) / _onda * 2 * pi - desfase) * a);
    }
    canvas.drawPath(camino, linea..color = color);
    // El tirador: una pastilla vertical, mas alta al arrastrar.
    final double alto = arrastrando ? 24 : 18;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(xp, medio), width: 5, height: alto), const Radius.circular(3)),
      Paint()..color = Tema.texto,
    );
  }

  @override
  bool shouldRepaint(_PintorOnda viejo) =>
      viejo.valor != valor || viejo.color != color || viejo.arrastrando != arrastrando || viejo.pista != pista;
}

/// El fondo vivo: los colores de la portada se mueven despacio, como tinta en
/// agua. Son degradados radiales (sin desenfoque, que es lo caro) y se
/// repintan solos, sin reconstruir nada.
class FondoVivo extends StatefulWidget {
  const FondoVivo({super.key});

  @override
  State<FondoVivo> createState() => _FondoVivoState();
}

class _FondoVivoState extends State<FondoVivo> with SingleTickerProviderStateMixin {
  late final AnimationController _tiempo = AnimationController(vsync: this, duration: const Duration(seconds: 28));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Movimiento.continuas(context)) {
      if (!_tiempo.isAnimating) _tiempo.repeat();
    } else {
      _tiempo.stop();
    }
  }

  @override
  void dispose() {
    _tiempo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color tono = Theme.of(context).colorScheme.primary;
    final HSLColor hsl = HSLColor.fromColor(tono);
    final List<Color> colores = <Color>[
      tono,
      hsl.withHue((hsl.hue + 40) % 360).toColor(),
      hsl.withHue((hsl.hue - 35) % 360).withLightness((hsl.lightness * 0.7).clamp(0, 1)).toColor(),
    ];
    return IgnorePointer(
      child: RepaintBoundary(
        child: TweenAnimationBuilder<Color?>(
          // Al cambiar de cancion, los colores pasan de unos a otros.
          tween: ColorTween(end: tono),
          duration: const Duration(milliseconds: 900),
          builder: (BuildContext context, Color? base, _) => CustomPaint(
            painter: _PintorManchas(tiempo: _tiempo, colores: <Color>[base ?? tono, colores[1], colores[2]]),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _PintorManchas extends CustomPainter {
  _PintorManchas({required this.tiempo, required this.colores}) : super(repaint: tiempo);

  final Animation<double> tiempo;
  final List<Color> colores;

  /// Donde va cada mancha (fraccion del tamanio) y como se mueve.
  static const List<(double, double, double, double)> _manchas = <(double, double, double, double)>[
    (0.15, 0.18, 1, 0),
    (0.85, 0.32, 2, 1.7),
    (0.45, 0.78, 1, 3.4),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final double t = tiempo.value * 2 * pi;
    final double r = size.shortestSide * 0.85;
    for (int i = 0; i < _manchas.length; i++) {
      final (double x, double y, double vueltas, double desfase) = _manchas[i];
      final Offset centro = Offset(
        size.width * (x + 0.12 * sin(t * vueltas + desfase)),
        size.height * (y + 0.08 * cos(t * vueltas + desfase)),
      );
      final Paint pintura = Paint()
        ..shader = RadialGradient(
          colors: <Color>[colores[i].withValues(alpha: 0.30), colores[i].withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: centro, radius: r));
      canvas.drawCircle(centro, r, pintura);
    }
  }

  @override
  bool shouldRepaint(_PintorManchas viejo) => !listEquals(viejo.colores, colores);
}
