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
  static const String _tablaFavoritas = 'favoritas';
  static const String _tablaVolumenes = 'volumenes';

  /// Version actual del esquema. Subirla exige atender [_migrar].
  static const int _version = 8;

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
      bits INTEGER,
      fecha INTEGER NOT NULL
    )
  ''';

  /// Lo que se marco con el corazon, y cuando: «Me gusta» va de lo ultimo
  /// marcado a lo primero.
  static const String _esquemaFavoritas = '''
    CREATE TABLE favoritas (
      uri TEXT PRIMARY KEY,
      fecha INTEGER NOT NULL
    )
  ''';

  /// Cuanto suena cada cancion (LUFS), para igualar el volumen al reproducir.
  /// Medirla cuesta un par de segundos: se hace una vez y se recuerda.
  static const String _esquemaVolumenes = '''
    CREATE TABLE volumenes (
      uri TEXT PRIMARY KEY,
      lufs REAL NOT NULL,
      fecha INTEGER NOT NULL
    )
  ''';

  static Future<void> _crear(Database bd) async {
    await bd.execute(_esquema);
    await bd.execute(_esquemaLetras);
    await bd.execute(_esquemaEscuchas);
    await bd.execute(_esquemaCalidades);
    await bd.execute(_esquemaFavoritas);
    await bd.execute(_esquemaVolumenes);
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
    // Viniendo de antes de la 5, el CREATE de ahora ya trae la columna de los
    // bits; solo a una tabla creada en la 5 hay que anadirsela.
    if (desde < 5) await bd.execute(_esquemaCalidades);
    if (desde == 5) await bd.execute('ALTER TABLE $_tablaCalidades ADD COLUMN bits INTEGER');
    // Solo se anade una tabla: lo que ya habia no se toca.
    if (desde < 7) await bd.execute(_esquemaFavoritas);
    if (desde < 8) await bd.execute(_esquemaVolumenes);
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
        'bits': calidad.bits,
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
      bits: (f['bits'] as num?)?.toInt(),
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
    await bd.delete(_tablaFavoritas, where: 'uri = ?', whereArgs: <Object>[uri]);
    await bd.delete(_tablaVolumenes, where: 'uri = ?', whereArgs: <Object>[uri]);
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

  /// De lo ultimo escuchado a lo mas antiguo: el historial.
  Future<List<String>> recientes({int limite = 50}) async {
    final List<Map<String, Object?>> filas = await (await _abierta).query(
      _tablaEscuchas,
      columns: <String>['uri'],
      orderBy: 'ultima DESC',
      limit: limite,
    );
    return <String>[for (final Map<String, Object?> f in filas) f['uri']! as String];
  }

  /// Todo lo que se ha escuchado alguna vez, para saber lo que no.
  Future<Set<String>> escuchadas() async {
    final List<Map<String, Object?>> filas =
        await (await _abierta).query(_tablaEscuchas, columns: <String>['uri']);
    return <String>{for (final Map<String, Object?> f in filas) f['uri']! as String};
  }

  /// Lo que se bajo sin perdida (FLAC, WAV...), segun la calidad de origen.
  Future<List<String>> sinPerdida() async {
    final List<Map<String, Object?>> filas = await (await _abierta).query(
      _tablaCalidades,
      columns: <String>['uri'],
      where: "codec IN ('flac', 'alac', 'wav', 'pcm', 'aiff')",
      orderBy: 'fecha DESC',
    );
    return <String>[for (final Map<String, Object?> f in filas) f['uri']! as String];
  }

  // --- Me gusta ---------------------------------------------------------------

  /// Lo marcado con el corazon, de lo ultimo a lo primero.
  Future<List<String>> favoritas() async {
    final List<Map<String, Object?>> filas = await (await _abierta).query(
      _tablaFavoritas,
      columns: <String>['uri'],
      orderBy: 'fecha DESC',
    );
    return <String>[for (final Map<String, Object?> f in filas) f['uri']! as String];
  }

  Future<void> marcarFavorita(String uri, {required bool favorita}) async {
    final Database bd = await _abierta;
    if (favorita) {
      await bd.insert(
        _tablaFavoritas,
        <String, Object>{'uri': uri, 'fecha': DateTime.now().millisecondsSinceEpoch},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else {
      await bd.delete(_tablaFavoritas, where: 'uri = ?', whereArgs: <Object>[uri]);
    }
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
    await (await _abierta).delete(_tablaCalidades);
    await (await _abierta).delete(_tablaFavoritas);
    await (await _abierta).delete(_tablaVolumenes);
  }

  // --- Volumen de cada cancion ---------------------------------------------

  Future<void> anotarVolumen(String uri, double lufs) async {
    await (await _abierta).insert(
      _tablaVolumenes,
      <String, Object>{'uri': uri, 'lufs': lufs, 'fecha': DateTime.now().millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Todo lo medido, de una vez: son pocos numeros y se miran a cada cancion.
  Future<Map<String, double>> volumenes() async {
    final List<Map<String, Object?>> filas = await (await _abierta).query(_tablaVolumenes);
    return <String, double>{
      for (final Map<String, Object?> f in filas) f['uri']! as String: (f['lufs']! as num).toDouble(),
    };
  }

  // --- Copia de seguridad -------------------------------------------------

  /// Las tablas que viajan en la copia. Todas cuelgan de un URI salvo las
  /// descargas, que ademas guardan de que enlace salio cada cancion.
  static const List<String> tablasDeLaCopia = <String>[
    _tabla,
    _tablaEscuchas,
    _tablaCalidades,
    _tablaFavoritas,
    _tablaVolumenes,
    _tablaLetras,
  ];

  /// Todo el catalogo, tabla por tabla, tal cual.
  Future<Map<String, List<Map<String, Object?>>>> volcar() async {
    final Database bd = await _abierta;
    return <String, List<Map<String, Object?>>>{
      for (final String tabla in tablasDeLaCopia) tabla: await bd.query(tabla),
    };
  }

  /// Vuelve a meter un volcado, con los URI traducidos a los de este telefono.
  ///
  /// [traducir] devuelve null para lo que aqui no existe: esas filas se
  /// saltan, porque colgarian de una cancion que no esta. Lo que ya hubiera
  /// se sustituye: restaurar es volver a como estaba.
  Future<int> cargarVolcado(
    Map<String, dynamic> volcado,
    String? Function(String uri) traducir,
  ) async {
    final Database bd = await _abierta;
    int metidas = 0;
    await bd.transaction((Transaction tx) async {
      for (final String tabla in tablasDeLaCopia) {
        final List<dynamic> filas = (volcado[tabla] as List<dynamic>?) ?? <dynamic>[];
        for (final dynamic fila in filas) {
          if (fila is! Map) continue;
          final Map<String, Object?> datos = <String, Object?>{
            for (final MapEntry<dynamic, dynamic> e in fila.entries) '${e.key}': e.value as Object?,
          };
          final String? uri = traducir('${datos['uri'] ?? ''}');
          if (uri == null) continue;
          datos['uri'] = uri;
          await tx.insert(tabla, datos, conflictAlgorithm: ConflictAlgorithm.replace);
          metidas++;
        }
      }
    });
    return metidas;
  }

  /// La cancion [vieja] pasa a ser [nueva] en todo lo que cuelga de ella.
  ///
  /// Lo usa «buscar mejor calidad»: la version nueva hereda las escuchas, la
  /// letra y el corazon de la anterior.
  Future<void> heredar(String vieja, String nueva) async {
    final Database bd = await _abierta;
    for (final String tabla in <String>[_tablaEscuchas, _tablaFavoritas, _tablaLetras]) {
      final List<Map<String, Object?>> filas =
          await bd.query(tabla, where: 'uri = ?', whereArgs: <Object>[vieja]);
      for (final Map<String, Object?> fila in filas) {
        await bd.insert(
          tabla,
          <String, Object?>{...fila, 'uri': nueva},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }
  }
}
