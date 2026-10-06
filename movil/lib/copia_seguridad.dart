import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalogo.dart';
import 'control_descarga.dart';
import 'favoritas.dart';
import 'listas.dart';
import 'nucleo.dart';

/// Una cancion de la copia que no esta en este telefono.
@immutable
class Faltante {
  const Faltante({required this.uri, required this.nombre, required this.audio, this.url});

  /// Su URI en el telefono de donde salio la copia.
  final String uri;
  final String nombre;
  final bool audio;

  /// De donde se bajo, si se sabe: con el se puede volver a bajar.
  final String? url;
}

/// Lo que dejo una restauracion.
@immutable
class ResultadoRestauracion {
  const ResultadoRestauracion({
    required this.encontradas,
    required this.listas,
    required this.faltantes,
    required this.fecha,
  });

  /// Canciones de la copia que ya estan en este telefono.
  final int encontradas;
  final int listas;
  final List<Faltante> faltantes;
  final DateTime fecha;

  /// Las que faltan y se pueden volver a bajar.
  List<Faltante> get recuperables => faltantes.where((Faltante f) => f.url != null).toList();
}

/// Copia de seguridad de todo lo que no es la musica en si.
///
/// Las canciones ya viven en la memoria del telefono (Music/Tumbao) y no se
/// van al desinstalar la app; lo que si se perderia son las listas, los Me
/// gusta, lo escuchado, las letras guardadas, los ajustes y las listas que se
/// siguen. Todo eso va en un archivo en Descargas/Tumbao.
///
/// En otro telefono las canciones tienen otros URI: se reconocen por su
/// nombre, y las que no estan se pueden volver a bajar porque la copia
/// recuerda de que enlace salio cada una.
class CopiaSeguridad {
  CopiaSeguridad._();

  static const String nombreArchivo = 'tumbao-copia.json';
  static const int formato = 1;

  static const String claveUltima = 'copia_ultima';
  static const String claveAuto = 'copia_automatica';

  /// Cada cuanto se hace sola.
  static const Duration cadaCuanto = Duration(days: 7);

  /// Los ajustes que viajan en la copia, tal cual.
  static const List<String> preferencias = <String>[
    ControlDescarga.claveAjustes,
    'ecualizador',
    'fundido_segundos',
    'volumen_parejo',
    'saltar_silencios',
    'suscripciones_v1',
    'posiciones_video_v1',
  ];

  /// Arma la copia como texto.
  static Future<String> generar({List<Elemento>? biblioteca}) async {
    final List<Elemento> canciones = biblioteca ?? await Nucleo.biblioteca();
    final Map<String, List<Map<String, Object?>>> catalogo = await Catalogo.instancia.volcar();

    // De que enlace salio cada cancion: las descargas guardan el id del video.
    final Map<String, String> enlaces = <String, String>{
      for (final Map<String, Object?> d in catalogo['descargas'] ?? const <Map<String, Object?>>[])
        '${d['uri']}': 'https://www.youtube.com/watch?v=${d['id']}',
    };

    await Listas.instancia.cargar();
    final SharedPreferences memoria = await SharedPreferences.getInstance();
    return const JsonEncoder.withIndent(' ').convert(<String, dynamic>{
      'app': 'Tumbao',
      'formato': formato,
      'fecha': DateTime.now().millisecondsSinceEpoch,
      'canciones': <Map<String, dynamic>>[
        for (final Elemento e in canciones)
          <String, dynamic>{
            'uri': e.uri,
            'nombre': e.nombre,
            'duracion': e.duracion,
            'audio': e.audio,
            if (enlaces[e.uri] != null) 'url': enlaces[e.uri],
          },
      ],
      'listas': Listas.instancia.todas,
      'catalogo': catalogo,
      'preferencias': <String, Object?>{
        for (final String clave in preferencias)
          if (memoria.get(clave) != null) clave: memoria.get(clave),
      },
    });
  }

  /// Hace la copia y la deja en Descargas/Tumbao. Devuelve donde quedo.
  static Future<String> guardar() async {
    final String ruta = await Nucleo.guardarCopia(nombreArchivo, await generar());
    final SharedPreferences memoria = await SharedPreferences.getInstance();
    await memoria.setInt(claveUltima, DateTime.now().millisecondsSinceEpoch);
    return ruta;
  }

  /// Cuando se hizo la ultima, o null si nunca.
  static Future<DateTime?> ultima() async {
    final SharedPreferences memoria = await SharedPreferences.getInstance();
    final int? ms = memoria.getInt(claveUltima);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static Future<bool> automatica() async {
    final SharedPreferences memoria = await SharedPreferences.getInstance();
    return memoria.getBool(claveAuto) ?? true;
  }

  static Future<void> ponerAutomatica(bool activa) async {
    final SharedPreferences memoria = await SharedPreferences.getInstance();
    await memoria.setBool(claveAuto, activa);
  }

  /// La copia semanal: se hace al abrir la app si ya toca. Nunca falla hacia
  /// fuera: una copia que no se pudo hacer se intenta la proxima vez.
  static Future<bool> siToca({DateTime? ahora}) async {
    try {
      if (!await automatica()) return false;
      final DateTime? antes = await ultima();
      if (antes != null && (ahora ?? DateTime.now()).difference(antes) < cadaCuanto) return false;
      final List<Elemento> canciones = await Nucleo.biblioteca();
      // Sin nada que guardar no se crea un archivo vacio.
      if (canciones.isEmpty) return false;
      await Nucleo.guardarCopia(nombreArchivo, await generar(biblioteca: canciones));
      final SharedPreferences memoria = await SharedPreferences.getInstance();
      await memoria.setInt(claveUltima, (ahora ?? DateTime.now()).millisecondsSinceEpoch);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Restaura una copia sobre lo que hay.
  ///
  /// Las listas se suman a las que ya existan con el mismo nombre; los ajustes
  /// y el catalogo se ponen como estaban en la copia.
  static Future<ResultadoRestauracion> restaurar(String texto) async {
    final Map<String, dynamic> copia;
    try {
      copia = jsonDecode(texto) as Map<String, dynamic>;
    } catch (_) {
      throw const FormatException('Ese archivo no es una copia de Tumbao.');
    }
    if (copia['app'] != 'Tumbao') throw const FormatException('Ese archivo no es una copia de Tumbao.');

    final List<Elemento> aqui = await Nucleo.biblioteca();
    final Map<String, String> traduccion = traducciones(copia, aqui);

    // Lo que no esta, con su enlace si se sabe.
    final List<Faltante> faltantes = <Faltante>[
      for (final dynamic c in (copia['canciones'] as List<dynamic>?) ?? <dynamic>[])
        if (c is Map<String, dynamic> && !traduccion.containsKey(c['uri']))
          Faltante(
            uri: '${c['uri']}',
            nombre: '${c['nombre'] ?? ''}',
            audio: c['audio'] != false,
            url: c['url']?.toString(),
          ),
    ];

    await _aplicar(copia, traduccion);
    final DateTime fecha = DateTime.fromMillisecondsSinceEpoch((copia['fecha'] as num?)?.toInt() ?? 0);
    return ResultadoRestauracion(
      encontradas: traduccion.length,
      listas: ((copia['listas'] as Map<String, dynamic>?) ?? <String, dynamic>{}).length,
      faltantes: faltantes,
      fecha: fecha,
    );
  }

  /// URI de la copia -> URI de este telefono, para las canciones que hay aqui.
  ///
  /// Primero por URI (mismo telefono, reinstalada la app); si no, por nombre
  /// de archivo y tipo, con la duracion como desempate.
  @visibleForTesting
  static Map<String, String> traducciones(Map<String, dynamic> copia, List<Elemento> aqui) {
    final Set<String> urisAqui = <String>{for (final Elemento e in aqui) e.uri};
    final Map<String, List<Elemento>> porNombre = <String, List<Elemento>>{};
    for (final Elemento e in aqui) {
      porNombre.putIfAbsent(e.nombre, () => <Elemento>[]).add(e);
    }
    final Map<String, String> traduccion = <String, String>{};
    for (final dynamic c in (copia['canciones'] as List<dynamic>?) ?? <dynamic>[]) {
      if (c is! Map<String, dynamic>) continue;
      final String uri = '${c['uri']}';
      if (urisAqui.contains(uri)) {
        traduccion[uri] = uri;
        continue;
      }
      final bool audio = c['audio'] != false;
      final double duracion = ((c['duracion'] as num?) ?? 0).toDouble();
      final List<Elemento> candidatas = (porNombre['${c['nombre']}'] ?? <Elemento>[])
          .where((Elemento e) => e.audio == audio)
          .toList()
        ..sort((Elemento a, Elemento b) =>
            (a.duracion - duracion).abs().compareTo((b.duracion - duracion).abs()));
      if (candidatas.isNotEmpty) traduccion[uri] = candidatas.first.uri;
    }
    return traduccion;
  }

  static Future<void> _aplicar(Map<String, dynamic> copia, Map<String, String> traduccion) async {
    await Catalogo.instancia.cargarVolcado(
      (copia['catalogo'] as Map<String, dynamic>?) ?? <String, dynamic>{},
      (String uri) => traduccion[uri],
    );

    final Listas listas = Listas.instancia;
    await listas.cargar();
    final Map<String, dynamic> suyas = (copia['listas'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    for (final MapEntry<String, dynamic> lista in suyas.entries) {
      final List<String> uris = <String>[
        for (final dynamic u in (lista.value as List<dynamic>? ?? <dynamic>[]))
          if (traduccion[u.toString()] != null) traduccion[u.toString()]!,
      ];
      if (!listas.nombres.contains(lista.key)) await listas.crear(lista.key);
      if (uris.isNotEmpty) await listas.anadirVarias(lista.key, uris);
    }

    final SharedPreferences memoria = await SharedPreferences.getInstance();
    final Map<String, dynamic> ajustes = (copia['preferencias'] as Map<String, dynamic>?) ?? <String, dynamic>{};
    for (final String clave in preferencias) {
      final dynamic valor = ajustes[clave];
      if (valor is String) await memoria.setString(clave, valor);
      if (valor is bool) await memoria.setBool(clave, valor);
      if (valor is int) await memoria.setInt(clave, valor);
      if (valor is double) await memoria.setDouble(clave, valor);
    }
    await Favoritas.instancia.recargar();
  }

  /// Baja otra vez lo que falta y lo engancha a sus listas y Me gusta.
  ///
  /// Primero las canciones y luego los videos, cada uno en su formato.
  static Future<void> bajarFaltantes(String texto, List<Faltante> faltantes) async {
    final ControlDescarga control = ControlDescarga.instancia;
    for (final bool audio in <bool>[true, false]) {
      final List<String> urls = <String>[
        for (final Faltante f in faltantes)
          if (f.audio == audio && f.url != null) f.url!,
      ];
      if (urls.isEmpty) continue;
      await control.iniciarVarios(urls, con: control.ajustes.copiar(soloAudio: audio));
    }
    // Con lo recien bajado ya hay donde enganchar las listas: se vuelve a
    // aplicar la copia, ahora con mas canciones encontradas.
    final Map<String, dynamic> copia = jsonDecode(texto) as Map<String, dynamic>;
    final Map<String, String> traduccion = traducciones(copia, await Nucleo.biblioteca());
    for (final Faltante f in faltantes) {
      final String? url = f.url;
      if (url == null) continue;
      final String? nueva = await Catalogo.instancia.buscar(url, audio: f.audio);
      if (nueva != null) traduccion[f.uri] = nueva;
    }
    await _aplicar(copia, traduccion);
  }
}
