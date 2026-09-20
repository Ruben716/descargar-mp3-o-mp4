import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

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

  /// Version actual del esquema. Subirla exige atender [_migrar].
  static const int _version = 2;

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
      fecha INTEGER NOT NULL
    )
  ''';

  static Future<void> _crear(Database bd) async {
    await bd.execute(_esquema);
    await bd.execute(_esquemaLetras);
  }

  static Future<void> _migrar(Database bd, int desde, int hasta) async {
    // De la 1 a la 2 solo se anade la tabla de letras; lo descargado se queda
    // donde estaba, que es justo lo que no se puede perder.
    if (desde < 2) await bd.execute(_esquemaLetras);
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
  Future<void> olvidar(String uri) async {
    await (await _abierta).delete(_tabla, where: 'uri = ?', whereArgs: <Object>[uri]);
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
  Future<({String lrc, String texto})?> letraDe(String uri) async {
    final List<Map<String, Object?>> filas = await (await _abierta).query(
      _tablaLetras,
      columns: <String>['lrc', 'texto'],
      where: 'uri = ?',
      whereArgs: <Object>[uri],
      limit: 1,
    );
    if (filas.isEmpty) return null;
    return (
      lrc: filas.first['lrc'] as String? ?? '',
      texto: filas.first['texto'] as String? ?? '',
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

  /// Solo para las pruebas: base en memoria y sin filas.
  ///
  /// Se abre una sola vez y luego se vacia. Cerrarla entre prueba y prueba
  /// bloqueaba la base cuando aun quedaban operaciones en marcha.
  Future<void> usarEnMemoria() async {
    _apertura ??= abrirEn(inMemoryDatabasePath);
    await (await _abierta).delete(_tabla);
    await (await _abierta).delete(_tablaLetras);
  }
}
