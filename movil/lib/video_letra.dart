import 'dart:io';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'disenos_letra.dart';
import 'nucleo.dart';
import 'portadas.dart';
import 'tarjeta_letra.dart';

/// Lo que dura el video de la letra: lo que cabe en un estado de WhatsApp o
/// en una historia, y el doble.
enum DuracionVideo {
  corta(Duration(seconds: 15), '15 s'),
  larga(Duration(seconds: 30), '30 s');

  const DuracionVideo(this.tiempo, this.titulo);

  final Duration tiempo;
  final String titulo;
}

/// Un fotograma del video: el verso que suena, y cuanto se ve.
class TramoVideo {
  const TramoVideo({required this.verso, required this.duracion, this.anterior = '', this.siguiente = ''});

  final String verso;

  /// Lo que se acaba de cantar y lo que viene, tenues. Vacios si caen fuera
  /// del trozo: lo que se lee es lo que suena.
  final String anterior;
  final String siguiente;
  final Duration duracion;
}

/// Que trozo de la cancion va en el video y con que fotogramas.
class PlanVideo {
  const PlanVideo({required this.inicio, required this.duracion, required this.tramos});

  /// Donde empieza en el archivo: el instante del verso mas el desfase de la
  /// letra, que es donde se canta de verdad.
  final Duration inicio;

  /// La pedida, o menos si la cancion acaba antes. Los tramos suman esto.
  final Duration duracion;

  final List<TramoVideo> tramos;
}

/// Si un verso no dice nada: vacio, o solo notas («♪»), puntos o rayas.
bool esPausa(String verso) => !RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(verso);

/// Un video de menos de esto no merece la pena.
const Duration duracionMinimaVideo = Duration(seconds: 2);

/// Planifica el video desde el verso [indice] durante [duracion].
///
/// [instantes] va alineado con [versos] (las marcas de la letra), y a cada uno
/// se le suma [desfase], como al resaltar la linea que suena. Cada verso se ve
/// desde que entra hasta que entra el siguiente, y el ultimo hasta el final del
/// trozo. Una pausa (ver [esPausa]) no es fotograma propio: sigue en pantalla
/// el verso de antes, que es lo que se acaba de oir. [total] es lo que dura la
/// cancion, si se sabe: el video no pasa de ahi.
///
/// null si no se puede: sin marcas, el verso es una pausa o queda muy poco.
PlanVideo? planificarVideo({
  required List<String> versos,
  required List<Duration> instantes,
  required int indice,
  required Duration duracion,
  Duration desfase = Duration.zero,
  Duration total = Duration.zero,
}) {
  if (versos.length != instantes.length || indice < 0 || indice >= versos.length) return null;
  if (esPausa(versos[indice])) return null;
  Duration inicio = instantes[indice] + desfase;
  if (inicio < Duration.zero) inicio = Duration.zero;
  Duration fin = inicio + duracion;
  if (total > Duration.zero && total < fin) fin = total;
  final int largo = (fin - inicio).inMilliseconds;
  if (largo < duracionMinimaVideo.inMilliseconds) return null;

  // Los versos con texto que entran antes del final, en ms desde el inicio.
  final List<({String texto, int desde})> entran = <({String texto, int desde})>[];
  for (int i = indice; i < versos.length; i++) {
    final int desde = i == indice ? 0 : (instantes[i] + desfase - inicio).inMilliseconds;
    if (desde >= largo) break;
    if (esPausa(versos[i])) continue;
    // Dos versos con la misma marca no caben a la vez: se ve el primero.
    if (entran.isNotEmpty && desde <= entran.last.desde) continue;
    entran.add((texto: versos[i].trim(), desde: desde));
  }
  return PlanVideo(
    inicio: inicio,
    duracion: Duration(milliseconds: largo),
    tramos: <TramoVideo>[
      for (int k = 0; k < entran.length; k++)
        TramoVideo(
          verso: entran[k].texto,
          anterior: k > 0 ? entran[k - 1].texto : '',
          siguiente: k + 1 < entran.length ? entran[k + 1].texto : '',
          duracion: Duration(milliseconds: (k + 1 < entran.length ? entran[k + 1].desde : largo) - entran[k].desde),
        ),
    ],
  );
}

/// Un fotograma del video de la letra: 9:16 para estados e historias, o
/// cuadrado.
///
/// Como [TarjetaLetra], se maqueta siempre a [ancho] puntos de ancho y se
/// saca a [anchoExportado] px: 720x1280 (o 720x720) en cualquier telefono. El
/// sitio de la onda ([disenoLetra]) se deja libre: la pinta FFmpeg encima (ver
/// video_letra.py), como lo que se mueve, que aqui va quieto en su sitio.
class FotogramaVideo extends StatelessWidget {
  const FotogramaVideo({
    required this.elemento,
    required this.tramo,
    this.colores,
    this.portada,
    this.formato = FormatoTarjeta.historia,
    this.estilo = EstiloLetra.letra,
    this.claveMovil,
    super.key,
  });

  final Elemento elemento;
  final TramoVideo tramo;
  final FormatoTarjeta formato;
  final EstiloLetra estilo;

  /// La del [RepaintBoundary] de lo que se mueve: de ahi sale su PNG.
  final GlobalKey? claveMovil;

  /// La paleta de la cancion. Sin ella, la de la app.
  final ColorScheme? colores;

  /// La caratula, de fondo desenfocada y en la cabecera. Sin ella, solo los
  /// colores, y en la cabecera la portada de siempre (con las iniciales).
  final ImageProvider? portada;

  static const double ancho = 360;
  static const double anchoExportado = 720;

  /// Px por punto al exportar.
  static const double escala = anchoExportado / ancho;

  double get alto => ancho / formato.proporcion;

  bool get _alta => formato == FormatoTarjeta.historia;

  /// Lo que hay arriba y abajo del verso que suena: siempre lo mismo, haya o
  /// no anterior y siguiente, para que el verso no baile de un fotograma a otro.
  /// En la cuadrada no caben: solo el que suena.
  double get _hueco => _alta && estilo == EstiloLetra.letra ? 66 : 0;

  double get _tamano {
    final int letras = tramo.verso.length;
    if (letras <= 24) return 34;
    if (letras <= 48) return 30;
    if (letras <= 80) return 26;
    return 22;
  }

  @override
  Widget build(BuildContext context) {
    final TintaTarjeta t = TarjetaLetra.tintaDe(FondoTarjeta.cancion, colores);
    final ImageProvider? caratula = portada;
    final DisenoLetra diseno = disenoLetra(formato, estilo);
    final Rect? movil = diseno.movil;
    // Sin el tamano de letra del sistema: el video debe salir igual en todos.
    // El Material transparente da el estilo de texto del tema aunque se
    // pinte fuera de la hoja.
    return MediaQuery.withNoTextScaling(
      child: Material(
        type: MaterialType.transparency,
        child: SizedBox(
          width: ancho,
          height: alto,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: t.degradado),
                ),
              ),
              // La caratula, tan desenfocada que solo queda su luz: da el color
              // de la cancion sin pelearse con la letra.
              if (caratula != null)
                ClipRect(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 36, sigmaY: 36),
                    child: Image(
                      image: caratula,
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      opacity: const AlwaysStoppedAnimation<double>(0.6),
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              // Arriba un poco de sombra para la cabecera y abajo mas, para que
              // la onda blanca se lea sobre cualquier portada.
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: <double>[0, 0.25, 0.6, 1],
                    colors: <Color>[Color(0x59000000), Color(0x1F000000), Color(0x2E000000), Color(0x99000000)],
                  ),
                ),
              ),
              if (movil != null)
                Positioned.fromRect(
                  rect: movil,
                  child: RepaintBoundary(
                    key: claveMovil,
                    child: MovilLetra(estilo: estilo, elemento: elemento, portada: caratula),
                  ),
                ),
              Positioned.fromRect(
                rect: diseno.texto,
                child: estilo == EstiloLetra.letra
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _cabecera(t, caratula),
                          Expanded(child: _versos(t)),
                          _marca(t),
                        ],
                      )
                    : _conMovil(t),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Con el vinilo o la portada ya no hace falta la miniatura: titulo, el
  /// verso y la marca. Bajo el vinilo de la historia, centrado.
  Widget _conMovil(TintaTarjeta t) {
    final bool centrado = _alta && estilo == EstiloLetra.vinilo;
    final String artista = elemento.artista;
    final TextAlign alineado = centrado ? TextAlign.center : TextAlign.start;
    return Column(
      crossAxisAlignment: centrado ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          elemento.tema,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: alineado,
          style: TextStyle(color: t.texto, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.25),
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
                    child: Text(
                      tramo.verso,
                      textAlign: alineado,
                      style: TextStyle(
                        color: t.texto,
                        fontSize: _alta ? _tamano : _tamano - 6,
                        fontWeight: FontWeight.w800,
                        height: 1.22,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _marca(t),
      ],
    );
  }

  Widget _versos(TintaTarjeta t) {
    final TextStyle tenue = TextStyle(
      color: Colors.white.withValues(alpha: 0.42),
      fontSize: 17,
      fontWeight: FontWeight.w700,
      height: 1.3,
      letterSpacing: -0.1,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_hueco > 0)
          SizedBox(
            height: _hueco,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(tramo.anterior, maxLines: 2, overflow: TextOverflow.ellipsis, style: tenue),
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints limites) => FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: limites.maxWidth,
                    child: Text(
                      tramo.verso,
                      style: TextStyle(
                        color: t.texto,
                        fontSize: _tamano,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_hueco > 0)
          SizedBox(
            height: _hueco,
            child: Align(
              alignment: Alignment.topLeft,
              child: Text(tramo.siguiente, maxLines: 2, overflow: TextOverflow.ellipsis, style: tenue),
            ),
          ),
      ],
    );
  }

  Widget _cabecera(TintaTarjeta t, ImageProvider? caratula) {
    final String artista = elemento.artista;
    const double lado = 48;
    return Row(
      children: <Widget>[
        if (caratula == null)
          PortadaLocal(elemento: elemento, lado: lado, radio: 10)
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image(
              image: caratula,
              width: lado,
              height: lado,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => PortadaLocal(elemento: elemento, lado: lado, radio: 10),
            ),
          ),
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
                style: TextStyle(color: t.texto, fontSize: 14.5, fontWeight: FontWeight.w700, height: 1.25),
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

/// La onda como la pinta FFmpeg, pero quieta: va encima de la vista previa
/// para que se vea donde ira, y no sale en los fotogramas.
class OndaDeMuestra extends StatelessWidget {
  const OndaDeMuestra({super.key});

  @override
  Widget build(BuildContext context) => const CustomPaint(painter: _PintorOnda(), size: Size.infinite);
}

class _PintorOnda extends CustomPainter {
  const _PintorOnda();

  @override
  void paint(Canvas canvas, Size size) {
    final double medio = size.height / 2;
    final Path arriba = Path()..moveTo(0, medio);
    final List<Offset> abajo = <Offset>[];
    for (double x = 0; x <= size.width; x += 1.5) {
      final double t = x / size.width;
      // Lobulos de distinto alto, como la de una cancion con su pulso.
      final double golpe = (sin(t * 52).abs() * (0.6 + 0.4 * sin(t * 11 + 1))).clamp(0.0, 1.0);
      final double alto = medio * 0.85 * (0.1 + 0.9 * golpe);
      arriba.lineTo(x, medio - alto);
      abajo.add(Offset(x, medio + alto));
    }
    for (final Offset punto in abajo.reversed) {
      arriba.lineTo(punto.dx, punto.dy);
    }
    arriba.close();
    canvas.drawPath(arriba, Paint()..color = Colors.white.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(_PintorOnda anterior) => false;
}

/// Donde se dejan los fotogramas mientras se hace el video.
class VideoLetra {
  const VideoLetra._();

  /// La carpeta temporal del sistema (la cache, en Android). Las pruebas no
  /// tienen path_provider y ponen aqui una suya.
  @visibleForTesting
  static Future<Directory> Function() carpeta = getTemporaryDirectory;

  /// Una carpeta nueva por video: al acabar se borra entera, salga o no.
  static Future<Directory> carpetaNueva() async => (await carpeta()).createTemp('video_letra_');
}
