import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import 'calidad.dart';
import 'formato.dart';

/// Acceso al nucleo Python, el mismo que usa la version de consola.
///
/// Todo viaja como JSON por el canal de plataforma: Dart no entiende los
/// objetos del dominio y Kotlin solo hace de intermediario.
class Nucleo {
  const Nucleo._();

  static const MethodChannel _canal = MethodChannel('com.ruben.descargador/nucleo');

  static Future<Map<String, dynamic>> _pedir(
    String metodo, [
    Map<String, dynamic>? argumentos,
  ]) async {
    final String crudo = await _canal.invokeMethod(metodo, argumentos) ?? '{}';
    final Map<String, dynamic> datos = jsonDecode(crudo) as Map<String, dynamic>;
    if (datos.containsKey('ok') && datos['ok'] != true) {
      throw ErrorNucleo(
        datos['error']?.toString() ?? 'Error desconocido',
        ((datos['registro'] as List<dynamic>?) ?? <dynamic>[])
            .map((dynamic l) => l.toString())
            .toList(),
      );
    }
    return datos;
  }

  static Future<Map<String, dynamic>> diagnostico() => _pedir('diagnostico');

  static Future<List<Resultado>> buscar(
    String texto, {
    int limite = 12,
    String fuente = 'youtube',
  }) async {
    final Map<String, dynamic> datos = await _pedir('buscar', <String, dynamic>{
      'texto': texto,
      'limite': limite,
      'fuente': fuente,
    });
    return ((datos['resultados'] as List<dynamic>?) ?? <dynamic>[])
        .map((dynamic r) => Resultado.desdeJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Trae las pistas de una lista de reproduccion ajena, sin descargarlas.
  static Future<ListaTraida> importarLista(String url) async {
    final Map<String, dynamic> datos =
        await _pedir('importarLista', <String, dynamic>{'url': url});
    return ListaTraida(
      titulo: datos['titulo']?.toString() ?? 'Lista importada',
      pistas: ((datos['resultados'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic r) => Resultado.desdeJson(r as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Descarga y devuelve los archivos y la calidad con la que llego el audio.
  static Future<({List<String> archivos, CalidadAudio? origen})> descargar(
    Ajustes ajustes, {
    bool avisar = true,
  }) async {
    final Map<String, dynamic> datos = await _pedir('descargar', <String, dynamic>{
      ...ajustes.aMapa(),
      'avisar': avisar,
    });
    return (
      archivos: ((datos['archivos'] as List<dynamic>?) ?? <dynamic>[])
          .map((dynamic a) => a.toString())
          .toList(),
      origen: CalidadAudio.tal(datos['origen']),
    );
  }

  /// Que audio llegaria de un enlace, y si se puede bajar, sin bajarlo.
  ///
  /// Falla con [ErrorNucleo] si no se puede: con DRM, retirado, privado...
  static Future<CalidadAudio> calidad(String url) async {
    final Map<String, dynamic> datos = await _pedir('calidad', <String, dynamic>{'url': url});
    return CalidadAudio.desdeJson(datos);
  }

  /// Carga el motor de descargas sin esperar a necesitarlo.
  ///
  /// Arrancarlo es lo que mas tarda de la primera busqueda. Hecho mientras
  /// el usuario aun mira la pantalla o escribe, esa espera no se nota.
  static Future<void> precalentar() async {
    try {
      await _pedir('precalentar');
    } catch (_) {
      // Si falla, la primera busqueda lo cargara igualmente.
    }
  }

  /// Un solo aviso al terminar un lote, en vez de uno por pista.
  static Future<void> avisarLote(int cantidad, {required bool audio}) =>
      _pedir('avisarLote', <String, dynamic>{'cantidad': cantidad, 'audio': audio});

  /// Manda un archivo de la biblioteca a otra app.
  static Future<void> compartirArchivo(String uri, {required bool audio}) =>
      _pedir('compartirArchivo', <String, dynamic>{'uri': uri, 'audio': audio});

  /// Comparte el enlace de algo que aun no esta descargado.
  static Future<void> compartirEnlace(String url, {String titulo = ''}) =>
      _pedir('compartirEnlace', <String, dynamic>{'url': url, 'titulo': titulo});

  /// Abre un enlace en su app (Crunchyroll, Netflix...) o en el navegador.
  static Future<void> abrirEnlace(String url) =>
      _pedir('abrirEnlace', <String, dynamic>{'url': url});

  static Future<Avance> progreso() async => Avance.desdeJson(await _pedir('progreso'));

  /// Reescribe titulo y artista de una pista y la renombra.
  ///
  /// Devuelve el nombre con el que quedo, que puede ser el de antes si el
  /// telefono no dejo renombrar (por ejemplo, si ya hay otra igual).
  static Future<String> etiquetar(
    String uri, {
    required String titulo,
    required String artista,
  }) async {
    final Map<String, dynamic> datos = await _pedir('etiquetar', <String, dynamic>{
      'uri': uri,
      'titulo': titulo,
      'artista': artista,
    });
    return datos['nombre']?.toString() ?? '';
  }

  static Future<List<Elemento>> biblioteca() async {
    final Map<String, dynamic> datos = await _pedir('biblioteca');
    return ((datos['elementos'] as List<dynamic>?) ?? <dynamic>[])
        .map((dynamic e) => Elemento.desdeJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Pista reproducible al vuelo, para oir antes de decidir si se descarga.
  static Future<Previsualizacion> previsualizar(String url, {bool soloAudio = true}) async {
    final Map<String, dynamic> datos = await _pedir(
      'previsualizar',
      <String, dynamic>{'url': url, 'soloAudio': soloAudio},
    );
    return Previsualizacion.desdeJson(datos);
  }

  /// Borra una descarga de la biblioteca del telefono.
  static Future<void> eliminar(String uri) =>
      _pedir('eliminar', <String, dynamic>{'uri': uri});

  /// Cierto mientras la app va encogida en una ventana flotante.
  static final ValueNotifier<bool> enVentanaFlotante = ValueNotifier<bool>(false);

  /// Brillo de la ventana de la app (0 a 1); sin valor solo lo lee.
  /// Devuelve -1 si sigue el del sistema.
  static Future<double> brillo([double? valor]) async =>
      await _canal.invokeMethod<double>('brillo', <String, dynamic>{'valor': valor}) ?? -1;

  /// Volumen de la musica del telefono (0 a 1); sin valor solo lo lee.
  static Future<double> volumen([double? valor]) async =>
      await _canal.invokeMethod<double>('volumen', <String, dynamic>{'valor': valor}) ?? 0.5;

  /// Encoge la app a una ventana flotante con la proporcion del video.
  static Future<bool> pedirVentanaFlotante({required int ancho, required int alto}) async =>
      await _canal.invokeMethod<bool>(
        'ventanaFlotante',
        <String, dynamic>{'ancho': ancho, 'alto': alto},
      ) ??
      false;

  /// Android avisa por el mismo canal al entrar o salir de la ventana.
  /// Lo que hacer cuando el usuario cierra la app (la quita de recientes).
  static Future<void> Function()? alCerrarTarea;

  static void escucharVentanaFlotante() {
    _canal.setMethodCallHandler((MethodCall llamada) async {
      if (llamada.method == 'ventanaFlotante') {
        enVentanaFlotante.value = llamada.arguments == true;
      }
      if (llamada.method == 'tareaCerrada') await alCerrarTarea?.call();
      if (llamada.method == 'widget') await alPulsarWidget?.call('${llamada.arguments}');
      return null;
    });
  }

  /// Un boton del widget de la pantalla de inicio: anterior, alternar o siguiente.
  static Future<void> Function(String accion)? alPulsarWidget;

  /// El atajo del icono con que se abrio la app, si lo hay. Se entrega una vez.
  static Future<String?> atajoPendiente() async {
    try {
      return await _canal.invokeMethod<String>('atajoPendiente');
    } catch (_) {
      return null;
    }
  }

  /// Pinta el widget de la pantalla de inicio. Sin titulo, sale como cerrado.
  static Future<void> actualizarWidget({
    String? titulo,
    String artista = '',
    bool sonando = false,
    String? caratula,
  }) async {
    try {
      await _canal.invokeMethod<void>('actualizarWidget', <String, dynamic>{
        'titulo': titulo,
        'artista': artista,
        'sonando': sonando,
        'caratula': caratula,
      });
    } catch (_) {
      // Sin widget (o en un telefono que no los tiene) no pasa nada.
    }
  }

  static Future<String?> urlCompartida() => _canal.invokeMethod<String>('urlCompartida');

  /// El enlace que otra app acaba de compartir, a la espera de atenderse.
  ///
  /// Lo recoge el armazon de pestanias, que es lo unico que existe siempre, y
  /// lo atiende Descargar. Antes lo pedia Descargar por su cuenta, pero esa
  /// pantalla solo se construye al visitarla: al compartir, la app se abria
  /// en Inicio y el enlace se quedaba esperando sin que nadie lo viera.
  static final ValueNotifier<String?> enlaceCompartido = ValueNotifier<String?>(null);

  static Future<void> recogerCompartido() async {
    final String? enlace = await urlCompartida();
    if (enlace != null && enlace.isNotEmpty) enlaceCompartido.value = enlace;
  }

  static final Map<String, Uint8List?> _caratulas = <String, Uint8List?>{};

  /// Caratula del archivo, ya decodificada. Se recuerda porque cruzar el
  /// canal y decodificar base64 por cada pintado seria un derroche.
  /// La caratula guardada como archivo: la notificacion del sistema necesita
  /// una direccion, no unos bytes.
  static Future<Uri?> caratulaArchivo(String uri) async {
    // El archivo de la vez anterior sigue ahi: si esta, no hay que pedir la
    // imagen ni decodificarla. Importa al poner una cola larga, que pide una
    // por cancion antes de que empiece a sonar nada.
    final File? guardado = await _archivoCaratula(uri);
    if (guardado != null && guardado.existsSync()) return guardado.uri;

    final Uint8List? imagen = await caratula(uri);
    if (imagen == null || guardado == null) return null;
    try {
      await guardado.writeAsBytes(imagen);
      return guardado.uri;
    } catch (_) {
      return null;
    }
  }

  /// Donde viven las caratulas ya preparadas, preguntado una sola vez.
  ///
  /// No va en la carpeta temporal a proposito: el limpiador del sistema la
  /// vacia cuando quiere, y entonces habria que volver a sacar y recomprimir
  /// las cien caratulas de la biblioteca antes de que sonara nada.
  static Directory? _carpetaCaratulas;

  static Future<File?> _archivoCaratula(String uri) async {
    try {
      final Directory cache =
          _carpetaCaratulas ??= await getApplicationSupportDirectory();
      return File('${cache.path}/caratula_${uri.hashCode.toRadixString(16)}.jpg');
    } catch (_) {
      return null;
    }
  }

  /// Peticiones a medio hacer, para que varias filas de la misma pista no
  /// pidan la portada por separado.
  ///
  /// El recuerdo no basta: se escribe al volver, y hasta entonces todas las
  /// filas que se pinten ven el hueco vacio y cruzan el canal cada una.
  static final Map<String, Future<Uint8List?>> _enCurso = <String, Future<Uint8List?>>{};

  /// Si ya se pidio, aunque fuera para saber que no tiene portada.
  static bool caratulaConocida(String uri) => _caratulas.containsKey(uri);

  /// Lo ya recordado, sin esperar. Distinguir "no tiene" de "aun no se pidio"
  /// es cosa de [caratulaConocida].
  static Uint8List? caratulaGuardada(String uri) => _caratulas[uri];

  /// Al borrar una descarga, su portada deja de valer.
  static void olvidarCaratula(String uri) {
    _caratulas.remove(uri);
    _enCurso.remove(uri);
    // Tambien la copia en disco: si no, una pista nueva que cayera en el mismo
    // sitio heredaria la portada de la que se borro.
    unawaited(_borrarCaratulaGuardada(uri));
  }

  static Future<void> _borrarCaratulaGuardada(String uri) async {
    try {
      final File? guardado = await _archivoCaratula(uri);
      if (guardado != null && guardado.existsSync()) await guardado.delete();
    } catch (_) {
      // Que sobre un archivo en la carpeta temporal no es problema de nadie.
    }
  }

  @visibleForTesting
  static void olvidarCaratulas() {
    _caratulas.clear();
    _enCurso.clear();
  }

  static Future<Uint8List?> caratula(String uri) {
    if (_caratulas.containsKey(uri)) return Future<Uint8List?>.value(_caratulas[uri]);
    return _enCurso[uri] ??= _pedirCaratula(uri);
  }

  static Future<Uint8List?> _pedirCaratula(String uri) async {
    try {
      final Map<String, dynamic> datos =
          await _pedir('caratula', <String, dynamic>{'uri': uri});
      final String crudo = datos['imagen']?.toString() ?? '';
      final Uint8List? imagen = crudo.isEmpty ? null : base64Decode(crudo);
      _caratulas[uri] = imagen;
      return imagen;
    } catch (_) {
      _caratulas[uri] = null;
      return null;
    } finally {
      _enCurso.remove(uri);
    }
  }
}

/// Error del nucleo, con el registro del motor cuando lo hay.
class ErrorNucleo implements Exception {
  const ErrorNucleo(this.mensaje, [this.registro = const <String>[]]);

  final String mensaje;
  final List<String> registro;

  @override
  String toString() => mensaje;
}

class Resultado {
  const Resultado({
    required this.titulo,
    required this.autor,
    required this.duracion,
    required this.url,
    this.miniatura = '',
    this.fuente,
    this.calidad,
  });

  factory Resultado.desdeJson(Map<String, dynamic> j) => Resultado(
        titulo: j['titulo']?.toString() ?? '',
        autor: j['autor']?.toString() ?? '',
        duracion: (j['duracion'] as num?)?.toDouble() ?? 0,
        url: j['url']?.toString() ?? '',
        miniatura: j['miniatura']?.toString() ?? '',
        calidad: CalidadAudio.tal(j['calidad']),
      );

  final String titulo;
  final String autor;
  final double duracion;
  final String url;
  final String miniatura;

  /// De donde salio. Buscando en todas a la vez hace falta saberlo por pista.
  final Fuente? fuente;

  /// La calidad, cuando la fuente ya la dice al buscar (Audius). Lo normal
  /// es que haga falta comprobarla.
  final CalidadAudio? calidad;

  Resultado deFuente(Fuente f) => Resultado(
        titulo: titulo,
        autor: autor,
        duracion: duracion,
        url: url,
        miniatura: miniatura,
        fuente: f,
        calidad: calidad,
      );
}

/// Una lista ajena tal y como llega: con su nombre, para poder recrearla.
class ListaTraida {
  const ListaTraida({required this.titulo, required this.pistas});

  final String titulo;
  final List<Resultado> pistas;
}

class Previsualizacion {
  const Previsualizacion({required this.url, required this.titulo, required this.cabeceras});

  factory Previsualizacion.desdeJson(Map<String, dynamic> j) => Previsualizacion(
        url: j['url']?.toString() ?? '',
        titulo: j['titulo']?.toString() ?? '',
        cabeceras: ((j['cabeceras'] as Map<String, dynamic>?) ?? <String, dynamic>{})
            .map((String k, dynamic v) => MapEntry<String, String>(k, v.toString())),
      );

  final String url;
  final String titulo;

  /// YouTube exige el mismo User-Agent con el que se pidio el enlace.
  final Map<String, String> cabeceras;
}

class Elemento {
  const Elemento({
    required this.nombre,
    required this.uri,
    required this.duracion,
    required this.tamano,
    required this.audio,
    this.etiquetaTitulo = '',
    this.etiquetaArtista = '',
    this.fecha = 0,
  });

  factory Elemento.desdeJson(Map<String, dynamic> j) => Elemento(
        nombre: j['nombre']?.toString() ?? '',
        uri: j['uri']?.toString() ?? '',
        duracion: (j['duracion'] as num?)?.toDouble() ?? 0,
        tamano: (j['tamano'] as num?)?.toInt() ?? 0,
        audio: j['audio'] == true,
        etiquetaTitulo: j['titulo']?.toString() ?? '',
        etiquetaArtista: j['artista']?.toString() ?? '',
        fecha: (j['fecha'] as num?)?.toInt() ?? 0,
      );

  /// Lo que dicen las etiquetas del archivo. Vacio si no las tiene.
  final String etiquetaTitulo;
  final String etiquetaArtista;

  /// Cuando llego al telefono, en segundos desde 1970. 0 si no se sabe.
  final int fecha;

  /// Artista y tema para ensenar; ver [nombreVisible].
  ({String artista, String tema}) get partes =>
      nombreVisible(nombre, titulo: etiquetaTitulo, artista: etiquetaArtista);

  String get tema => partes.tema;
  String get artista => partes.artista;

  /// En una sola linea, para donde no caben dos: «Artista - Tema».
  String get etiqueta {
    final ({String artista, String tema}) p = partes;
    return p.artista.isEmpty ? p.tema : '${p.artista} - ${p.tema}';
  }

  final String nombre;
  final String uri;
  final double duracion;
  final int tamano;
  final bool audio;
}

class Avance {
  const Avance({required this.estado, required this.porcentaje, required this.velocidad});

  factory Avance.desdeJson(Map<String, dynamic> j) => Avance(
        estado: j['status']?.toString() ?? '',
        porcentaje: (j['porcentaje'] as num?)?.toDouble() ?? -1,
        velocidad: (j['velocidad'] as num?)?.toInt() ?? 0,
      );

  final String estado;
  final double porcentaje;
  final int velocidad;
}

/// Lo que el usuario puede ajustar. Refleja DownloadOptions del dominio.
/// De donde se puede buscar musica.
///
/// Espeja FUENTES del nucleo. Bandcamp queda fuera porque su reproductor sirve
/// 128 kb/s y el FLAC esta detras del pago; Tidal y companiia llevan DRM.
enum Fuente {
  /// Todas a la vez. No existe en el nucleo: la app pregunta a cada una en
  /// paralelo y junta lo que va llegando.
  todas('todas', 'Todas', 'Busca en todas a la vez y compara la calidad'),
  youtube('youtube', 'YouTube', 'Lo mas y lo mas nuevo'),
  soundcloud('soundcloud', 'SoundCloud', 'Mezclas y temas propios'),
  audius('audius', 'Audius', 'Artistas que suben a 320 y a veces el original sin perdida'),
  bandcamp('bandcamp', 'Bandcamp', 'Independientes; algunos regalan el FLAC'),
  archive('archive', 'Archive', 'Conciertos sin perdida');

  const Fuente(this.clave, this.etiqueta, this.pista);

  final String clave;
  final String etiqueta;

  /// Una linea de que esperar, que si no nadie adivina cual elegir.
  final String pista;

  /// Si sus resultados son grabaciones completas y no canciones sueltas.
  ///
  /// El Archive guarda conciertos enteros: cada resultado es una lista de
  /// pistas, asi que se abre como tal en vez de bajarse de una pieza.
  bool get daListas => this == Fuente.archive;

  /// Las que existen de verdad en el nucleo, en el orden en que se ensenian.
  static const List<Fuente> reales = <Fuente>[
    Fuente.youtube,
    Fuente.soundcloud,
    Fuente.audius,
    Fuente.bandcamp,
    Fuente.archive,
  ];
}

/// Formatos de audio en los que no se puede igualar el volumen.
///
/// Espeja `FORMATOS_SIN_NORMALIZAR` del nucleo: al sacar el audio, FFmpeg
/// copia el flujo tal cual cuando el codec de destino ya es el de origen, y
/// entonces el filtro no se puede aplicar. YouTube entrega opus y aac.
const Set<String> formatosSinNormalizar = <String>{'best', 'opus', 'm4a', 'aac'};

class Ajustes {
  const Ajustes({
    required this.url,
    this.soloAudio = false,
    this.calidad = 720,
    this.formatoAudio = 'mp3',
    this.bitrate = '192',
    this.subtitulos = '',
    this.fragmento = '',
    this.sinPatrocinios = false,
    this.normalizar = false,
    this.etiquetasLimpias = true,
    this.portadaOficial = true,
  });

  final String url;
  final bool soloAudio;
  final int calidad;
  final String formatoAudio;
  final String bitrate;
  final String subtitulos;
  final String fragmento;
  final bool sinPatrocinios;

  /// Iguala el volumen del MP3 al descargarlo.
  final bool normalizar;

  /// Separa artista y tema del titulo de YouTube y le quita las coletillas.
  final bool etiquetasLimpias;

  /// Cambia el fotograma del video por la caratula oficial del tema.
  final bool portadaOficial;

  Ajustes copiar({
    String? url,
    bool? soloAudio,
    int? calidad,
    String? formatoAudio,
    String? bitrate,
    String? subtitulos,
    String? fragmento,
    bool? sinPatrocinios,
    bool? normalizar,
    bool? etiquetasLimpias,
    bool? portadaOficial,
  }) =>
      Ajustes(
        url: url ?? this.url,
        soloAudio: soloAudio ?? this.soloAudio,
        calidad: calidad ?? this.calidad,
        formatoAudio: formatoAudio ?? this.formatoAudio,
        bitrate: bitrate ?? this.bitrate,
        subtitulos: subtitulos ?? this.subtitulos,
        fragmento: fragmento ?? this.fragmento,
        sinPatrocinios: sinPatrocinios ?? this.sinPatrocinios,
        normalizar: normalizar ?? this.normalizar,
        etiquetasLimpias: etiquetasLimpias ?? this.etiquetasLimpias,
        portadaOficial: portadaOficial ?? this.portadaOficial,
      );

  Map<String, dynamic> aMapa() => <String, dynamic>{
        'url': url,
        'soloAudio': soloAudio,
        // En audio la altura no aplica; el nucleo la ignoraria igualmente.
        'calidad': soloAudio ? 0 : calidad,
        'formatoAudio': formatoAudio,
        'bitrate': bitrate,
        'subtitulos': subtitulos,
        'fragmento': fragmento,
        'sinPatrocinios': sinPatrocinios,
        // Igualar el volumen exige reconvertir, que solo pasa al sacar el
        // audio y con un formato que no se pueda copiar tal cual. En otro caso
        // el nucleo rechazaria la descarga entera.
        'normalizar': soloAudio && normalizar && !formatosSinNormalizar.contains(formatoAudio),
        'etiquetasLimpias': etiquetasLimpias,
        // Solo tiene sentido en audio: un video no lleva caratula dentro.
        'portadaOficial': soloAudio && portadaOficial,
      };
}
