import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'animaciones.dart';
import 'catalogo.dart';
import 'estado_reproductor.dart';
import 'letras.dart';
import 'nucleo.dart';
import 'tarjeta_letra.dart';
import 'tema.dart';
import 'traducir_letra.dart';

/// La letra de lo que suena, resaltando la linea que toca.
class PanelLetras extends StatefulWidget {
  const PanelLetras({required this.elemento, super.key});

  final Elemento elemento;

  @override
  State<PanelLetras> createState() => _PanelLetrasState();
}

class _PanelLetrasState extends State<PanelLetras> {
  final EstadoReproductor _estado = EstadoReproductor.instancia;
  final ScrollController _desplazamiento = ScrollController();

  /// Alto fijo por linea: hace falta saberlo para poder centrar la que suena
  /// sin medir el texto, que con lineas de dos renglones seria un lio.
  // Cabe un verso de dos lineas al tamanio del que suena (19 x 1,25 x 2): con
  // 46 se salia por dos pixeles.
  static const double _alto = 54;

  Letra? _letra;
  int _resaltada = -1;

  /// La letra en castellano, una por linea, si se pidio y se pudo.
  List<String>? _traduccion;
  bool _traduciendo = false;

  /// Mientras se escucha la voz para cuadrar la letra.
  bool _escuchando = false;

  /// Las canciones a las que ya se intento cuadrar la letra sola: si no salio
  /// un ajuste claro, no se repite cada vez que se abre.
  static const String clavePorVoz = 'letras_por_voz';

  /// Alto de cada linea: con traduccion debajo hace falta mas.
  double get _altoLinea => _traduccion == null ? _alto : _alto + 22;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(PanelLetras anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.elemento.uri != widget.elemento.uri) _cargar();
  }

  @override
  void dispose() {
    _desplazamiento.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool deNuevo = false}) async {
    setState(() {
      _letra = null;
      _resaltada = -1;
      _traduccion = null;
    });
    final Elemento e = widget.elemento;
    final ({String artista, String tema}) partes = e.partes;
    final Letra letra = await Letras.de(
      uri: e.uri,
      nombre: e.nombre,
      duracion: e.duracion,
      artista: partes.artista,
      tema: partes.tema,
      deNuevo: deNuevo,
    );
    if (!mounted || e.uri != widget.elemento.uri) return;
    setState(() => _letra = letra);
    // La primera vez, si nadie la ha ajustado a mano, se intenta sola. Una de
    // otra version, tambien al buscarla otra vez: hasta cuadrarla no se mueve.
    final bool toca = letra.porCuadrar
        ? deNuevo || !await _yaIntentada(e.uri)
        : letra.sincronizada && letra.desfase == Duration.zero && !await _yaIntentada(e.uri);
    if (toca) await _ajustarConLaVoz(sola: true);
  }

  Future<bool> _yaIntentada(String uri) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      return (prefs.getStringList(clavePorVoz) ?? const <String>[]).contains(uri);
    } catch (_) {
      return true;
    }
  }

  Future<void> _anotarIntentada(String uri) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> todas = <String>[...?prefs.getStringList(clavePorVoz), uri];
      // Las mas viejas se olvidan: que la lista no crezca sin fin.
      await prefs.setStringList(clavePorVoz, todas.skip(todas.length > 500 ? todas.length - 500 : 0).toList());
    } catch (_) {
      // Si no se puede apuntar, a lo sumo se vuelve a intentar otro dia.
    }
  }

  /// Escucha donde entra la voz y corre la letra para que cada verso caiga
  /// ahi (ver voz.py). [sola]: sin que nadie lo pida; entonces solo se avisa
  /// si se cambio algo.
  ///
  /// Una letra de otra version ([Letra.porCuadrar]) se busca mas lejos, lo
  /// que difieren las dos versiones, y basta con que el ajuste sea claro,
  /// aunque sea dejarla como esta: entonces sus tiempos valen y se mueve.
  Future<void> _ajustarConLaVoz({bool sola = false}) async {
    final Letra? letra = _letra;
    final String uri = widget.elemento.uri;
    if (letra == null || !(letra.sincronizada || letra.porCuadrar) || _escuchando) return;
    final bool cuadrar = letra.porCuadrar;
    setState(() => _escuchando = true);
    final ({int desfaseMs, bool aplicar, bool seguro})? r = await Nucleo.sincronizarLetra(
      uri,
      <int>[
        for (final LineaLetra l in letra.lineas)
          if (l.texto.trim().isNotEmpty) l.desde.inMilliseconds,
      ],
      rango: cuadrar ? Letras.rangoDeCuadre(letra) : null,
    );
    await _anotarIntentada(uri);
    if (!mounted || uri != widget.elemento.uri) return;
    setState(() => _escuchando = false);
    if (cuadrar) {
      if (r != null && r.seguro) {
        final Letra hecha = await Letras.cuadrar(uri, letra, Duration(milliseconds: r.desfaseMs));
        if (!mounted || uri != widget.elemento.uri) return;
        setState(() {
          _letra = hecha;
          _resaltada = -1;
          // La traduccion iba por las lineas de corrido.
          _traduccion = null;
        });
        _avisar('Letra cuadrada con la voz');
      } else if (!sola) {
        _avisar(r == null
            ? 'No se pudo escuchar la cancion.'
            : 'Esta letra es de otra version y no se pudo cuadrar con la voz.');
      }
      return;
    }
    final Letra? actual = _letra;
    if (r != null && r.aplicar && actual != null) {
      final Duration antes = actual.desfase;
      await _ajustar(Duration(milliseconds: r.desfaseMs) - antes);
      if (!mounted) return;
      final double segundos = r.desfaseMs / 1000;
      _avisar(
        'Letra ajustada a la voz (${segundos > 0 ? '+' : ''}${segundos.toStringAsFixed(1)} s)',
        deshacer: () => _ajustar(antes - (_letra?.desfase ?? antes)),
      );
    } else if (!sola) {
      _avisar(r == null
          ? 'No se pudo escuchar la cancion.'
          : 'No hubo un ajuste claro: si no va a la par, corrigela a mano.');
    }
  }

  void _avisar(String texto, {VoidCallback? deshacer}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(texto),
      // Con boton, Flutter lo dejaria fijo hasta tocarlo: que se vaya solo.
      persist: false,
      action: deshacer == null ? null : SnackBarAction(label: 'Deshacer', onPressed: deshacer),
    ));
  }

  /// Donde va la cancion en su archivo. Con el fundido al compas se carga
  /// recortada y el motor cuenta desde el corte, no desde el principio: sin
  /// sumarlo, la letra iba adelantada todo lo que se recorto.
  Duration get _inicio => _estado.inicioDelTramo(widget.elemento);

  /// Salta al momento en que se canta el verso [i], con el ajuste de
  /// sincronia y el recorte incluidos.
  void _saltarA(Letra letra, int i) => _estado.motor.seek(instanteDelVerso(letra, i, inicio: _inicio));

  /// Corre la letra medio segundo y lo guarda para esta pista.
  Future<void> _ajustar(Duration cuanto) async {
    final Letra? letra = _letra;
    if (letra == null) return;
    final Duration nuevo = letra.desfase + cuanto;
    setState(() {
      _letra = letra.conDesfase(nuevo);
      // Sin esto la linea resaltada no se movería hasta el siguiente cambio.
      _resaltada = -1;
    });
    await Catalogo.instancia.guardarDesfase(widget.elemento.uri, nuevo.inMilliseconds);
  }

  void _seguir(Letra letra, Duration instante) {
    final int toca = letra.lineaEn(instante);
    if (toca == _resaltada) return;
    _resaltada = toca;
    if (toca < 0 || !_desplazamiento.hasClients) return;

    // La linea que canta se lleva al centro; el resto queda arriba y abajo,
    // que es lo que deja seguir la cancion sin buscar donde va.
    final double alto = _desplazamiento.position.viewportDimension;
    final double destino = (toca * _altoLinea) - (alto / 2) + (_altoLinea / 2);
    _desplazamiento.animateTo(
      destino.clamp(0, _desplazamiento.position.maxScrollExtent),
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  /// Pone o quita la traduccion. La primera vez puede tardar: baja el idioma.
  Future<void> _alternarTraduccion() async {
    final Letra? letra = _letra;
    if (letra == null || _traduciendo) return;
    if (_traduccion != null) {
      setState(() {
        _traduccion = null;
        _resaltada = -1;
      });
      return;
    }
    setState(() => _traduciendo = true);
    final List<String>? lineas = await TraducirLetra.traducir(letra);
    if (!mounted) return;
    setState(() {
      _traduciendo = false;
      _traduccion = lineas;
      _resaltada = -1;
    });
    if (lineas == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('No se pudo traducir. La primera vez hace falta internet para bajar el idioma.'),
      ));
    }
  }

  /// Mantener pulsado un verso lo prepara para compartirlo como tarjeta y,
  /// con la [letra] sincronizada, tambien como video: para eso van sus marcas.
  void _compartir(List<String> versos, int indice, {Letra? letra}) {
    if (versos[indice].trim().isEmpty) return;
    Feedback.forLongPress(context);
    abrirCompartirLetra(
      context,
      elemento: widget.elemento,
      versos: versos,
      indice: indice,
      instantes: letra == null ? null : <Duration>[for (final LineaLetra l in letra.lineas) l.desde],
      desfase: letra?.desfase ?? Duration.zero,
    );
  }

  Widget _botonTraducir() {
    final bool puesta = _traduccion != null;
    final Color tono = puesta ? Tema.acento : Colors.white54;
    return TextButton.icon(
      onPressed: _alternarTraduccion,
      icon: _traduciendo
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(Icons.translate_rounded, size: 18, color: tono),
      label: Text(puesta ? 'Ver solo original' : 'Traducir', style: TextStyle(fontSize: 12, color: tono)),
    );
  }

  /// Una sola fila arriba con lo que se toca poco: la sincronia a la izquierda
  /// y la traduccion a la derecha. Antes iban arriba y abajo, cada una con su
  /// hueco, y le quitaban a la letra casi dos lineas.
  Widget _barra({required bool traducible, Duration? desfase, bool cuadrable = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: <Widget>[
          if (cuadrable)
            TextButton.icon(
              onPressed: _escuchando ? null : () => _ajustarConLaVoz(),
              icon: _escuchando
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.graphic_eq_rounded, size: 18),
              label: Text(_escuchando ? 'Cuadrando con la voz' : 'Cuadrar con la voz'),
              style: TextButton.styleFrom(foregroundColor: Colors.white70),
            ),
          if (desfase != null) _ControlSincronia(desfase: desfase, alAjustar: _ajustar),
          if (desfase != null)
            IconButton(
              tooltip: 'Ajustar con la voz',
              visualDensity: VisualDensity.compact,
              onPressed: _escuchando ? null : () => _ajustarConLaVoz(),
              icon: _escuchando
                  ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.graphic_eq_rounded, size: 18),
              color: Colors.white54,
            ),
          const Spacer(),
          if (traducible) _botonTraducir(),
          IconButton(
            tooltip: 'Buscar la letra otra vez',
            visualDensity: VisualDensity.compact,
            onPressed: () => _cargar(deNuevo: true),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            color: Colors.white54,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Letra? letra = _letra;
    if (letra == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (letra.vacia) {
      return _SinLetra(alBuscar: () => _cargar(deNuevo: true));
    }
    final bool traducible = TraducirLetra.ofrecer(letra);
    if (!letra.sincronizada) {
      final List<String> originales = letra.texto.split('\n');
      final List<String>? traducidas = _traduccion;
      return Column(
        children: <Widget>[
          _barra(traducible: traducible, cuadrable: letra.porCuadrar),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 8, 28, 40),
              // Una linea por widget, y no un solo texto: asi cada verso se
              // puede mantener pulsado para compartirlo.
              child: DefaultTextStyle.merge(
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, height: 1.9, fontSize: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int i = 0; i < originales.length; i++) ...<Widget>[
                      GestureDetector(
                        // Sin toque corto: sin marcas de tiempo no hay a donde saltar.
                        onLongPress: originales[i].trim().isEmpty ? null : () => _compartir(originales, i),
                        child: Text(originales[i]),
                      ),
                      if (traducidas != null && i < traducidas.length && traducidas[i].trim().isNotEmpty)
                        Text(
                          traducidas[i],
                          style: const TextStyle(color: Tema.acento, fontSize: 13, fontStyle: FontStyle.italic),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: <Widget>[
        _barra(traducible: traducible, desfase: letra.desfase),
        Expanded(child: _versos(letra)),
      ],
    );
  }

  Widget _versos(Letra letra) {
    // El desenfoque de lo ya cantado es un adorno: fuera con «Quitar
    // animaciones» y en las pruebas, donde solo estorba.
    final bool desenfoca = Movimiento.continuas(context);
    final List<String> versos = <String>[for (final LineaLetra l in letra.lineas) l.texto];
    return StreamBuilder<Duration>(
      stream: _estado.motor.positionStream,
      builder: (BuildContext context, AsyncSnapshot<Duration> instante) {
        final Duration ahora = (instante.data ?? Duration.zero) + _inicio;
        // El desplazamiento se pide para despues del fotograma: moverlo
        // mientras se construye la lista es un error en Flutter.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _seguir(letra, ahora);
        });
        final int activa = letra.lineaEn(ahora);

        return ListView.builder(
          controller: _desplazamiento,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
          itemCount: letra.lineas.length,
          itemExtent: _altoLinea,
          itemBuilder: (BuildContext context, int i) {
            final bool suena = i == activa;
            final bool pasada = i < activa;
            final String texto = letra.lineas[i].texto.isEmpty ? '·' : letra.lineas[i].texto;
            Widget verso = AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: suena ? 19 : 16,
                height: 1.25,
                fontWeight: suena ? FontWeight.w800 : FontWeight.w500,
                // El que suena va en blanco entero: lo tiñe la mascara.
                color: suena ? Colors.white : (pasada ? Colors.white24 : Colors.white60),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (suena)
                    VersoKaraoke(texto: texto, cantado: fraccionCantada(letra, i, ahora))
                  else
                    Text(texto, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                  if (_traduccion case final List<String> t when i < t.length && t[i].trim().isNotEmpty)
                    Text(
                      t[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                        color: suena ? Tema.acento.withValues(alpha: 0.8) : Tema.textoTenue,
                      ),
                    ),
                ],
              ),
            );
            // Lo ya cantado se aleja un poco: queda ahi, pero sin competir.
            if (pasada && desenfoca) {
              verso = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 1.2, sigmaY: 1.2), child: verso);
            }
            return GestureDetector(
              // Tocar una linea salta a ese momento: es la forma mas comoda
              // de repetir el trozo que no se pillo.
              onTap: () => _saltarA(letra, i),
              // Mantenerla pulsada, en cambio, la comparte como tarjeta.
              onLongPress: () => _compartir(versos, i, letra: letra),
              behavior: HitTestBehavior.opaque,
              child: Align(alignment: Alignment.center, child: verso),
            );
          },
        );
      },
    );
  }
}

/// A que posicion del motor hay que saltar para oir el verso [i]: con el
/// ajuste de sincronia, y descontando [inicio] si la cancion se cargo
/// recortada (el motor cuenta desde el corte).
Duration instanteDelVerso(Letra letra, int i, {Duration inicio = Duration.zero}) {
  final Duration destino = letra.lineas[i].desde + letra.desfase - inicio;
  return destino < Duration.zero ? Duration.zero : destino;
}

/// Cuanto se lleva cantado del verso [linea] en [instante], de 0 a 1.
///
/// El verso dura hasta que entra el siguiente; el ultimo no tiene siguiente,
/// asi que se le dan 4 segundos. Tiene en cuenta el desfase de la letra, igual
/// que [Letra.lineaEn], para que el relleno vaya a la par del resaltado.
double fraccionCantada(Letra letra, int linea, Duration instante) {
  if (linea < 0 || linea >= letra.lineas.length) return 0;
  final Duration ajustado = instante - letra.desfase;
  final Duration desde = letra.lineas[linea].desde;
  final Duration hasta = linea + 1 < letra.lineas.length
      ? letra.lineas[linea + 1].desde
      : desde + const Duration(seconds: 4);
  final int total = (hasta - desde).inMilliseconds;
  if (total <= 0) return 1;
  return ((ajustado - desde).inMilliseconds / total).clamp(0.0, 1.0);
}

/// El verso que suena, llenandose de color de izquierda a derecha como en un
/// karaoke: lo cantado en el acento y lo que falta en blanco tenue.
///
/// La posicion del motor llega a saltos de unas decimas; entre una y otra el
/// relleno se desliza solo, para que avance seguido y no a tirones. Solo se
/// repinta la mascara: el texto no se vuelve a maquetar.
class VersoKaraoke extends StatelessWidget {
  const VersoKaraoke({required this.texto, required this.cantado, super.key});

  final String texto;

  /// De 0 a 1: lo que lleva cantado. Ver [fraccionCantada].
  final double cantado;

  static const Color _falta = Color(0x99FFFFFF);

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: cantado),
      duration: Movimiento.de(context, const Duration(milliseconds: 200)),
      builder: (BuildContext context, double f, Widget? hijo) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (Rect zona) => LinearGradient(
          colors: const <Color>[Tema.acento, Tema.acento, _falta, _falta],
          stops: <double>[0, f, f, 1],
        ).createShader(zona),
        child: hijo,
      ),
      child: Text(texto, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
    );
  }
}

/// Corrige a mano la sincronia de la letra.
///
/// Hace falta aunque la letra sea la correcta: las marcas que da el servidor
/// son del disco, y el video de YouTube casi nunca arranca en el mismo punto
/// porque suele llevar una entradilla.
class _ControlSincronia extends StatelessWidget {
  const _ControlSincronia({required this.desfase, required this.alAjustar});

  static const Duration paso = Duration(milliseconds: 500);

  final Duration desfase;
  final Future<void> Function(Duration) alAjustar;

  String get _etiqueta {
    if (desfase == Duration.zero) return 'A la par';
    final double segundos = desfase.inMilliseconds / 1000;
    final String signo = segundos > 0 ? '+' : '';
    return '$signo${segundos.toStringAsFixed(1)} s';
  }

  @override
  Widget build(BuildContext context) {
    final bool ajustada = desfase != Duration.zero;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          onPressed: () => alAjustar(-paso),
          tooltip: 'La letra va atrasada',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.fast_rewind_rounded, size: 18),
          color: Colors.white54,
        ),
        Tooltip(
          message: ajustada ? 'Toca para dejarlo como estaba' : 'Ajusta si la letra no va a la par',
          child: TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(56, 36),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: ajustada ? () => alAjustar(-desfase) : null,
            child: Text(
              _etiqueta,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: ajustada ? Tema.acento : Tema.textoTenue,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: () => alAjustar(paso),
          tooltip: 'La letra va adelantada',
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.fast_forward_rounded, size: 18),
          color: Colors.white54,
        ),
      ],
    );
  }
}

class _SinLetra extends StatelessWidget {
  const _SinLetra({required this.alBuscar});

  final VoidCallback alBuscar;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(Icons.lyrics_outlined, size: 48, color: Colors.white24),
          const SizedBox(height: 14),
          const Text(
            'No hay letra para esta.',
            style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          const Text(
            'Se busca en YouTube Music y en lrclib por el\n'
            'artista y el titulo de la cancion.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Tema.textoTenue, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: alBuscar,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Buscar otra vez'),
          ),
        ],
      ),
    ),
  );
}
