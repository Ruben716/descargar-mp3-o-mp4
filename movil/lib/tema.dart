import 'package:flutter/material.dart';

/// Identidad visual de la app: azul electrico sobre negro azulado.
///
/// Sigue las ideas de Material 3 Expressive: fondo casi negro para que la
/// caratula mande, un acento vibrante, formas muy redondeadas y tipografia
/// con contraste fuerte entre titulo y apoyo. Todos los colores de la app
/// salen de aqui: repetir un hex en cada pantalla es como acabo habiendo tres
/// rojos distintos para lo mismo.
class Tema {
  const Tema._();

  // Superficies: cuanto mas alta, mas clara, como hace Spotify. Asi la
  // profundidad se lee sin sombras grises, que sobre un fondo casi negro solo
  // ensucian. Todas llevan un poco de azul para que el negro no quede muerto.
  static const Color fondo = Color(0xFF05070D);
  static const Color superficie = Color(0xFF0C1322);
  static const Color superficieAlta = Color(0xFF152036);
  static const Color superficieMaxima = Color(0xFF1F2C48);

  /// Filetes de 1 px, divisores y la pista apagada del deslizador.
  static const Color contorno = Color(0xFF2A3A5E);

  /// Pista apagada de deslizadores y barras de progreso. El contorno no
  /// llegaba al 3:1 que piden los componentes; este da 4,7:1 o mas.
  static const Color pista = Color(0xFF6B7A9A);

  /// El azul de texto e iconos activos.
  ///
  /// No es el azul profundo del logo: un azul muy saturado «vibra» sobre negro
  /// y se queda corto de contraste. Este da AA (4,5:1) en las cuatro
  /// superficies, incluso en la mas clara.
  static const Color acento = Color(0xFF4D94FF);

  /// Cian hielo: el arranque del degradado de marca y el color de «Me gusta».
  static const Color acentoHielo = Color(0xFF45C8FF);

  /// El final del degradado de los botones.
  static const Color azulProfundo = Color(0xFF3A7BFF);

  /// Texto e iconos encima del acento, del degradado, del oro y del rojo.
  ///
  /// El blanco sobre el acento o sobre el rojo se queda en 3:1, que no se lee
  /// bien al sol; esta tinta da 5:1 o mas en todos. Es tambien la del logo.
  static const Color tinta = Color(0xFF040814);

  static const Color texto = Color(0xFFE8EDF8);
  static const Color textoSecundario = Color(0xFFA9B6D0);

  /// Para el texto pequenio de apoyo, en lugar de [Colors.white38].
  ///
  /// El blanco al 38 % da 3,5:1 sobre estos fondos y no llega al minimo para
  /// texto; este gris azulado da 4,6:1 o mas en todas las superficies.
  static const Color textoTenue = Color(0xFF8896B3);

  // Estados. Van aqui y no repetidos por pantallas para que «borrar» sea el
  // mismo rojo en toda la app.
  static const Color exito = Color(0xFF57D9A3);
  static const Color peligro = Color(0xFFFF5D5D);
  static const Color peligroFondo = Color(0xFF4A1717);

  /// Solo para HI-RES, SIN PERDIDA y puntuaciones: es el complementario del
  /// azul y se reconoce como sello de calidad, como el amarillo de Tidal.
  static const Color oro = Color(0xFFFFC857);
  static const Color meGusta = acentoHielo;

  /// Las dos primeras paradas del velo sobre una portada difuminada.
  static const Color veloSuave = Color(0xCC05070D);
  static const Color veloDenso = Color(0xF205070D);

  /// Degradado de marca, usado en botones y cabeceras.
  static const LinearGradient degradado = LinearGradient(
    colors: <Color>[acentoHielo, azulProfundo],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Destello azul arriba a la izquierda, detras de las cabeceras.
  ///
  /// Es lo que hace YouTube Music en su Inicio: un poco de color de marca que
  /// se funde con el negro y da profundidad sin tapar nada. Va tan suave que
  /// el texto de encima sigue por encima de 14:1.
  static const RadialGradient resplandor = RadialGradient(
    center: Alignment(-0.6, -1.1),
    radius: 1.2,
    colors: <Color>[Color(0x244D94FF), Color(0x004D94FF)],
  );

  /// Antetitulos como «SONANDO AHORA»: pequenios, en mayusculas y espaciados.
  static const TextStyle antetitulo = TextStyle(
    fontSize: 10,
    letterSpacing: 1.1,
    fontWeight: FontWeight.w800,
    color: acento,
  );

  /// El esquema de color completo, fijado rol a rol.
  ///
  /// `fromSeed` por si solo no basta: su variante gira el tono del terciario y,
  /// con una semilla azul, el terciario y sus contenedores salen rosa lila.
  /// Fijados aqui, todos los roles quedan en azul o cian salvo el rojo del
  /// error. Tambien hay que fijar `onPrimary`: el que sale de la semilla se
  /// queda en 4:1 sobre el acento y los botones rellenos lo usan para el texto.
  static final ColorScheme esquema = ColorScheme.fromSeed(
    seedColor: acento,
    brightness: Brightness.dark,
  ).copyWith(
    primary: acento,
    onPrimary: tinta,
    primaryContainer: const Color(0xFF123A80),
    onPrimaryContainer: const Color(0xFFD6E4FF),
    secondary: acentoHielo,
    onSecondary: tinta,
    secondaryContainer: const Color(0xFF173463),
    onSecondaryContainer: const Color(0xFFD6E4FF),
    tertiary: acentoHielo,
    onTertiary: tinta,
    tertiaryContainer: const Color(0xFF0E3A52),
    onTertiaryContainer: const Color(0xFFCDEFFF),
    tertiaryFixed: const Color(0xFFCDEFFF),
    tertiaryFixedDim: acentoHielo,
    onTertiaryFixed: const Color(0xFF001E2C),
    onTertiaryFixedVariant: const Color(0xFF0E3A52),
    error: peligro,
    onError: tinta,
    errorContainer: peligroFondo,
    onErrorContainer: const Color(0xFFFFDCDC),
    surface: fondo,
    onSurface: texto,
    onSurfaceVariant: textoSecundario,
    surfaceDim: fondo,
    surfaceBright: const Color(0xFF26324F),
    surfaceContainerLowest: const Color(0xFF020308),
    surfaceContainerLow: const Color(0xFF090E19),
    surfaceContainer: superficie,
    surfaceContainerHigh: superficieAlta,
    surfaceContainerHighest: superficieMaxima,
    outline: pista,
    outlineVariant: contorno,
    inverseSurface: const Color(0xFFE3EAF8),
    onInverseSurface: superficie,
    inversePrimary: const Color(0xFF1F5FD6),
    surfaceTint: acento,
  );

  static ThemeData construir() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: esquema,
      scaffoldBackgroundColor: fondo,
      splashFactory: InkSparkle.splashFactory,
      // Al abrir una pantalla, la nueva entra deslizando y la de detras se
      // desvanece: es la transicion de Android 14 en adelante.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: <TargetPlatform, PageTransitionsBuilder>{
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
      textTheme: const TextTheme(
        displaySmall: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -1),
        headlineMedium: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.6),
        titleLarge: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.4),
        titleMedium: TextStyle(fontWeight: FontWeight.w700, height: 1.25),
        bodySmall: TextStyle(height: 1.35),
        labelLarge: TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: superficie,
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
      // La barra va casi opaca sobre el fondo y separada por un filete (lo pone
      // main.dart), no por un bloque de otro color: asi pesa menos que el
      // contenido. Lo que no esta elegido va en el gris tenue, no en blanco.
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: veloDenso,
        indicatorColor: acento.withValues(alpha: 0.20),
        height: 68,
        iconTheme: WidgetStateProperty.resolveWith(
          (Set<WidgetState> estados) => IconThemeData(
            color: estados.contains(WidgetState.selected) ? acento : textoTenue,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (Set<WidgetState> estados) => estados.contains(WidgetState.selected)
              ? const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: texto)
              : const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textoTenue),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 5,
        activeTrackColor: acento,
        inactiveTrackColor: pista,
        thumbColor: Colors.white,
        overlayShape: SliderComponentShape.noOverlay,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
      ),
      // El color de la barra no se fija: sale del primario del esquema, y asi
      // en el reproductor sigue el tinte de la caratula. Solo la pista va fija.
      progressIndicatorTheme: const ProgressIndicatorThemeData(linearTrackColor: pista),
      // Los interruptores no necesitan tema propio: con onPrimary en tinta y
      // surfaceContainerHighest en superficieMaxima, el de Material 3 ya sale
      // con pulgar oscuro sobre pista azul, y apagado sobre el azul mas claro.
      // Fijarlos aqui romperia el tinte de la caratula en el ecualizador.
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        // Sin selectedColor: el de Material ya es secondaryContainer, y asi
        // dentro del reproductor sigue el tinte de la caratula.
        // Un filete en las fichas sin elegir: sin el, sobre el negro azulado
        // no se ve donde empieza una y acaba la otra.
        side: WidgetStateBorderSide.resolveWith(
          (Set<WidgetState> estados) => estados.contains(WidgetState.selected)
              ? BorderSide.none
              : const BorderSide(color: contorno),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: superficieAlta,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: superficie,
        modalBackgroundColor: superficie,
        dragHandleColor: contorno,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: superficieAlta,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: contorno),
        ),
      ),
      // Avisos oscuros, como en Tidal: el claro de serie deslumbra de noche,
      // que es justo cuando mas se usa una app de musica.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: superficieMaxima,
        contentTextStyle: const TextStyle(color: texto, fontSize: 14),
        actionTextColor: acentoHielo,
        closeIconColor: textoSecundario,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      cardTheme: CardThemeData(
        color: superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: const BorderSide(color: Color(0x0FFFFFFF)),
        ),
      ),
    );
  }
}

/// Destello de marca detras de una cabecera (ver [Tema.resplandor]).
///
/// El destello mide [alto] aunque la cabecera sea mas baja y se sale por
/// debajo sin recortarse, para que se funda poco a poco con lo que sigue. Si
/// la cabecera va dentro de una lista, sube con ella al desplazar.
class Resplandor extends StatelessWidget {
  const Resplandor({required this.hijo, this.alto = 300, super.key});

  final Widget hijo;
  final double alto;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: alto,
          child: const IgnorePointer(
            child: DecoratedBox(decoration: BoxDecoration(gradient: Tema.resplandor)),
          ),
        ),
        hijo,
      ],
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
          // Un filete blanco muy tenue da al boton aspecto de cristal sobre el
          // negro, y el brillo azul debajo lo despega del fondo sin sombra gris.
          border: Border.all(color: const Color(0x1FFFFFFF)),
          boxShadow: activo
              ? <BoxShadow>[
                  BoxShadow(
                    color: Tema.acento.withValues(alpha: 0.45),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
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
                  Icon(icono, color: Tema.tinta),
                  const SizedBox(width: 10),
                  // Flexible: con la letra grande del sistema o un texto
                  // largo («Descargar las 12 en musica») se recorta en vez de
                  // salirse del boton.
                  Flexible(
                    child: Text(
                      texto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Tema.tinta,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
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
