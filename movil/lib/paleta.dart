import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'nucleo.dart';
import 'tema.dart';

/// Saca los colores de la portada para vestir con ellos el reproductor.
///
/// Es lo que hacen las apps de musica buenas: la pantalla entera se tinta con
/// la caratula, y cada cancion se siente distinta sin haber disenado nada a
/// mano. Flutter lo trae de serie, asi que no hace falta ninguna libreria.
class Paleta {
  const Paleta._();

  /// Sacar los colores de una imagen cuesta bastante, y la pantalla se
  /// reconstruye a cada segundo mientras suena: sin recordarlo se recalcularia
  /// una y otra vez y se notaria en los tirones.
  static final Map<String, ColorScheme> _memoria = <String, ColorScheme>{};
  static final Map<String, Future<ColorScheme>> _enCurso = <String, Future<ColorScheme>>{};

  /// La paleta del tema, para cuando la pista no tiene portada.
  ///
  /// Es el esquema de la marca tal cual y no uno sacado de su semilla: asi,
  /// sin caratula, el reproductor sale con el mismo azul y cian que el resto
  /// de la app, y no con el pastel y el terciario rosado que da la semilla.
  static final ColorScheme neutra = Tema.esquema;

  static ColorScheme? guardada(String uri) => _memoria[uri];

  static Future<ColorScheme> de(String uri) {
    final ColorScheme? ya = _memoria[uri];
    if (ya != null) return Future<ColorScheme>.value(ya);
    return _enCurso[uri] ??= _calcular(uri);
  }

  static Future<ColorScheme> _calcular(String uri) async {
    try {
      final Uint8List? portada = await Nucleo.caratula(uri);
      if (portada == null || portada.isEmpty) return _memoria[uri] = neutra;
      final ColorScheme sacada = await ColorScheme.fromImageProvider(
        provider: MemoryImage(portada),
        brightness: Brightness.dark,
      );
      // El fondo de la app se mantiene casi negro aunque la portada sea clara:
      // con el fondo tenido, la propia caratula deja de destacar.
      //
      // El primario es el color del titulo: de una portada muy oscura sale
      // apagado y casi no se lee sobre ese fondo, asi que se le sube la luz.
      return _memoria[uri] = sacada.copyWith(
        surface: Tema.fondo,
        primary: conContraste(sacada.primary, Tema.fondo),
      );
    } catch (_) {
      return _memoria[uri] = neutra;
    } finally {
      _enCurso.remove(uri);
    }
  }

  /// Al borrar una descarga su paleta ya no vale.
  static void olvidar(String uri) {
    _memoria.remove(uri);
    _enCurso.remove(uri);
  }

  @visibleForTesting
  static void vaciar() {
    _memoria.clear();
    _enCurso.clear();
  }
}

/// El contraste entre dos colores segun WCAG: de 1 (iguales) a 21 (negro y blanco).
double contraste(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

/// [color] con la luz justa para leerse sobre [fondo]: al menos [minimo] a 1.
///
/// Solo sube la luminosidad en HSL, sin tocar el tono ni la saturacion, y lo
/// minimo que haga falta: el titulo sigue siendo del color de la portada,
/// solo que mas claro. Si ya llegaba, se devuelve tal cual. La luminancia
/// crece siempre con la luz en HSL, asi que basta una busqueda binaria.
Color conContraste(Color color, Color fondo, {double minimo = 4.5}) {
  if (contraste(color, fondo) >= minimo) return color;
  final HSLColor hsl = HSLColor.fromColor(color);
  double bajo = hsl.lightness;
  double alto = 1;
  for (int i = 0; i < 20; i++) {
    final double medio = (bajo + alto) / 2;
    if (contraste(hsl.withLightness(medio).toColor(), fondo) >= minimo) {
      alto = medio;
    } else {
      bajo = medio;
    }
  }
  return hsl.withLightness(alto).toColor();
}

/// Aplica la paleta de una pista a todo lo que tenga debajo.
///
/// Mientras se calcula se sigue viendo la de antes, no un parpadeo: cambiar de
/// cancion no deberia apagar la pantalla un instante.
class ConPaletaDe extends StatefulWidget {
  const ConPaletaDe({required this.uri, required this.hijo, super.key});

  final String uri;
  final Widget hijo;

  @override
  State<ConPaletaDe> createState() => _ConPaletaDeState();
}

class _ConPaletaDeState extends State<ConPaletaDe> {
  late ColorScheme _colores = Paleta.guardada(widget.uri) ?? Paleta.neutra;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(ConPaletaDe anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.uri != widget.uri) _cargar();
  }

  Future<void> _cargar() async {
    final ColorScheme sacada = await Paleta.de(widget.uri);
    if (mounted && sacada != _colores) setState(() => _colores = sacada);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        colorScheme: _colores,
        sliderTheme: base.sliderTheme.copyWith(
          activeTrackColor: _colores.primary,
          thumbColor: _colores.primary,
        ),
        iconTheme: base.iconTheme.copyWith(color: _colores.primary),
      ),
      child: widget.hijo,
    );
  }
}

/// El velo que va sobre la portada difuminada, tenido con su propio color.
///
/// Sin velo el texto no se lee encima de la imagen; con uno gris se pierde el
/// color que se acaba de sacar. Asi se conserva el tono y el texto se lee.
class VeloDePaleta extends StatelessWidget {
  const VeloDePaleta({super.key});

  @override
  Widget build(BuildContext context) {
    final Color tono = Theme.of(context).colorScheme.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color.alphaBlend(tono.withValues(alpha: 0.18), Tema.veloSuave),
            Color.alphaBlend(tono.withValues(alpha: 0.10), Tema.veloDenso),
            Tema.fondo,
          ],
        ),
      ),
    );
  }
}
