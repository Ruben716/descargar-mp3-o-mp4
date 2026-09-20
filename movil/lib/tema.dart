import 'package:flutter/material.dart';

/// Identidad visual de la app.
///
/// Sigue las ideas de Material 3 Expressive: fondo casi negro para que la
/// caratula mande, un acento vibrante, formas muy redondeadas y tipografia
/// con contraste fuerte entre titulo y apoyo.
class Tema {
  const Tema._();

  static const Color fondo = Color(0xFF08070C);
  static const Color superficie = Color(0xFF141220);
  static const Color superficieAlta = Color(0xFF1E1B2E);
  static const Color acento = Color(0xFFB69CFF);
  static const Color acentoCalido = Color(0xFFFF8FB1);

  /// Degradado de marca, usado en botones y cabeceras.
  static const LinearGradient degradado = LinearGradient(
    colors: <Color>[acento, acentoCalido],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static ThemeData construir() {
    final ColorScheme colores = ColorScheme.fromSeed(
      seedColor: acento,
      brightness: Brightness.dark,
    ).copyWith(
      surface: fondo,
      surfaceContainer: superficie,
      surfaceContainerHigh: superficieAlta,
      primary: acento,
      secondary: acentoCalido,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colores,
      scaffoldBackgroundColor: fondo,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displaySmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -1),
        headlineMedium: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.6),
        titleMedium: TextStyle(fontWeight: FontWeight.w700, height: 1.25),
        bodySmall: TextStyle(height: 1.35),
        labelLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: superficie,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(26),
          borderSide: const BorderSide(color: acento, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: superficie,
        indicatorColor: acento.withValues(alpha: 0.22),
        height: 68,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 5,
        activeTrackColor: acento,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide.none,
      ),
    );
  }
}

/// Boton principal con el degradado de marca.
class BotonDegradado extends StatelessWidget {
  const BotonDegradado({
    required this.texto,
    required this.icono,
    required this.alPulsar,
    super.key,
  });

  final String texto;
  final IconData icono;
  final VoidCallback? alPulsar;

  @override
  Widget build(BuildContext context) {
    final bool activo = alPulsar != null;
    return Opacity(
      opacity: activo ? 1 : 0.45,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: Tema.degradado,
          borderRadius: BorderRadius.circular(22),
          boxShadow: activo
              ? <BoxShadow>[
                  BoxShadow(
                    color: Tema.acento.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: alPulsar,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 17),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icono, color: Colors.black87),
                  const SizedBox(width: 10),
                  Text(
                    texto,
                    style: const TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
