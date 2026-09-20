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
  static const String _esquema = '''
    CREATE TABLE descargas (
      id TEXT NOT NULL,
      audio INTEGER NOT NULL,
      uri TEXT NOT NULL,
      fecha INTEGER NOT NULL,
      PRIMARY KEY (id, audio)
    )
  ''';

  /// Se guarda la apertura, no la base ya abierta.
  ///
  /// Con varias descargas a la vez las tres llegan aqui antes de que ninguna
  /// termine de abrir: guardando el Future todas esperan a la misma y no se
  /// abre por duplicado, que era lo que dejaba la base bloqueada.
  Future<Database>? _apertura;

  Future<Database> get _abierta => _apertura ??= _abrir();

  Future<Database> _abrir() async => openDatabase(
    '${await getDatabasesPath()}/catalogo.db',
    version: 1,
    onCreate: (Database bd, int _) => bd.execute(_esquema),
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

  /// Solo para las pruebas: base en memoria y sin filas.
  ///
  /// Se abre una sola vez y luego se vacia. Cerrarla entre prueba y prueba
  /// bloqueaba la base cuando aun quedaban operaciones en marcha.
  Future<void> usarEnMemoria() async {
    _apertura ??= openDatabase(
      inMemoryDatabasePath,
      version: 1,
      onCreate: (Database bd, int _) => bd.execute(_esquema),
    );
    await (await _abierta).delete(_tabla);
  }
}
