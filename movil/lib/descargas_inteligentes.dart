import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'catalogo.dart';
import 'control_descarga.dart';
import 'descubre.dart';
import 'estado_reproductor.dart';
import 'favoritas.dart';
import 'listas.dart';
import 'nucleo.dart';
import 'tema.dart';

/// Una cancion que la app bajo sola, y de que semana de «Descubre» era.
@immutable
class BajadaInteligente {
  const BajadaInteligente({required this.url, required this.uri, required this.semana});

  factory BajadaInteligente.desdeJson(Map<String, dynamic> j) => BajadaInteligente(
        url: '${j['url']}',
        uri: '${j['uri']}',
        semana: (j['semana'] as num?)?.toInt() ?? 0,
      );

  final String url;
  final String uri;
  final int semana;

  Map<String, Object> aJson() => <String, Object>{'url': url, 'uri': uri, 'semana': semana};
}

/// Descargas inteligentes: con wifi, la app baja sola las primeras canciones
/// de «Descubre», como hace YouTube Music.
///
/// Cada semana se renuevan: lo que bajo sola y no has tocado (ni escuchado, ni
/// marcado Me gusta, ni metido en otra lista) se borra para dejar sitio a lo
/// nuevo. Lo que si tocaste pasa a ser tuyo y no se borra nunca. Solo se borra
/// lo que la app bajo por su cuenta; nada de lo que bajaste tu.
class DescargasInteligentes extends ChangeNotifier {
  DescargasInteligentes._();

  static final DescargasInteligentes instancia = DescargasInteligentes._();

  static const String claveActivas = 'inteligentes_activas';
  static const String claveCuantas = 'inteligentes_cuantas';
  static const String claveBajadas = 'inteligentes_bajadas';

  /// La lista de Tumbao donde quedan, para encontrarlas.
  static const String lista = 'Descargas inteligentes';
  static const List<int> opciones = <int>[10, 20, 30];

  bool _cargada = false;
  bool _activas = false;
  int _cuantas = 20;
  List<BajadaInteligente> _bajadas = <BajadaInteligente>[];
  bool _trabajando = false;
  String _aviso = '';

  bool get activas => _activas;
  int get cuantas => _cuantas;
  bool get trabajando => _trabajando;
  String get aviso => _aviso;

  /// Las que bajo sola y aun no son tuyas.
  List<BajadaInteligente> get bajadas => List<BajadaInteligente>.unmodifiable(_bajadas);

  /// Que canciones de [pistas] bajar: por su orden, sin lo que ya esta en el
  /// telefono ([tengo], por video) ni lo que ya se bajo solo ([yaBajadas]).
  static List<Resultado> queBajar(
    List<Resultado> pistas, {
    required Set<String> tengo,
    required Set<String> yaBajadas,
    required int faltan,
  }) {
    if (faltan <= 0) return const <Resultado>[];
    return <Resultado>[
      for (final Resultado r in pistas)
        if (!yaBajadas.contains(r.url) && !tengo.contains(Catalogo.identificador(r.url))) r,
    ].take(faltan).toList();
  }

  /// Que hacer con lo bajado de semanas anteriores a [semana]: lo que no has
  /// tocado se borra; lo que si, se queda y deja de ser de la app.
  static ({List<BajadaInteligente> borrar, List<BajadaInteligente> tuyas}) repasar(
    List<BajadaInteligente> bajadas, {
    required int semana,
    required Set<String> escuchadas,
    required Set<String> favoritas,
    required Set<String> enOtrasListas,
  }) {
    final List<BajadaInteligente> borrar = <BajadaInteligente>[];
    final List<BajadaInteligente> tuyas = <BajadaInteligente>[];
    for (final BajadaInteligente b in bajadas) {
      final bool tocada =
          escuchadas.contains(b.uri) || favoritas.contains(b.uri) || enOtrasListas.contains(b.uri);
      if (tocada) {
        tuyas.add(b);
      } else if (b.semana < semana) {
        borrar.add(b);
      }
    }
    return (borrar: borrar, tuyas: tuyas);
  }

  Future<void> cargar() async {
    if (_cargada) return;
    _cargada = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      _activas = prefs.getBool(claveActivas) ?? false;
      _cuantas = prefs.getInt(claveCuantas) ?? _cuantas;
      final String? guardadas = prefs.getString(claveBajadas);
      if (guardadas != null) {
        _bajadas = <BajadaInteligente>[
          for (final dynamic j in jsonDecode(guardadas) as List<dynamic>)
            BajadaInteligente.desdeJson(j as Map<String, dynamic>),
        ];
      }
    } catch (_) {
      // Sin lo guardado se empieza de cero: no se borra nada que no se conozca.
    }
    notifyListeners();
  }

  Future<void> _guardar() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(claveActivas, _activas);
    await prefs.setInt(claveCuantas, _cuantas);
    await prefs.setString(claveBajadas, jsonEncode(<Map<String, Object>>[for (final BajadaInteligente b in _bajadas) b.aJson()]));
  }

  /// Al encenderlas se bajan ya, sin esperar a la proxima vez que se abra la app.
  Future<void> ponerActivas(bool activas) async {
    await cargar();
    _activas = activas;
    _aviso = '';
    notifyListeners();
    await _guardar();
    if (activas) unawaited(revisar());
  }

  Future<void> ponerCuantas(int cuantas) async {
    await cargar();
    _cuantas = cuantas;
    notifyListeners();
    await _guardar();
    if (_activas) unawaited(revisar());
  }

  /// Desde las tareas de fondo: solo si estan encendidas.
  Future<void> revisarSiToca() async {
    await cargar();
    if (_activas) await revisar();
  }

  /// Renueva lo de semanas anteriores y baja lo que falte de la de ahora.
  /// Devuelve cuantas se bajaron.
  Future<int> revisar() async {
    await cargar();
    final ControlDescarga control = ControlDescarga.instancia;
    if (!_activas || _trabajando || control.activa) return 0;
    if (!await Nucleo.redSinLimite()) {
      _aviso = 'Esperando wifi para bajarlas.';
      notifyListeners();
      return 0;
    }
    _trabajando = true;
    notifyListeners();
    int bajadas = 0;
    try {
      final Descubre descubre = Descubre.instancia;
      await descubre.cargar();
      if (descubre.pistas.isEmpty) await descubre.rehacer();
      final DateTime? hecha = descubre.hecha;
      if (descubre.pistas.isEmpty || hecha == null) {
        _aviso = 'Aun no hay canciones en Descubre.';
        return 0;
      }
      final int semana = Descubre.semanaDe(hecha);
      await _renovar(semana);

      final Map<String, String> videos = await Catalogo.instancia.videos();
      final List<Resultado> nuevas = queBajar(
        descubre.pistas,
        tengo: videos.keys.toSet(),
        yaBajadas: <String>{for (final BajadaInteligente b in _bajadas) b.url},
        faltan: _cuantas - _bajadas.where((BajadaInteligente b) => b.semana == semana).length,
      );
      if (nuevas.isNotEmpty) {
        final List<String> urls = <String>[for (final Resultado r in nuevas) r.url];
        await control.iniciarVarios(urls, con: control.ajustes.copiar(soloAudio: true));
        for (final String url in urls) {
          final String? uri = await Catalogo.instancia.buscar(url, audio: true);
          if (uri == null) continue;
          _bajadas.add(BajadaInteligente(url: url, uri: uri, semana: semana));
          await _alaLista(uri);
          bajadas++;
        }
      }
      _aviso = bajadas == 0
          ? 'Tus descargas inteligentes estan al dia.'
          : 'Se bajaron $bajadas ${bajadas == 1 ? 'cancion nueva' : 'canciones nuevas'} de Descubre.';
      await _guardar();
    } catch (_) {
      _aviso = 'No se pudieron bajar ahora; se intentara al volver a abrir la app.';
    } finally {
      _trabajando = false;
      notifyListeners();
    }
    return bajadas;
  }

  /// Borra lo de semanas anteriores que no tocaste y suelta lo que si.
  Future<void> _renovar(int semana) async {
    final Listas listas = Listas.instancia;
    await listas.cargar();
    final ({List<BajadaInteligente> borrar, List<BajadaInteligente> tuyas}) repaso = repasar(
      _bajadas,
      semana: semana,
      escuchadas: await Catalogo.instancia.escuchadas(),
      favoritas: (await Catalogo.instancia.favoritas()).toSet(),
      enOtrasListas: <String>{
        for (final MapEntry<String, List<String>> l in listas.todas.entries)
          if (l.key != lista) ...l.value,
      },
    );
    final Set<String> fuera = <String>{for (final BajadaInteligente b in repaso.tuyas) b.uri};
    for (final BajadaInteligente b in repaso.borrar) {
      try {
        await EstadoReproductor.instancia.olvidarSiEs(b.uri);
        await Nucleo.eliminar(b.uri);
        await Catalogo.instancia.olvidar(b.uri);
        await listas.olvidar(b.uri);
        Favoritas.instancia.olvidar(b.uri);
        fuera.add(b.uri);
      } catch (_) {
        // Si no se pudo borrar se intenta la proxima vez.
      }
    }
    _bajadas.removeWhere((BajadaInteligente b) => fuera.contains(b.uri));
  }

  Future<void> _alaLista(String uri) async {
    final Listas listas = Listas.instancia;
    await listas.cargar();
    if (!listas.nombres.contains(lista)) await listas.crear(lista);
    if (!listas.contiene(lista, uri)) await listas.anadir(lista, uri);
  }

  @visibleForTesting
  void reiniciar() {
    _cargada = false;
    _activas = false;
    _cuantas = 20;
    _bajadas = <BajadaInteligente>[];
    _trabajando = false;
    _aviso = '';
  }
}

/// El interruptor de las descargas inteligentes y cuantas bajar. Va en
/// Descubre y en Ajustes.
class AjusteDescargasInteligentes extends StatelessWidget {
  const AjusteDescargasInteligentes({this.margen = const EdgeInsets.symmetric(horizontal: 16), super.key});

  final EdgeInsets margen;

  @override
  Widget build(BuildContext context) {
    final DescargasInteligentes d = DescargasInteligentes.instancia;
    return ListenableBuilder(
      listenable: d,
      builder: (BuildContext context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            contentPadding: margen,
            value: d.activas,
            onChanged: (bool v) => unawaited(d.ponerActivas(v)),
            secondary: const Icon(Icons.download_for_offline_rounded),
            title: const Text('Descargas inteligentes'),
            subtitle: Text(
              d.trabajando
                  ? 'Bajando canciones de Descubre...'
                  : d.activas && d.aviso.isNotEmpty
                      ? d.aviso
                      : 'Con wifi, baja solas las primeras ${d.cuantas} de Descubre cada semana. '
                          'Las que no escuches se cambian por las nuevas.',
            ),
          ),
          if (d.activas)
            Padding(
              padding: margen.copyWith(top: 0, bottom: 8),
              child: Wrap(
                spacing: 8,
                children: <Widget>[
                  for (final int n in DescargasInteligentes.opciones)
                    ChoiceChip(
                      label: Text('$n canciones'),
                      selected: d.cuantas == n,
                      onSelected: (_) => unawaited(d.ponerCuantas(n)),
                      labelStyle: TextStyle(color: d.cuantas == n ? Tema.texto : Tema.textoSecundario),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
