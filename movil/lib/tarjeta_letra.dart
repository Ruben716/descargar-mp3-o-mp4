import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'disenos_letra.dart';
import 'nucleo.dart';
import 'paleta.dart';
import 'portadas.dart';
import 'tema.dart';
import 'video_letra.dart';

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
    this.estilo = EstiloLetra.letra,
    this.colores,
    this.portada,
    super.key,
  });

  final Elemento elemento;
  final EstiloLetra estilo;

  /// La caratula grande, para el vinilo y la portada. Sin ella, la de
  /// siempre (con las iniciales si no hay).
  final ImageProvider? portada;

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
            hsl.withHue((hsl.hue + 14) % 360).withSaturation(saturacion * 0.85).withLightness(0.12).toColor(),
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
            gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: t.degradado),
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
              if (estilo != EstiloLetra.letra)
                ..._conMovil(t)
              else
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
                                child: SizedBox(width: limites.maxWidth, child: _versos(t)),
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

  /// El vinilo o la portada en su sitio y, en lo que queda, titulo, frase y
  /// marca. Bajo el vinilo de la historia, todo centrado.
  List<Widget> _conMovil(TintaTarjeta t) {
    final DisenoLetra diseno = disenoLetra(formato, estilo, video: false);
    final bool centrado = formato == FormatoTarjeta.historia && estilo == EstiloLetra.vinilo;
    final String artista = elemento.artista;
    final TextAlign alineado = centrado ? TextAlign.center : TextAlign.start;
    return <Widget>[
      Positioned.fromRect(
        rect: diseno.movil!,
        child: MovilLetra(estilo: estilo, elemento: elemento, portada: portada),
      ),
      Positioned.fromRect(
        rect: diseno.texto,
        child: Column(
          crossAxisAlignment: centrado ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              elemento.tema,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: alineado,
              style: TextStyle(color: t.texto, fontSize: 14, fontWeight: FontWeight.w700, height: 1.25),
            ),
            if (artista.isNotEmpty)
              Text(
                artista,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: alineado,
                style: TextStyle(color: t.tenue, fontSize: 12.5, fontWeight: FontWeight.w500, height: 1.3),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Align(
                  alignment: centrado ? Alignment.center : Alignment.centerLeft,
                  child: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints limites) => FittedBox(
                      fit: BoxFit.scaleDown,
                      child: SizedBox(
                        width: limites.maxWidth,
                        child: _versos(t, centrado: centrado),
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
    ];
  }

  /// Cada verso en su parrafo, con un respiro entre uno y otro: si no, al
  /// partirse en dos lineas no se ve donde acaba uno y empieza el siguiente.
  Widget _versos(TintaTarjeta t, {bool centrado = false}) {
    // Con el vinilo o la portada queda menos sitio para la frase.
    final double tamano = estilo == EstiloLetra.letra ? _tamano : _tamano - 4;
    final TextStyle letra = TextStyle(
      color: t.texto,
      fontSize: tamano,
      fontWeight: FontWeight.w800,
      height: 1.3,
      letterSpacing: -0.3,
    );
    final List<String> frase = _frase;
    return Column(
      crossAxisAlignment: centrado ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < frase.length; i++) ...<Widget>[
          if (i > 0) SizedBox(height: tamano * 0.4),
          Text(frase[i], style: letra, textAlign: centrado ? TextAlign.center : TextAlign.start),
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
    mainAxisSize: MainAxisSize.min,
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

/// La tarjeta que hay bajo [clave], en PNG a [ancho] px (la del video de la
/// letra, a [FotogramaVideo.anchoExportado]).
///
/// El [RepaintBoundary] se pinta a su tamano propio, sin la escala de la
/// vista previa que lo encoge: por eso basta con multiplicar su ancho.
Future<Uint8List?> capturarTarjeta(GlobalKey clave, {double ancho = TarjetaLetra.anchoExportado}) async {
  final RenderObject? objeto = clave.currentContext?.findRenderObject();
  if (objeto is! RenderRepaintBoundary || objeto.size.isEmpty) return null;
  final ui.Image imagen = await objeto.toImage(pixelRatio: ancho / objeto.size.width);
  try {
    final ByteData? datos = await imagen.toByteData(format: ui.ImageByteFormat.png);
    return datos?.buffer.asUint8List();
  } finally {
    imagen.dispose();
  }
}

/// Abre la hoja para compartir una frase de la letra como tarjeta o, si la
/// letra esta sincronizada, como video.
///
/// [instantes] son las marcas de la letra, alineadas con [versos], y
/// [desfase] su ajuste de sincronia: el verso se canta en el archivo en
/// `instantes[i] + desfase`. Sin marcas solo se ofrece la imagen.
Future<void> abrirCompartirLetra(
  BuildContext context, {
  required Elemento elemento,
  required List<String> versos,
  required int indice,
  List<Duration>? instantes,
  Duration desfase = Duration.zero,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    backgroundColor: Tema.superficie,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) =>
        HojaCompartirLetra(elemento: elemento, versos: versos, indice: indice, instantes: instantes, desfase: desfase),
  );
}

/// Como se comparte la frase: tarjeta quieta o video con el audio.
enum ModoCompartir { imagen, video }

class HojaCompartirLetra extends StatefulWidget {
  const HojaCompartirLetra({
    required this.elemento,
    required this.versos,
    required this.indice,
    this.instantes,
    this.desfase = Duration.zero,
    super.key,
  });

  final Elemento elemento;
  final List<String> versos;
  final int indice;

  /// Las marcas de la letra sincronizada, alineadas con [versos]. null si no
  /// lo esta: entonces no hay video.
  final List<Duration>? instantes;
  final Duration desfase;

  @override
  State<HojaCompartirLetra> createState() => _HojaCompartirLetraState();
}

class _HojaCompartirLetraState extends State<HojaCompartirLetra> {
  final GlobalKey _clave = GlobalKey();
  final GlobalKey _claveVideo = GlobalKey();
  final GlobalKey _claveMovil = GlobalKey();

  FormatoTarjeta _formato = FormatoTarjeta.historia;
  FondoTarjeta _fondo = FondoTarjeta.cancion;
  EstiloLetra _estilo = EstiloLetra.letra;
  int _cuantos = 1;
  late ColorScheme? _colores = Paleta.guardada(widget.elemento.uri);
  bool _enviando = false;

  ModoCompartir _modo = ModoCompartir.imagen;
  DuracionVideo _duracion = DuracionVideo.corta;

  /// La caratula para el fondo del video; null mientras no llega o si no hay.
  late ImageProvider? _portada = _proveedor(Nucleo.caratulaGuardada(widget.elemento.uri));

  /// Que fotograma se esta pintando para el video; con todos ya pintados,
  /// se estan uniendo.
  int _pintado = 0;

  /// Cuantos versos con texto hay desde el elegido, hasta el maximo.
  late final int _disponibles = versosDesde(widget.versos, widget.indice, TarjetaLetra.maximoVersos).length;

  /// El video se ofrece solo si hay marcas y el verso deja un trozo que valga.
  late final bool _admiteVideo = _planDe(DuracionVideo.corta) != null;

  @override
  void initState() {
    super.initState();
    _cargarColores();
    _cargarPortada();
  }

  Future<void> _cargarColores() async {
    final ColorScheme sacada = await Paleta.de(widget.elemento.uri);
    if (mounted && sacada != _colores) setState(() => _colores = sacada);
  }

  static ImageProvider? _proveedor(Uint8List? datos) => datos == null || datos.isEmpty ? null : MemoryImage(datos);

  Future<void> _cargarPortada() async {
    if (_portada != null) return;
    final ImageProvider? traida = _proveedor(await Nucleo.caratula(widget.elemento.uri));
    if (mounted && traida != null) setState(() => _portada = traida);
  }

  PlanVideo? _planDe(DuracionVideo duracion) {
    final List<Duration>? instantes = widget.instantes;
    if (instantes == null) return null;
    return planificarVideo(
      versos: widget.versos,
      instantes: instantes,
      indice: widget.indice,
      duracion: duracion.tiempo,
      desfase: widget.desfase,
      total: Duration(milliseconds: (widget.elemento.duracion * 1000).round()),
    );
  }

  /// Pinta cada fotograma en la vista previa, lo guarda en PNG y se los pasa
  /// a FFmpeg con el trozo de audio. Al acabar, como con la imagen, se
  /// comparte y se cierra la hoja; si falla, se cierra y se avisa.
  Future<void> _crearVideo() async {
    final PlanVideo? plan = _planDe(_duracion);
    if (_enviando || plan == null) return;
    setState(() {
      _enviando = true;
      _pintado = 0;
    });
    final NavigatorState navegador = Navigator.of(context);
    final ScaffoldMessengerState? avisos = ScaffoldMessenger.maybeOf(context);
    final ImageProvider? portada = _portada;
    Directory? carpeta;
    try {
      // Que la caratula este ya descodificada: si no, el primer fotograma
      // podria salir sin ella.
      if (portada != null) await precacheImage(portada, context);
      carpeta = await VideoLetra.carpetaNueva();
      final DisenoLetra diseno = disenoLetra(_formato, _estilo);
      final Rect? sitioMovil = diseno.movil;
      String? movil;
      final List<({String png, int ms})> fotogramas = <({String png, int ms})>[];
      for (int i = 0; i < plan.tramos.length; i++) {
        if (!mounted) return;
        setState(() => _pintado = i);
        await WidgetsBinding.instance.endOfFrame;
        final Uint8List? png = await capturarTarjeta(_claveVideo, ancho: FotogramaVideo.anchoExportado);
        if (png == null) throw const ErrorNucleo('No se pudo pintar el video.');
        final File archivo = File('${carpeta.path}/$i.png');
        await archivo.writeAsBytes(png, flush: true);
        fotogramas.add((png: archivo.path, ms: plan.tramos[i].duracion.inMilliseconds));
        // Lo que se mueve es igual en todos: se saca una vez. Si no sale, el
        // video se hace igual, con el que trae pintado cada fotograma.
        if (i == 0 && sitioMovil != null) {
          final Uint8List? suelto = await capturarTarjeta(
            _claveMovil,
            ancho: sitioMovil.width * FotogramaVideo.escala * _estilo.escalaMovil,
          );
          if (suelto != null) {
            final File archivoMovil = File('${carpeta.path}/movil.png');
            await archivoMovil.writeAsBytes(suelto, flush: true);
            movil = archivoMovil.path;
          }
        }
      }
      if (mounted) setState(() => _pintado = plan.tramos.length);
      await Nucleo.videoLetra(
        uri: widget.elemento.uri,
        inicioMs: plan.inicio.inMilliseconds,
        duracionMs: plan.duracion.inMilliseconds,
        fotogramas: fotogramas,
        diseno: disenoParaFfmpeg(_formato, _estilo, movil: movil),
      );
      if (mounted) navegador.pop();
    } catch (_) {
      if (!mounted) return;
      // El aviso se daria debajo de la hoja, donde no se ve: primero se cierra.
      navegador.pop();
      avisos?.showSnackBar(
        const SnackBar(behavior: SnackBarBehavior.floating, content: Text('No se pudo crear el video.')),
      );
    } finally {
      try {
        await carpeta?.delete(recursive: true);
      } catch (_) {
        // Queda en la cache, que Android vacia cuando le hace falta.
      }
    }
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
      avisos?.showSnackBar(
        const SnackBar(behavior: SnackBarBehavior.floating, content: Text('No se pudo compartir la imagen.')),
      );
    }
  }

  Widget _vistaPrevia(double altoMaximo) {
    if (_modo == ModoCompartir.video) return _vistaVideo(altoMaximo);
    final TarjetaLetra tarjeta = TarjetaLetra(
      elemento: widget.elemento,
      versos: versosDesde(widget.versos, widget.indice, _cuantos),
      formato: _formato,
      fondo: _fondo,
      estilo: _estilo,
      colores: _colores,
      portada: _portada,
    );
    return _marcoPrevia(altoMaximo, _formato.proporcion, RepaintBoundary(key: _clave, child: tarjeta));
  }

  /// El primer fotograma del video; mientras se hace, el que se esta pintando.
  Widget _vistaVideo(double altoMaximo) {
    final PlanVideo? plan = _planDe(_duracion);
    if (plan == null || plan.tramos.isEmpty) return SizedBox(height: altoMaximo);
    final TramoVideo tramo = plan.tramos[_enviando ? min(_pintado, plan.tramos.length - 1) : 0];
    return _marcoPrevia(
      altoMaximo,
      _formato.proporcion,
      Stack(
        children: <Widget>[
          RepaintBoundary(
            key: _claveVideo,
            child: FotogramaVideo(
              elemento: widget.elemento,
              tramo: tramo,
              colores: _colores,
              portada: _portada,
              formato: _formato,
              estilo: _estilo,
              claveMovil: _claveMovil,
            ),
          ),
          // Fuera del RepaintBoundary: la de verdad la pinta FFmpeg con el audio.
          Positioned.fromRect(rect: disenoLetra(_formato, _estilo).onda, child: const OndaDeMuestra()),
        ],
      ),
    );
  }

  Widget _marcoPrevia(double altoMaximo, double proporcion, Widget lienzo) {
    return SizedBox(
      height: altoMaximo,
      child: Center(
        child: AspectRatio(
          aspectRatio: proporcion,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              boxShadow: const <BoxShadow>[BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 10))],
            ),
            // El redondeo es de la vista previa, no de la imagen: queda fuera
            // del RepaintBoundary y la tarjeta sale con sus esquinas rectas.
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: FittedBox(child: lienzo),
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
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: t.degradado),
        border: Border.all(color: Colors.white24),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double altoVista = min(MediaQuery.sizeOf(context).height * 0.42, 400);
    // El boton va fijo debajo: con los ajustes, en un telefono normal ya no
    // cabia y habia que bajar a buscarlo.
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text('Compartir la letra', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontSize: 20)),
                  const SizedBox(height: 16),
                  if (_admiteVideo) ...<Widget>[
                    SegmentedButton<ModoCompartir>(
                      showSelectedIcon: false,
                      segments: const <ButtonSegment<ModoCompartir>>[
                        ButtonSegment<ModoCompartir>(
                          value: ModoCompartir.imagen,
                          label: Text('Imagen'),
                          icon: Icon(Icons.image_outlined),
                        ),
                        ButtonSegment<ModoCompartir>(
                          value: ModoCompartir.video,
                          label: Text('Video'),
                          icon: Icon(Icons.movie_outlined),
                        ),
                      ],
                      selected: <ModoCompartir>{_modo},
                      onSelectionChanged: _enviando ? null : (Set<ModoCompartir> s) => setState(() => _modo = s.first),
                    ),
                    const SizedBox(height: 16),
                  ],
                  _vistaPrevia(altoVista),
                  const SizedBox(height: 20),
                  ...(_modo == ModoCompartir.video ? _ajustesVideo() : _ajustesImagen()),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: _modo == ModoCompartir.video ? _botonVideo() : _botonImagen(),
          ),
        ],
      ),
    );
  }

  Widget _botonImagen() => FilledButton.icon(
    onPressed: _enviando ? null : _compartir,
    icon: _enviando ? const _Girando() : const Icon(Icons.ios_share_rounded),
    label: const Text('Compartir'),
  );

  Widget _botonVideo() {
    final int versos = _planDe(_duracion)?.tramos.length ?? 0;
    final String avance = _pintado >= versos ? 'Uniendo el video' : 'Pintando ${_pintado + 1} de $versos';
    return FilledButton.icon(
      onPressed: _enviando ? null : _crearVideo,
      icon: _enviando ? const _Girando() : const Icon(Icons.movie_creation_outlined),
      label: Text(_enviando ? avance : 'Crear video'),
    );
  }

  /// Letra, vinilo o portada: el mismo para la imagen y el video.
  Widget _chipsEstilo() => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: <Widget>[
      for (final EstiloLetra e in EstiloLetra.values)
        ChoiceChip(
          avatar: Icon(e.icono, size: 18),
          label: Text(e.titulo),
          selected: _estilo == e,
          onSelected: _enviando ? null : (_) => setState(() => _estilo = e),
        ),
    ],
  );

  List<Widget> _ajustesImagen() => <Widget>[
    _chipsEstilo(),
    const SizedBox(height: 10),
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
  ];

  List<Widget> _ajustesVideo() {
    final PlanVideo? plan = _planDe(_duracion);
    final int versos = plan?.tramos.length ?? 0;
    final int segundos = ((plan?.duracion.inMilliseconds ?? 0) / 1000).round();
    return <Widget>[
      _chipsEstilo(),
      const SizedBox(height: 10),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <Widget>[
          for (final FormatoTarjeta f in FormatoTarjeta.values)
            ChoiceChip(
              avatar: Icon(f.icono, size: 18),
              label: Text(f.titulo),
              selected: _formato == f,
              onSelected: _enviando ? null : (_) => setState(() => _formato = f),
            ),
          for (final DuracionVideo d in DuracionVideo.values)
            ChoiceChip(
              label: Text(d.titulo),
              selected: _duracion == d,
              onSelected: _enviando ? null : (_) => setState(() => _duracion = d),
            ),
        ],
      ),
      const SizedBox(height: 10),
      Text(
        '$versos ${versos == 1 ? 'verso' : 'versos'} en $segundos s, con el audio de ese trozo.',
        style: const TextStyle(color: Tema.textoTenue, fontSize: 12.5),
      ),
    ];
  }
}

/// La rueda de espera dentro de un boton.
class _Girando extends StatelessWidget {
  const _Girando();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
}
