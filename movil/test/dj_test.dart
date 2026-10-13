import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:descargador_movil/catalogo.dart';
import 'package:descargador_movil/control_descarga.dart';
import 'package:descargador_movil/dj.dart';
import 'package:descargador_movil/estado_reproductor.dart';
import 'package:descargador_movil/nucleo.dart';
import 'package:descargador_movil/ritmos.dart';
import 'package:descargador_movil/volumen_parejo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Correlacion de Spearman entre la posicion y [valores].
double _spearman(List<double> valores) {
  final int n = valores.length;
  final List<int> orden = List<int>.generate(n, (int i) => i)
    ..sort((int a, int b) => valores[a].compareTo(valores[b]));
  final List<int> rango = List<int>.filled(n, 0);
  for (int i = 0; i < n; i++) {
    rango[orden[i]] = i;
  }
  double s = 0;
  for (int i = 0; i < n; i++) {
    s += pow(rango[i] - i, 2).toDouble();
  }
  return 1 - 6 * s / (n * (n * n - 1));
}

Elemento _cancion(String uri, {String artista = '', double duracion = 200}) => Elemento(
      nombre: artista.isEmpty ? '$uri.mp3' : '$artista - $uri.mp3',
      uri: uri,
      duracion: duracion,
      tamano: 1,
      audio: true,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('dj automatico', () {
    final Random r = Random(7);
    final List<PistaDj> lista = <PistaDj>[
      for (int i = 0; i < 40; i++)
        PistaDj(
          'p$i',
          'a${i % 7}',
          Rasgos(
            bpm: <double>[90, 95, 100, 120, 124, 128, 140, 174][i % 8] + r.nextDouble() * 2,
            confianza: .4,
            energia: r.nextDouble(),
          ),
        ),
      const PistaDj('sin', 'x', null),
    ];
    final List<PistaDj> barajada = List<PistaDj>.of(lista)..shuffle(Random(3));

    test('el doble y la mitad son el mismo tempo para un DJ', () {
      expect(Dj.distanciaTempo(87, 174), lessThan(0.05));
      const Rasgos a = Rasgos(bpm: 128, confianza: .5);
      expect(Dj.costeTempo(a, const Rasgos(bpm: 126, confianza: .5)), lessThan(0.1));
      expect(Dj.costeTempo(a, const Rasgos(bpm: 100, confianza: .5)), 1);
      expect(Dj.costeTempo(a, null), 0.5, reason: 'sin analizar, neutro');
      expect(Dj.costeTempo(a, const Rasgos(bpm: 128, confianza: .05)), 0.5,
          reason: 'un tempo sin confianza no cuenta');
    });

    test('la rueda Camelot', () {
      expect(Dj.costeTono('8A', '9A'), 0.1);
      expect(Dj.costeTono('8A', '8B'), 0.1);
      expect(Dj.costeTono('8A', '3B'), 1);
      expect(Dj.costeTono('12A', '1A'), 0.1);
      expect(Dj.costeTono(null, '1A'), 0.3);
      expect(Dj.costeTono('raro', '1A'), 0.3, reason: 'lo ilegible no revienta');
    });

    test('ordenar no pierde ni repite y cuesta menos que al azar', () {
      final List<PistaDj> ordenada = Dj.ordenar(barajada, azar: Random(1));
      expect(ordenada.length, lista.length);
      expect(ordenada.toSet().length, lista.length);
      expect(ordenada.any((PistaDj p) => p.id == 'sin'), isTrue, reason: 'la sin analizar se conserva');
      expect(Dj.costeRuta(ordenada), lessThan(Dj.costeRuta(barajada) * 0.5));
    });

    test('la elegida va delante', () {
      expect(Dj.ordenar(barajada, primera: 'p5', azar: Random(1)).first.id, 'p5');
      for (final ModoDj modo in ModoDj.values) {
        expect(Dj.ordenar(barajada, modo: modo, primera: 'p9', azar: Random(1)).first.id, 'p9',
            reason: modo.name);
      }
      expect(Dj.ordenar(barajada.take(2).toList(), primera: barajada[1].id).first.id, barajada[1].id);
    });

    test('subiendo, la energia crece con la posicion', () {
      final List<PistaDj> sube = Dj.ordenar(barajada, modo: ModoDj.subir, azar: Random(1));
      final Map<String, double> e = Dj.percentiles(barajada);
      expect(_spearman(<double>[for (final PistaDj p in sube) e[p.id] ?? .5]), greaterThan(0.9));
      final List<PistaDj> baja = Dj.ordenar(barajada, modo: ModoDj.bajar, azar: Random(1));
      expect(_spearman(<double>[for (final PistaDj p in baja) e[p.id] ?? .5]), lessThan(-0.9));
    });

    test('en fiesta el pico cae hacia el 70 %', () {
      final List<PistaDj> arco = Dj.ordenar(barajada, modo: ModoDj.arco, azar: Random(1));
      final Map<String, double> e = Dj.percentiles(barajada);
      final List<double> curva = <double>[for (final PistaDj p in arco) e[p.id] ?? .5];
      final int pico = curva.indexOf(curva.reduce(max));
      expect(arco.length, barajada.length);
      expect(arco.toSet().length, barajada.length);
      expect(pico, greaterThan(arco.length * 0.55));
      expect(pico, lessThan(arco.length * 0.85));
    });

    test('500 canciones se ordenan en poco tiempo', () {
      final List<PistaDj> grande = <PistaDj>[
        for (int i = 0; i < 500; i++)
          PistaDj('g$i', 'a${i % 50}',
              Rasgos(bpm: 80 + r.nextDouble() * 90, confianza: .4, energia: r.nextDouble())),
      ];
      final Stopwatch reloj = Stopwatch()..start();
      expect(Dj.ordenar(grande, azar: Random(1)).length, 500);
      expect(reloj.elapsedMilliseconds, lessThan(2000));
    });

    test('con canciones de la biblioteca deja fuera las sesiones largas', () {
      final List<Elemento> cosas = <Elemento>[
        for (int i = 0; i < 6; i++) _cancion('c$i', artista: 'A$i'),
        _cancion('podcast', duracion: 3600),
      ];
      final Map<String, Rasgos> rasgos = <String, Rasgos>{
        for (int i = 0; i < 6; i++) 'c$i': Rasgos(bpm: 100.0 + i, confianza: .5, energia: i / 6),
      };
      final List<Elemento> orden = Dj.ordenarElementos(
        cosas,
        rasgos: (String u) => rasgos[u],
        modo: ModoDj.subir,
        azar: Random(1),
      );
      expect(orden.map((Elemento e) => e.uri), isNot(contains('podcast')));
      expect(orden.map((Elemento e) => e.uri).toList(), <String>['c0', 'c1', 'c2', 'c3', 'c4', 'c5']);
      expect(
        Dj.ordenarElementos(<Elemento>[_cancion('largo', duracion: 4000)], rasgos: (String _) => null)
            .single
            .uri,
        'largo',
        reason: 'si solo hay largas, suenan igual',
      );
    });

    test('ordenar muchas fuera del hilo da lo mismo que dentro', () async {
      final List<Elemento> muchas = <Elemento>[for (int i = 0; i < 160; i++) _cancion('m$i')];
      final List<Elemento> orden = await EstadoReproductor.ordenarComoDj(
        muchas,
        rasgos: <String, Rasgos>{
          for (int i = 0; i < 160; i++) 'm$i': Rasgos(bpm: 90.0 + i % 40, confianza: .5, energia: i / 160),
        },
        primera: 'm42',
      );
      expect(orden.length, 160);
      expect(orden.first.uri, 'm42');
      expect(orden.map((Elemento e) => e.uri).toSet().length, 160);
    });

    test('lo parecido se acerca y lo distinto se aleja', () {
      const Rasgos a = Rasgos(bpm: 128, confianza: .5, energia: .8);
      expect(Dj.diferencia(a, const Rasgos(bpm: 127, confianza: .5, energia: .78)), lessThan(0.1));
      expect(Dj.diferencia(a, const Rasgos(bpm: 70, confianza: .5, energia: .1)), greaterThan(0.8));
      expect(Dj.diferencia(a, null), 0.5);
    });
  });

  group('fundido al compas', () {
    test('corta en el pulso y la salida va por compases', () {
      final CorteAlCompas? c = CorteAlCompas.calcular(
        const Rasgos(bpm: 128, confianza: .5, pulsoInicioMs: 2000, pulsoFinMs: 200000),
        fundido: const Duration(seconds: 8),
        total: const Duration(seconds: 205),
      );
      expect(c, isNotNull);
      expect(c!.inicio.inMilliseconds, 1980, reason: '20 ms antes del primer golpe');
      expect(c.fin.inMilliseconds, 200469, reason: 'donde caeria el pulso siguiente');
      expect(c.salida.inMilliseconds, 7500, reason: '8 s a 128 BPM son 16 pulsos');
      expect(c.entrada.inMilliseconds, 1875, reason: 'un compas');
    });

    test('sin pulso fiable o muy corta, el fundido de siempre', () {
      expect(
        CorteAlCompas.calcular(
          const Rasgos(bpm: 128, confianza: .05, pulsoInicioMs: 0, pulsoFinMs: 100000),
          fundido: const Duration(seconds: 8),
          total: const Duration(seconds: 120),
        ),
        isNull,
      );
      expect(
        CorteAlCompas.calcular(
          const Rasgos(bpm: 128, confianza: .5, pulsoInicioMs: 0, pulsoFinMs: 20000),
          fundido: const Duration(seconds: 8),
          total: const Duration(seconds: 25),
        ),
        isNull,
      );
    });

    test('la curva al compas no baja a cero y la entrada arranca arriba', () {
      double v(int ms, {bool entrando = false}) => EstadoReproductor.volumenConFundido(
            posicion: Duration(milliseconds: ms),
            total: const Duration(seconds: 100),
            fundido: const Duration(seconds: 8),
            entrando: entrando,
            salida: const Duration(milliseconds: 7500),
            entrada: const Duration(milliseconds: 1875),
            piso: 0.25,
            arranque: 0.6,
          );
      expect(v(100000), closeTo(0.25, 1e-9), reason: 'justo en el corte');
      expect(v(92000), 1, reason: 'antes de la salida, entero');
      double antes = 1;
      for (int ms = 92500; ms <= 100000; ms += 250) {
        expect(v(ms), lessThanOrEqualTo(antes + 1e-9));
        antes = v(ms);
      }
      expect(v(0, entrando: true), closeTo(0.6, 1e-9));
      expect(v(1875, entrando: true), 1);
    });

    test('sin los parametros nuevos se comporta como siempre', () {
      double v(int ms, {bool entrando = false}) => EstadoReproductor.volumenConFundido(
            posicion: Duration(milliseconds: ms),
            total: const Duration(seconds: 100),
            fundido: const Duration(seconds: 4),
            entrando: entrando,
          );
      expect(v(98000), closeTo(0.5, 1e-9));
      expect(v(1000, entrando: true), closeTo(0.25, 1e-9));
      expect(v(50000), 1);
    });
  });

  group('ritmos', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      Ritmos.instancia.reiniciar();
      VolumenParejo.instancia.reiniciar();
      ControlDescarga.instancia.reiniciar();
      await Catalogo.instancia.usarEnMemoria();
    });

    test('los rasgos van y vuelven del json y de la tabla', () async {
      final Rasgos r = Rasgos.desdeJson(<String, dynamic>{
        'ok': true,
        'version': 1,
        'bpm': 123.5,
        'confianza': 0.42,
        'energia': 0.7,
        'golpes': 2.5,
        'brillo': 0.05,
        'graves': 0.6,
        'lra': 5.2,
        'lufs': -9.1,
        'inicioMs': 120,
        'finMs': 200000,
        'pulsoInicioMs': 130,
        'pulsoFinMs': 199500,
        'genero': ' Salsa ',
        'anio': 1978,
      });
      expect(r.conPulso, isTrue);
      expect(r.textoBpm, '~124 BPM');
      expect(r.genero, 'Salsa');
      await Catalogo.instancia.anotarRitmo('content://audio/1', r.aFila());
      final Rasgos vuelta = Rasgos.deFila((await Catalogo.instancia.ritmos()).single);
      expect(vuelta.bpm, 123.5);
      expect(vuelta.pulsoFinMs, 199500);
      expect(vuelta.genero, 'Salsa');
      expect(vuelta.anio, 1978);
      expect(vuelta.version, Rasgos.versionActual);
      expect(const Rasgos(bpm: 120, confianza: 0.05).conPulso, isFalse);
      expect(const Rasgos().textoBpm, isNull);
    });

    test('olvidar una cancion borra su ritmo, y la copia lo lleva', () async {
      await Catalogo.instancia.anotarRitmo('content://audio/1', const Rasgos(bpm: 100, confianza: 1).aFila());
      expect(Catalogo.tablasDeLaCopia, contains('ritmos'));
      expect((await Catalogo.instancia.volcar())['ritmos'], hasLength(1));
      await Catalogo.instancia.olvidar('content://audio/1');
      expect(await Catalogo.instancia.ritmos(), isEmpty);
    });

    test('se carga lo de esta version y lo viejo se vuelve a analizar', () async {
      await Catalogo.instancia.anotarRitmo('content://audio/1', const Rasgos(energia: .2).aFila());
      await Catalogo.instancia.anotarRitmo(
        'content://audio/2',
        const Rasgos(energia: .9, version: Rasgos.versionActual - 1).aFila(),
      );
      await Ritmos.instancia.cargar();
      expect(Ritmos.instancia.rasgosDe('content://audio/1'), isNotNull);
      expect(Ritmos.instancia.rasgosDe('content://audio/2'), isNull);
    });

    test('analiza una vez cada una, lo urgente primero y el volumen lo aprovecha', () async {
      final List<String> pedidas = <String>[];
      final Completer<void> freno = Completer<void>();
      Ritmos.analizar = (String uri) async {
        pedidas.add(uri);
        if (uri == 'a') await freno.future;
        return Rasgos(energia: .5, lufs: uri == 'c' ? -9 : null);
      };
      await Ritmos.instancia.cargar();
      await VolumenParejo.instancia.cargar();
      Ritmos.instancia.pedirSiFalta('a');
      // Que empiece con «a» antes de pedir mas.
      await Future<void>.delayed(Duration.zero);
      Ritmos.instancia.pedirSiFalta('a');
      Ritmos.instancia.pedirSiFalta('b');
      Ritmos.instancia.analizarTodas(<String>['c'], urgente: true);
      expect(Ritmos.instancia.pendientes, 3);
      freno.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(pedidas, <String>['a', 'c', 'b'], reason: 'la urgente se cuela delante de la normal');
      expect(Ritmos.instancia.analizadas, 3);
      expect(Ritmos.instancia.pendientes, 0);
      expect(VolumenParejo.instancia.lufsDe('c'), -9, reason: 'una pasada da tambien el volumen');
      expect((await Catalogo.instancia.ritmos()).length, 3, reason: 'y se recuerda');
    });

    test('el percentil se calibra con la biblioteca', () {
      Ritmos.instancia.ponerParaPruebas(<String, Rasgos>{
        'a': const Rasgos(energia: .1),
        'b': const Rasgos(energia: .5),
        'c': const Rasgos(energia: .9),
      });
      expect(Ritmos.instancia.percentil('a'), 0);
      expect(Ritmos.instancia.percentil('b'), 0.5);
      expect(Ritmos.instancia.percentil('c'), 1);
      expect(Ritmos.instancia.percentil('x'), isNull);
    });

    test('el catalogo de la v8 gana la tabla de ritmos sin perder nada', () async {
      final Directory temporal = await Directory.systemTemp.createTemp('tumbao');
      final String ruta = '${temporal.path}/catalogo.db';
      final Database vieja = await openDatabase(
        ruta,
        version: 8,
        onCreate: (Database bd, int _) async {
          await bd.execute(
            'CREATE TABLE descargas (id TEXT NOT NULL, audio INTEGER NOT NULL, '
            'uri TEXT NOT NULL, fecha INTEGER NOT NULL, PRIMARY KEY (id, audio))',
          );
          await bd.execute(
            'CREATE TABLE volumenes (uri TEXT PRIMARY KEY, lufs REAL NOT NULL, fecha INTEGER NOT NULL)',
          );
        },
      );
      await vieja.insert('volumenes', <String, Object>{'uri': 'content://audio/1', 'lufs': -9.0, 'fecha': 0});
      await vieja.close();

      final Database nueva = await Catalogo.abrirEn(ruta);
      try {
        expect(await nueva.getVersion(), Catalogo.version);
        expect((await nueva.query('volumenes')).single['lufs'], -9.0, reason: 'lo medido se queda');
        expect(await nueva.query('ritmos'), isEmpty, reason: 'y la tabla nueva ya esta');
      } finally {
        await nueva.close();
        await temporal.delete(recursive: true);
      }
    });
  });
}
