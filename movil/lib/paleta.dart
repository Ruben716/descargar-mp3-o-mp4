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
  static final ColorScheme neutra = ColorScheme.fromSeed(
    seedColor: Tema.acento,
    brightness: Brightness.dark,
  ).copyWith(surface: Tema.fondo);

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
      return _memoria[uri] = sacada.copyWith(surface: Tema.fondo);
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
            Color.alphaBlend(tono.withValues(alpha: 0.18), const Color(0xCC08070C)),
            Color.alphaBlend(tono.withValues(alpha: 0.10), const Color(0xF208070C)),
            Tema.fondo,
          ],
        ),
      ),
    );
  }
}
