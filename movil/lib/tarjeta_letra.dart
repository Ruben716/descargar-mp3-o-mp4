import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'nucleo.dart';
import 'paleta.dart';
import 'portadas.dart';
import 'tema.dart';

/// La forma de la tarjeta: alta para las historias, cuadrada para lo demas.
enum FormatoTarjeta {
  historia('Historia', Icons.crop_portrait_rounded, 9 / 16),
  cuadrada('Cuadrada', Icons.crop_square_rounded, 1);

  const FormatoTarjeta(this.titulo, this.icono, this.proporcion);

  final String titulo;
  final IconData icono;

  /// Ancho entre alto.
  final double proporcion;
}

/// De que se viste el fondo de la tarjeta.
enum FondoTarjeta {
  cancion('Color de la cancion'),
  oscuro('Oscuro'),
  claro('Claro');

  const FondoTarjeta(this.titulo);

  final String titulo;
}

/// Los colores con los que se pinta una tarjeta.
typedef TintaTarjeta = ({List<Color> degradado, Color texto, Color tenue});

/// Una frase de la letra lista para compartir, como las de Spotify o Apple Music.
///
/// Se maqueta siempre al mismo tamano, [ancho] puntos de ancho, y la vista
/// previa la encoge: lo que se ve es justo lo que sale, y la imagen se saca a
/// [anchoExportado] px sea cual sea la pantalla del telefono.
class TarjetaLetra extends StatelessWidget {
  const TarjetaLetra({
    required this.elemento,
    required this.versos,
    this.formato = FormatoTarjeta.historia,
    this.fondo = FondoTarjeta.cancion,
    this.colores,
    super.key,
  });

  final Elemento elemento;

  /// De uno a [maximoVersos]; los que sobren no se pintan.
  final List<String> versos;
  final FormatoTarjeta formato;
  final FondoTarjeta fondo;

  /// La paleta de la cancion. Sin ella, la de la app.
  final ColorScheme? colores;

  static const double ancho = 360;
  static const double anchoExportado = 1080;
  static const int maximoVersos = 3;

  double get alto => ancho / formato.proporcion;

  List<String> get _frase => <String>[for (final String v in versos.take(maximoVersos)) v.trim()];

  /// Grande si es corta y algo menos si es larga. Lo que aun asi no quepa lo
  /// encoge el [FittedBox]: la frase nunca se sale de la tarjeta.
  double get _tamano {
    final int letras = _frase.fold(0, (int total, String v) => total + v.length);
    final double base = formato == FormatoTarjeta.historia ? 34 : 30;
    if (letras <= 36) return base;
    if (letras <= 80) return base - 5;
    if (letras <= 140) return base - 9;
    return base - 12;
  }

  /// Los dos tonos del fondo y los del texto.
  TintaTarjeta get tinta => tintaDe(fondo, colores);

  static TintaTarjeta tintaDe(FondoTarjeta fondo, ColorScheme? colores) {
    switch (fondo) {
      case FondoTarjeta.cancion:
        final HSLColor hsl = HSLColor.fromColor((colores ?? Paleta.neutra).primary);
        // El primario de la paleta sale vivo para leerse sobre negro; de fondo
        // entero seria chillon, asi que se apaga y se oscurece. El segundo
        // tono gira un poco el matiz, que un degradado de un solo color plano
        // parece un fallo.
        final double saturacion = min(hsl.saturation, 0.5);
        return (
          degradado: <Color>[
            hsl.withSaturation(saturacion).withLightness(0.32).toColor(),
            hsl
                .withHue((hsl.hue + 14) % 360)
                .withSaturation(saturacion * 0.85)
                .withLightness(0.12)
                .toColor(),
          ],
          texto: Colors.white,
          tenue: Colors.white.withValues(alpha: 0.7),
        );
      case FondoTarjeta.oscuro:
        return (
          degradado: const <Color>[Color(0xFF1A1D24), Color(0xFF07080B)],
          texto: Colors.white,
          tenue: Colors.white.withValues(alpha: 0.62),
        );
      case FondoTarjeta.claro:
        return (
          degradado: const <Color>[Color(0xFFFAF8F4), Color(0xFFE8E4DC)],
          texto: const Color(0xFF15171C),
          tenue: const Color(0xFF15171C).withValues(alpha: 0.6),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final TintaTarjeta t = tinta;
    final bool historia = formato == FormatoTarjeta.historia;
    // Sin el tamano de letra del sistema: la tarjeta es una imagen, y debe
    // salir igual en todos los telefonos.
    return MediaQuery.withNoTextScaling(
      child: SizedBox(
        width: ancho,
        height: alto,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: t.degradado,
            ),
          ),
          child: Stack(
            children: <Widget>[
              // La unica textura: una luz muy suave desde arriba, como de
              // papel satinado. Mas que eso ya distrae de la frase.
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.8, -1),
                      radius: 1.2,
                      colors: <Color>[Color(0x14FFFFFF), Color(0x00FFFFFF)],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: historia
                    ? const EdgeInsets.fromLTRB(30, 40, 30, 34)
                    : const EdgeInsets.fromLTRB(26, 26, 26, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _cabecera(t),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: historia ? 24 : 16),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: LayoutBuilder(
                            builder: (BuildContext context, BoxConstraints limites) => FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: limites.maxWidth,
                                child: _versos(t),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    _marca(t),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Cada verso en su parrafo, con un respiro entre uno y otro: si no, al
  /// partirse en dos lineas no se ve donde acaba uno y empieza el siguiente.
  Widget _versos(TintaTarjeta t) {
    final double tamano = _tamano;
    final TextStyle estilo = TextStyle(
      color: t.texto,
      fontSize: tamano,
      fontWeight: FontWeight.w800,
      height: 1.3,
      letterSpacing: -0.3,
    );
    final List<String> frase = _frase;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < frase.length; i++) ...<Widget>[
          if (i > 0) SizedBox(height: tamano * 0.4),
          Text(frase[i], style: estilo),
        ],
      ],
    );
  }

  Widget _cabecera(TintaTarjeta t) {
    final String artista = elemento.artista;
    return Row(
      children: <Widget>[
        PortadaLocal(elemento: elemento, lado: 46, radio: 8),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                elemento.tema,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: t.texto, fontSize: 14, fontWeight: FontWeight.w700, height: 1.25),
              ),
              if (artista.isNotEmpty)
                Text(
                  artista,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: t.tenue, fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.3),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _marca(TintaTarjeta t) => Row(
        children: <Widget>[
          Icon(Icons.graphic_eq_rounded, size: 15, color: t.tenue),
          const SizedBox(width: 6),
          Text(
            'Tumbao',
            style: TextStyle(color: t.tenue, fontSize: 12.5, fontWeight: FontWeight.w700, letterSpacing: 0.6),
          ),
        ],
      );
}

/// El verso [indice] y, si se piden, los que le siguen, saltando los huecos.
///
/// Un verso vacio en la letra es una pausa de la musica: en la tarjeta no
/// pinta nada, asi que «el siguiente» es el siguiente que dice algo.
List<String> versosDesde(List<String> versos, int indice, int cuantos) {
  if (indice < 0 || indice >= versos.length) return const <String>[];
  final List<String> salida = <String>[];
  for (int i = indice; i < versos.length && salida.length < cuantos; i++) {
    final String v = versos[i].trim();
    if (v.isNotEmpty) salida.add(v);
  }
  return salida;
}

/// La tarjeta que hay bajo [clave], en PNG a [TarjetaLetra.anchoExportado] px.
///
/// El [RepaintBoundary] se pinta a su tamano propio, sin la escala de la
/// vista previa que lo encoge: por eso basta con multiplicar su ancho.
Future<Uint8List?> capturarTarjeta(GlobalKey clave) async {
  final RenderObject? objeto = clave.currentContext?.findRenderObject();
  if (objeto is! RenderRepaintBoundary || objeto.size.isEmpty) return null;
  final ui.Image imagen = await objeto.toImage(pixelRatio: TarjetaLetra.anchoExportado / objeto.size.width);
  try {
    final ByteData? datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    return datos?.buffer.asUint8List();
  } finally {
    imagen.dispose();
  }
}

/// Abre la hoja para compartir una frase de la letra como tarjeta.
Future<void> abrirCompartirLetra(
  BuildContext context, {
  required Elemento elemento,
  required List<String> versos,
  required int indice,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Tema.superficie,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => HojaCompartirLetra(elemento: elemento, versos: versos, indice: indice),
  );
}

class HojaCompartirLetra extends StatefulWidget {
  const HojaCompartirLetra({
    required this.elemento,
    required this.versos,
    required this.indice,
    super.key,
  });

  final Elemento elemento;
  final List<String> versos;
  final int indice;

  @override
  State<HojaCompartirLetra> createState() => _HojaCompartirLetraState();
}

class _HojaCompartirLetraState extends State<HojaCompartirLetra> {
  final GlobalKey _clave = GlobalKey();

  FormatoTarjeta _formato = FormatoTarjeta.historia;
  FondoTarjeta _fondo = FondoTarjeta.cancion;
  int _cuantos = 1;
  late ColorScheme? _colores = Paleta.guardada(widget.elemento.uri);
  bool _enviando = false;

  /// Cuantos versos con texto hay desde el elegido, hasta el maximo.
  late final int _disponibles =
      versosDesde(widget.versos, widget.indice, TarjetaLetra.maximoVersos).length;

  @override
  void initState() {
    super.initState();
    _cargarColores();
  }

  Future<void> _cargarColores() async {
    final ColorScheme sacada = await Paleta.de(widget.elemento.uri);
    if (mounted && sacada != _colores) setState(() => _colores = sacada);
  }

  Future<void> _compartir() async {
    if (_enviando) return;
    setState(() => _enviando = true);
    final NavigatorState navegador = Navigator.of(context);
    final ScaffoldMessengerState? avisos = ScaffoldMessenger.maybeOf(context);
    try {
      final Uint8List? png = await capturarTarjeta(_clave);
      if (png == null) throw const ErrorNucleo('No se pudo preparar la imagen.');
      await Nucleo.compartirImagen(png, 'tumbao-letra-${DateTime.now().millisecondsSinceEpoch}.png');
      if (mounted) navegador.pop();
    } catch (_) {
      if (!mounted) return;
      // El aviso se daria debajo de la hoja, donde no se ve: primero se cierra.
      navegador.pop();
      avisos?.showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('No se pudo compartir la imagen.'),
      ));
    }
  }

  Widget _vistaPrevia(double altoMaximo) {
    final TarjetaLetra tarjeta = TarjetaLetra(
      elemento: widget.elemento,
      versos: versosDesde(widget.versos, widget.indice, _cuantos),
      formato: _formato,
      fondo: _fondo,
      colores: _colores,
    );
    return SizedBox(
      height: altoMaximo,
      child: Center(
        child: AspectRatio(
          aspectRatio: _formato.proporcion,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10)),
              ],
            ),
            // El redondeo es de la vista previa, no de la imagen: queda fuera
            // del RepaintBoundary y la tarjeta sale con sus esquinas rectas.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: FittedBox(
                child: RepaintBoundary(key: _clave, child: tarjeta),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// La muestra de cada fondo, para la ficha que lo elige.
  Widget _muestra(FondoTarjeta fondo) {
    final TintaTarjeta t = TarjetaLetra.tintaDe(fondo, _colores);
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: t.degradado,
        ),
        border: Border.all(color: Colors.white24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double altoVista = min(MediaQuery.sizeOf(context).height * 0.46, 420);
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Compartir la letra',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20),
            ),
            const SizedBox(height: 16),
            _vistaPrevia(altoVista),
            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final FormatoTarjeta f in FormatoTarjeta.values)
                  ChoiceChip(
                    avatar: Icon(f.icono, size: 18),
                    label: Text(f.titulo),
                    selected: _formato == f,
                    onSelected: (_) => setState(() => _formato = f),
                  ),
                if (_cuantos < _disponibles)
                  ActionChip(
                    avatar: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Verso siguiente'),
                    onPressed: () => setState(() => _cuantos++),
                  ),
                if (_cuantos > 1)
                  ActionChip(
                    avatar: const Icon(Icons.remove_rounded, size: 18),
                    label: const Text('Quitar verso'),
                    onPressed: () => setState(() => _cuantos--),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final FondoTarjeta f in FondoTarjeta.values)
                  ChoiceChip(
                    avatar: _muestra(f),
                    showCheckmark: false,
                    label: Text(f.titulo),
                    selected: _fondo == f,
                    onSelected: (_) => setState(() => _fondo = f),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _enviando ? null : _compartir,
              icon: _enviando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.ios_share_rounded),
              label: const Text('Compartir'),
            ),
          ],
        ),
      ),
    );
  }
}
