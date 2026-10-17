import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'animaciones.dart';
import 'nucleo.dart';
import 'portadas.dart';

/// Las portadas oficiales en grande (hasta 1400 px), para el reproductor.
///
/// La que se ve en las listas es la miniatura de Android, que no pasa de
/// 512 px y, en lo bajado de YouTube, es el fotograma del video: estirada de
/// borde a borde se ve blanda. Esta se baja una vez, solo con wifi, y se
/// guarda en la carpeta privada de la app con un nombre fijo por cancion
/// ([Nucleo.clavePortada]): si el archivo esta, se usa sin tocar la red.
class PortadasGrandes {
  const PortadasGrandes._();

  /// Donde vive la carpeta «portadas». Es la misma que la `filesDir` de Kotlin.
  ///
  /// En las pruebas no hay path_provider: la busqueda se queda ahi, sin pedir
  /// nada al canal, salvo que la prueba ponga aqui una carpeta suya.
  @visibleForTesting
  static Future<Directory> Function() carpeta = getApplicationSupportDirectory;

  /// Las canciones sin portada oficial, con el dia en que se pregunto.
  static const String _claveSinPortada = 'portadas_sin_oficial';

  /// Pasado este tiempo se vuelve a preguntar: los catalogos crecen.
  static const int diasSinPreguntar = 30;

  static Map<String, int>? _sinPortada;

  /// Peticiones a medio hacer, para que dos pintados no la pidan dos veces.
  static final Map<String, Future<File?>> _enCurso = <String, Future<File?>>{};

  /// Cuantas lleva la bajada de toda la biblioteca. null si no esta en marcha.
  static final ValueNotifier<({int hechas, int total})?> avance =
      ValueNotifier<({int hechas, int total})?>(null);

  @visibleForTesting
  static void reiniciar() {
    _sinPortada = null;
    _enCurso.clear();
    avance.value = null;
  }

  static int _hoy() => DateTime.now().millisecondsSinceEpoch ~/ Duration.millisecondsPerDay;

  static Future<File?> _archivo(String uri) async {
    try {
      final Directory raiz = await carpeta();
      return File('${raiz.path}/portadas/${Nucleo.clavePortada(uri)}.jpg');
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, int>> _cargarSinPortada() async {
    if (_sinPortada != null) return _sinPortada!;
    final Map<String, int> leidas = <String, int>{};
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      for (final String linea in prefs.getStringList(_claveSinPortada) ?? const <String>[]) {
        final List<String> partes = linea.split(':');
        final int? dia = partes.length == 2 ? int.tryParse(partes[1]) : null;
        if (dia != null) leidas[partes[0]] = dia;
      }
    } catch (_) {
      // Sin recuerdo se vuelve a preguntar; no es grave.
    }
    return _sinPortada = leidas;
  }

  static Future<bool> _recienPreguntada(String clave) async {
    final int? dia = (await _cargarSinPortada())[clave];
    return dia != null && _hoy() - dia < diasSinPreguntar;
  }

  static Future<void> _recordarSinPortada(String clave) async {
    final Map<String, int> sin = await _cargarSinPortada();
    final int hoy = _hoy();
    sin[clave] = hoy;
    // Lo caducado sobra: que la lista no crezca sin fin.
    sin.removeWhere((String _, int dia) => hoy - dia >= diasSinPreguntar);
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _claveSinPortada,
        <String>[for (final MapEntry<String, int> e in sin.entries) '${e.key}:${e.value}'],
      );
    } catch (_) {
      // Se queda en memoria hasta que se cierre la app.
    }
  }

  /// La portada grande ya bajada, sin tocar la red. null si no esta.
  static Future<File?> guardada(String uri) async {
    final File? archivo = await _archivo(uri);
    return archivo != null && archivo.existsSync() ? archivo : null;
  }

  /// La guardada o, si no esta y se esta con wifi, la oficial recien bajada.
  ///
  /// Solo para canciones con artista: buscar por el titulo suelto da con
  /// cualquier otra que se llame igual, y una portada equivocada es peor que
  /// la pequena.
  static Future<File?> obtener(Elemento elemento) {
    final String uri = elemento.uri;
    // El cierre no puede devolver lo que quita: es este mismo futuro, y
    // whenComplete esperaria a que acabe el, que espera al cierre.
    return _enCurso[uri] ??= _obtener(elemento).whenComplete(() {
      _enCurso.remove(uri);
    });
  }

  static Future<File?> _obtener(Elemento elemento) async {
    final File? archivo = await _archivo(elemento.uri);
    if (archivo == null) return null;
    if (archivo.existsSync()) return archivo;
    final ({String artista, String tema}) partes = elemento.partes;
    if (!elemento.audio || partes.artista.trim().isEmpty || partes.tema.trim().isEmpty) return null;
    final String clave = Nucleo.clavePortada(elemento.uri);
    if (await _recienPreguntada(clave)) return null;
    if (!await Nucleo.redSinLimite()) return null;
    final ({String? ruta, bool sinPortada}) traida =
        await Nucleo.pedirCaratulaGrande(elemento.uri, artista: partes.artista, titulo: partes.tema);
    if (traida.sinPortada) await _recordarSinPortada(clave);
    final String? ruta = traida.ruta;
    if (ruta == null) return null;
    final File bajada = File(ruta);
    return bajada.existsSync() ? bajada : null;
  }

  /// Baja las de toda la biblioteca en segundo plano, de una en una.
  ///
  /// Solo con wifi: si se pierde, se para donde iba y lo hecho queda. Devuelve
  /// cuantas hay ya en grande al terminar.
  static Future<int> bajarTodas() async {
    if (avance.value != null) return 0;
    avance.value = (hechas: 0, total: 0);
    int conPortada = 0;
    try {
      final List<Elemento> todo = <Elemento>[
        for (final Elemento e in await Nucleo.biblioteca())
          if (e.audio) e,
      ];
      for (int i = 0; i < todo.length; i++) {
        avance.value = (hechas: i, total: todo.length);
        if (await guardada(todo[i].uri) != null) {
          conPortada++;
          continue;
        }
        if (!await Nucleo.redSinLimite()) break;
        if (await obtener(todo[i]) != null) conPortada++;
      }
    } catch (_) {
      // Sin biblioteca no hay nada que bajar.
    } finally {
      avance.value = null;
    }
    return conPortada;
  }
}

/// La portada del reproductor: la de siempre y, encima, la oficial en grande.
///
/// Mientras no llega se ve [PortadaLocal]; cuando hay archivo grande se funde
/// por encima, del mismo tamano, sin saltos ni parpadeo de la pequena.
class PortadaGrande extends StatefulWidget {
  const PortadaGrande({required this.elemento, this.lado = 300, super.key});

  final Elemento elemento;
  final double lado;

  @override
  State<PortadaGrande> createState() => _PortadaGrandeState();
}

class _PortadaGrandeState extends State<PortadaGrande> {
  File? _grande;

  @override
  void initState() {
    super.initState();
    unawaited(_buscar());
  }

  @override
  void didUpdateWidget(PortadaGrande anterior) {
    super.didUpdateWidget(anterior);
    if (anterior.elemento.uri != widget.elemento.uri) {
      // La de la cancion anterior no puede quedarse encima de la nueva.
      _grande = null;
      unawaited(_buscar());
    }
  }

  Future<void> _buscar() async {
    final String uri = widget.elemento.uri;
    final File? grande = await PortadasGrandes.obtener(widget.elemento);
    if (!mounted || grande == null || widget.elemento.uri != uri) return;
    setState(() => _grande = grande);
  }

  @override
  Widget build(BuildContext context) {
    final Widget pequena = PortadaLocal(elemento: widget.elemento, lado: widget.lado, radio: 0);
    final File? grande = _grande;
    if (grande == null) return pequena;
    return SizedBox(
      width: widget.lado,
      height: widget.lado,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          pequena,
          Image.file(
            grande,
            key: ValueKey<String>(grande.path),
            fit: BoxFit.cover,
            gaplessPlayback: true,
            // Descodificada al ancho real de la pantalla, no a los 1400 px
            // del archivo: son casi 8 MB de memoria por imagen.
            cacheWidth: (widget.lado * MediaQuery.devicePixelRatioOf(context)).round(),
            frameBuilder: (BuildContext context, Widget hijo, int? fotograma, bool alInstante) {
              if (alInstante) return hijo;
              return AnimatedOpacity(
                opacity: fotograma == null ? 0 : 1,
                duration: Movimiento.de(context, Movimiento.largo),
                curve: Curves.easeOut,
                child: hijo,
              );
            },
            // Un archivo roto deja ver la pequena, que sigue debajo.
            errorBuilder: (BuildContext context, Object error, StackTrace? pila) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
