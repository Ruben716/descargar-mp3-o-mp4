import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'calidad.dart';

/// Registro de lo ya descargado, en SQLite.
///
/// Sirve para no bajar dos veces la misma pista: si una lista trae algo que ya
/// esta en el telefono, se reutiliza el archivo y solo se anade a la lista.
/// Medido antes: casi todo el tiempo de una descarga se va en preguntarle a
/// YouTube por los formatos, asi que saltarsela es ahorro puro.
class Catalogo {
  Catalogo._();

  static final Catalogo instancia = Catalogo._();

  static const String _tabla = 'descargas';
  static const String _tablaLetras = 'letras';
  static const String _tablaEscuchas = 'escuchas';
  static const String _tablaCalidades = 'calidades';

  /// Version actual del esquema. Subirla exige atender [_migrar].
  static const int _version = 5;

  static const String _esquema = '''
    CREATE TABLE descargas (
      id TEXT NOT NULL,
      audio INTEGER NOT NULL,
      uri TEXT NOT NULL,
      fecha INTEGER NOT NULL,
      PRIMARY KEY (id, audio)
    )
  ''';

  /// La letra se guarda para que a la segunda no haga falta internet.
  ///
  /// `lrc` vacio es una respuesta valida y significa "se busco y no habia":
  /// sin distinguirlo, cada vez que se abriese esa cancion se repetiria la
  /// consulta que ya sabemos que no da nada.
  static const String _esquemaLetras = '''
    CREATE TABLE letras (
      uri TEXT PRIMARY KEY,
      lrc TEXT NOT NULL,
      texto TEXT NOT NULL,
      fecha INTEGER NOT NULL,
      desfase INTEGER NOT NULL DEFAULT 0
    )
  ''';

  /// Cuantas veces se ha oido cada pista, para lo mas escuchado.
  ///
  /// Solo el recuento y la ultima vez: no se guarda un historial con hora a
  /// hora, que no se usaria para nada y crece sin freno.
  static const String _esquemaEscuchas = '''
    CREATE TABLE escuchas (
      uri TEXT PRIMARY KEY,
      veces INTEGER NOT NULL,
      ultima INTEGER NOT NULL
    )
  ''';

  /// De que calidad llego cada descarga, para poder decirlo sin inventar.
  ///
  /// Va por URI y no por enlace: lo que se ensenia es la cancion que hay en
  /// el telefono, venga de YouTube, de SoundCloud o del Archive.
  static const String _esquemaCalidades = '''
    CREATE TABLE calidades (
      uri TEXT PRIMARY KEY,
      codec TEXT NOT NULL,
      kbps REAL,
      hz INTEGER,
      fecha INTEGER NOT NULL
    )
  ''';

  static Future<void> _crear(Database bd) async {
    await bd.execute(_esquema);
    await bd.execute(_esquemaLetras);
    await bd.execute(_esquemaEscuchas);
    await bd.execute(_esquemaCalidades);
  }

  static Future<void> _migrar(Database bd, int desde, int hasta) async {
    // Cada paso solo anade una tabla; lo descargado se queda donde estaba,
    // que es justo lo que no se puede perder.
    if (desde < 2) await bd.execute(_esquemaLetras);
    if (desde < 3) await bd.execute(_esquemaEscuchas);
    if (desde < 4) {
      // La columna solo hay que anadirla a una tabla que se creo sin ella.
      // Viniendo de la v1 la crea el CREATE de arriba, que es el de ahora y ya
      // la trae: intentarlo igualmente aborta la actualizacion entera.
      if (desde >= 2) {
        await bd.execute(
          'ALTER TABLE $_tablaLetras ADD COLUMN desfase INTEGER NOT NULL DEFAULT 0',
        );
      }
      // Las letras guardadas hasta aqui se eligieron sin comprobar que la
      // cancion fuera la pedida, asi que algunas son de otro tema. Se tiran
      // para que se vuelvan a buscar bien; volver a bajarlas es barato.
      await bd.delete(_tablaLetras);
    }
    if (desde < 5) await bd.execute(_esquemaCalidades);
  }

  /// Apunta de que calidad llego una descarga.
  Future<void> anotarCalidad(String uri, CalidadAudio calidad) async {
    if (uri.isEmpty) return;
    await (await _abierta).insert(
      _tablaCalidades,
      <String, Object?>{
        'uri': uri,
        'codec': calidad.codec,
        'kbps': calidad.kbps,
        'hz': calidad.hz,
        'fecha': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// La calidad de origen de una cancion, o null si se bajo antes de saberla.
  Future<CalidadAudio?> calidadDe(String uri) async {
    final List<Map<String, Object?>> filas = await (await _abierta).query(
      _tablaCalidades,
      where: 'uri = ?',
      whereArgs: <Object>[uri],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    final Map<String, Object?> f = filas.first;
    return CalidadAudio(
      codec: f['codec']! as String,
      kbps: (f['kbps'] as num?)?.toDouble(),
      hz: (f['hz'] as num?)?.toInt(),
    );
  }

  /// Se guarda la apertura, no la base ya abierta.
  ///
  /// Con varias descargas a la vez las tres llegan aqui antes de que ninguna
  /// termine de abrir: guardando el Future todas esperan a la misma y no se
  /// abre por duplicado, que era lo que dejaba la base bloqueada.
  Future<Database>? _apertura;

  Future<Database> get _abierta => _apertura ??= _abrir();

  Future<Database> _abrir() async => abrirEn('${await getDatabasesPath()}/catalogo.db');

  /// Abre la base con el esquema y las migraciones de siempre.
  ///
  /// Es publica para que las pruebas puedan comprobar que una base vieja de
  /// verdad sobrevive a la actualizacion, que es donde se perderia lo
  /// descargado si algo estuviese mal.
  @visibleForTesting
  static Future<Database> abrirEn(String ruta) => openDatabase(
    ruta,
    version: _version,
    onCreate: (Database bd, int _) => _crear(bd),
    onUpgrade: _migrar,
  );

  /// El identificador del video dentro de la URL.
  ///
  /// La misma pista llega con URLs distintas segun de donde venga (youtube.com,
  /// music.youtube.com, youtu.be), asi que comparar URLs enteras no valdria.
  static String? identificador(String url) {
    final Uri? enlace = Uri.tryParse(url);
    if (enlace == null) return null;
    final String? v = enlace.queryParameters['v'];
    if (v != null && v.isNotEmpty) return v;
    if (enlace.host.contains('youtu.be') && enlace.pathSegments.isNotEmpty) {
      return enlace.pathSegments.last;
    }
    return null;
  }

  /// Devuelve el URI de biblioteca si esa pista ya se bajo en ese formato.
  ///
  /// El formato importa: tener el MP3 no significa tener el video.
  Future<String?> buscar(String url, {required bool audio}) async {
    final String? id = identificador(url);
    if (id == null) return null;
    final List<Map<String, Object?>> filas = await (await _abierta).query(
      _tabla,
      columns: <String>['uri'],
      where: 'id = ? AND audio = ?',
      whereArgs: <Object>[id, audio ? 1 : 0],
      limit: 1,
    );
    return filas.isEmpty ? null : filas.first['uri'] as String?;
  }

  Future<void> registrar(String url, {required bool audio, required String uri}) async {
    final String? id = identificador(url);
    if (id == null || uri.isEmpty) return;
    await (await _abierta).insert(
      _tabla,
      <String, Object>{
        'id': id,
        'audio': audio ? 1 : 0,
        'uri': uri,
        'fecha': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Al borrar una descarga hay que olvidarla, o creeriamos tenerla todavia.
  ///
  /// Se va tambien lo que colgaba de ella: si no, una pista borrada seguiria
  /// encabezando lo mas escuchado sin que se pueda abrir.
  Future<void> olvidar(String uri) async {
    final Database bd = await _abierta;
    await bd.delete(_tabla, where: 'uri = ?', whereArgs: <Object>[uri]);
    await bd.delete(_tablaLetras, where: 'uri = ?', whereArgs: <Object>[uri]);
    await bd.delete(_tablaEscuchas, where: 'uri = ?', whereArgs: <Object>[uri]);
    await bd.delete(_tablaCalidades, where: 'uri = ?', whereArgs: <Object>[uri]);
  }

  Future<int> cuantas() async {
    final List<Map<String, Object?>> filas =
        await (await _abierta).rawQuery('SELECT COUNT(*) AS n FROM $_tabla');
    return (filas.first['n'] as int?) ?? 0;
  }

  // --- Letras -------------------------------------------------------------

  /// Lo guardado para esa pista, o `null` si nunca se busco.
  ///
  /// Devolver una letra vacia no es lo mismo que devolver `null`: lo primero
  /// dice que se busco y no habia, y evita repetir la consulta cada vez.
  Future<({String lrc, String texto, int desfase})?> letraDe(String uri) async {
    final List<Map<String, Object?>> filas = await (await _abierta).query(
      _tablaLetras,
      columns: <String>['lrc', 'texto', 'desfase'],
      where: 'uri = ?',
      whereArgs: <Object>[uri],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    return (
      lrc: filas.first['lrc'] as String? ?? '',
      texto: filas.first['texto'] as String? ?? '',
      desfase: filas.first['desfase'] as int? ?? 0,
    );
  }

  /// Guarda el ajuste manual de sincronia de esa letra, en milisegundos.
  Future<void> guardarDesfase(String uri, int milisegundos) async {
    if (uri.isEmpty) return;
    await (await _abierta).update(
      _tablaLetras,
      <String, Object>{'desfase': milisegundos},
      where: 'uri = ?',
      whereArgs: <Object>[uri],
    );
  }

  Future<void> guardarLetra(String uri, {required String lrc, required String texto}) async {
    if (uri.isEmpty) return;
    await (await _abierta).insert(
      _tablaLetras,
      <String, Object>{
        'uri': uri,
        'lrc': lrc,
        'texto': texto,
        'fecha': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // --- Escuchas -----------------------------------------------------------

  /// Suma una escucha a esa pista.
  Future<void> anotarEscucha(String uri) async {
    if (uri.isEmpty) return;
    await (await _abierta).rawInsert(
      'INSERT INTO $_tablaEscuchas (uri, veces, ultima) VALUES (?, 1, ?) '
      'ON CONFLICT(uri) DO UPDATE SET veces = veces + 1, ultima = ?',
      <Object>[uri, DateTime.now().millisecondsSinceEpoch,
        DateTime.now().millisecondsSinceEpoch],
    );
  }

  /// Los URI mas escuchados, del que mas al que menos.
  Future<List<({String uri, int veces})>> masEscuchadas({int limite = 10}) async {
    final List<Map<String, Object?>> filas = await (await _abierta).query(
      _tablaEscuchas,
      columns: <String>['uri', 'veces'],
      orderBy: 'veces DESC, ultima DESC',
      limit: limite,
    );
    return filas
        .map((Map<String, Object?> f) => (
              uri: f['uri'] as String? ?? '',
              veces: f['veces'] as int? ?? 0,
            ))
        .toList();
  }

  Future<int> vecesEscuchada(String uri) async {
    final List<Map<String, Object?>> filas = await (await _abierta).query(
      _tablaEscuchas,
      columns: <String>['veces'],
      where: 'uri = ?',
      whereArgs: <Object>[uri],
      limit: 1,
    );
    return filas.isEmpty ? 0 : (filas.first['veces'] as int? ?? 0);
  }

  /// Solo para las pruebas: base en memoria y sin filas.
  ///
  /// Se abre una sola vez y luego se vacia. Cerrarla entre prueba y prueba
  /// bloqueaba la base cuando aun quedaban operaciones en marcha.
  Future<void> usarEnMemoria() async {
    _apertura ??= abrirEn(inMemoryDatabasePath);
    await (await _abierta).delete(_tabla);
    await (await _abierta).delete(_tablaLetras);
    await (await _abierta).delete(_tablaEscuchas);
  }
}
