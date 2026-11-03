import 'package:descargador_movil/acceso.dart';
import 'package:descargador_movil/nucleo.dart';
import 'package:descargador_movil/tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// El control de acceso: los plazos, el servidor (falso, nunca se toca la red),
/// la pantalla del codigo y el bloqueo de buscar y bajar.
const MethodChannel _canal = MethodChannel('com.ruben.descargador/nucleo');

const int _dia = 24 * 60 * 60 * 1000;
final DateTime _hoy = DateTime.utc(2026, 11, 3, 12);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final List<(String, String)> preguntas = <(String, String)>[];
  ResultadoAcceso respuesta = (estado: RespuestaAcceso.ok, nombre: 'Carlos');
  DateTime reloj = _hoy;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    Acceso.instancia.reiniciar();
    preguntas.clear();
    respuesta = (estado: RespuestaAcceso.ok, nombre: 'Carlos');
    reloj = _hoy;
    Acceso.exigir = true;
    Acceso.ahora = () => reloj;
    Acceso.idDispositivo = () async => 'telefono-de-prueba';
    Acceso.servidor = (String codigo, String dispositivo) async {
      preguntas.add((codigo, dispositivo));
      return respuesta;
    };
  });

  tearDown(() {
    Acceso.instancia.reiniciar();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_canal, null);
  });

  group('estadoDe: los plazos', () {
    EstadoAcceso estado({bool codigo = true, int validado = 0, int visto = 0, int ahora = 0}) => Acceso.estadoDe(
          hayCodigo: codigo,
          validadoMs: validado,
          vistoMs: visto,
          ahoraMs: ahora,
        );
    final int t0 = _hoy.millisecondsSinceEpoch;

    test('sin codigo, o sin haber validado nunca, hay que pedirlo', () {
      expect(estado(codigo: false, validado: t0, ahora: t0), EstadoAcceso.sinCodigo);
      expect(estado(validado: 0, ahora: t0), EstadoAcceso.sinCodigo);
    });

    test('hasta 7 dias todo; de 7 a 30 solo lo de dentro; pasados 30 nada', () {
      expect(estado(validado: t0, ahora: t0), EstadoAcceso.completo);
      expect(estado(validado: t0, ahora: t0 + 7 * _dia), EstadoAcceso.completo, reason: 'justo 7 dias aun vale');
      expect(estado(validado: t0, ahora: t0 + 7 * _dia + 1), EstadoAcceso.sinDescargas);
      expect(estado(validado: t0, ahora: t0 + 30 * _dia), EstadoAcceso.sinDescargas);
      expect(estado(validado: t0, ahora: t0 + 30 * _dia + 1), EstadoAcceso.caducado);
    });

    test('atrasar el reloj no alarga los plazos', () {
      // Se vio la hora t0 + 20 dias y ahora el reloj dice que es t0 + 2.
      expect(estado(validado: t0, visto: t0 + 20 * _dia, ahora: t0 + 2 * _dia), EstadoAcceso.caducado);
      // Una diferencia chica (cambio de huso, ajuste del reloj) no cuenta.
      expect(
        estado(validado: t0, visto: t0 + 2 * _dia, ahora: t0 + 2 * _dia - 30 * 60 * 1000),
        EstadoAcceso.completo,
      );
    });
  });

  group('con el servidor', () {
    test('un codigo bueno se guarda y la proxima vez entra sin preguntar al usuario', () async {
      expect(await Acceso.instancia.introducir('1d43 b59c-7f4e'), isNull);
      expect(preguntas.single, ('1D43B59C7F4E', 'telefono-de-prueba'), reason: 'sin guiones, en mayusculas');
      expect(Acceso.instancia.estado, EstadoAcceso.completo);
      expect(Acceso.instancia.nombre, 'Carlos');

      Acceso.instancia.reiniciar();
      Acceso.exigir = true;
      Acceso.ahora = () => reloj;
      Acceso.idDispositivo = () async => 'telefono-de-prueba';
      Acceso.servidor = (String c, String d) async {
        preguntas.add((c, d));
        return (estado: RespuestaAcceso.sinRed, nombre: '');
      };
      await Acceso.instancia.cargar();
      expect(Acceso.instancia.estado, EstadoAcceso.completo, reason: 'sin red se sigue con lo guardado');
      expect(Acceso.instancia.nombre, 'Carlos');
    });

    test('un codigo malo dice por que y no se guarda', () async {
      for (final (RespuestaAcceso r, String parte) in <(RespuestaAcceso, String)>[
        (RespuestaAcceso.noExiste, 'no existe'),
        (RespuestaAcceso.desactivado, 'desactivado'),
        (RespuestaAcceso.otroTelefono, 'otro telefono'),
        (RespuestaAcceso.espera, 'Espera unos minutos'),
        (RespuestaAcceso.sinRed, 'Conectate a internet'),
      ]) {
        respuesta = (estado: r, nombre: '');
        expect(await Acceso.instancia.introducir('1D43-B59C-7F4E'), contains(parte), reason: '$r');
        expect(Acceso.instancia.estado, EstadoAcceso.sinCodigo);
        expect(Acceso.instancia.hayCodigo, isFalse);
      }
    });

    test('lo que no parece un codigo ni se manda al servidor', () async {
      expect(await Acceso.instancia.introducir('  abc '), contains('no existe'));
      expect(preguntas, isEmpty);
    });

    test('renovar al volver al dia: el plazo empieza de nuevo', () async {
      await Acceso.instancia.introducir('1D43-B59C-7F4E');
      reloj = _hoy.add(const Duration(days: 9));
      await Acceso.instancia.cargar();
      expect(Acceso.instancia.estado, EstadoAcceso.sinDescargas, reason: 'a los 9 dias, sin descargas');

      await Acceso.instancia.revalidar();
      expect(Acceso.instancia.estado, EstadoAcceso.completo);
      expect(Acceso.instancia.validado!.isAtSameMomentAs(reloj), isTrue);
    });

    test('sin red no se renueva ni se castiga', () async {
      await Acceso.instancia.introducir('1D43-B59C-7F4E');
      reloj = _hoy.add(const Duration(days: 9));
      respuesta = (estado: RespuestaAcceso.sinRed, nombre: '');
      await Acceso.instancia.cargar();
      await Acceso.instancia.revalidar();
      expect(Acceso.instancia.estado, EstadoAcceso.sinDescargas);
      expect(Acceso.instancia.hayCodigo, isTrue);
    });

    test('si desactivan el codigo, la proxima vez que hay red se cierra', () async {
      await Acceso.instancia.introducir('1D43-B59C-7F4E');
      respuesta = (estado: RespuestaAcceso.desactivado, nombre: '');
      await Acceso.instancia.revalidar();
      expect(Acceso.instancia.estado, EstadoAcceso.sinCodigo);
      expect(Acceso.instancia.hayCodigo, isFalse);
      expect(Acceso.instancia.aviso, contains('desactivado'));
    });

    test('pasados 30 dias sin red no abre; con red y el mismo codigo, si', () async {
      await Acceso.instancia.introducir('1D43-B59C-7F4E');
      reloj = _hoy.add(const Duration(days: 31));
      respuesta = (estado: RespuestaAcceso.sinRed, nombre: '');
      await Acceso.instancia.cargar();
      expect(Acceso.instancia.estado, EstadoAcceso.caducado);

      respuesta = (estado: RespuestaAcceso.ok, nombre: 'Carlos');
      await Acceso.instancia.revalidar();
      expect(Acceso.instancia.estado, EstadoAcceso.completo);
    });

    test('si Android no da el id del telefono, se usa uno propio que se guarda', () async {
      Acceso.idDispositivo = () async => '';
      await Acceso.instancia.introducir('1D43-B59C-7F4E');
      await Acceso.instancia.revalidar();
      expect(preguntas, hasLength(2));
      expect(preguntas[0].$2, hasLength(32));
      expect(preguntas[1].$2, preguntas[0].$2, reason: 'el mismo siempre');
    });

    test('cerrar quita el codigo para escribir otro', () async {
      await Acceso.instancia.introducir('1D43-B59C-7F4E');
      await Acceso.instancia.cerrar();
      expect(Acceso.instancia.estado, EstadoAcceso.sinCodigo);
    });
  });

  group('buscar y bajar', () {
    final List<String> llamadas = <String>[];

    setUp(() {
      llamadas.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_canal,
          (MethodCall llamada) async {
        llamadas.add(llamada.method);
        return '{"ok":true,"resultados":[]}';
      });
    });

    test('con la puerta apagada (consola, pruebas) todo pasa', () async {
      Acceso.exigir = false;
      await Nucleo.buscar('algo');
      expect(llamadas, <String>['buscar']);
    });

    test('con acceso completo pasa', () async {
      await Acceso.instancia.introducir('1D43-B59C-7F4E');
      await Nucleo.buscar('algo');
      expect(llamadas, <String>['buscar']);
    });

    test('pasados 7 dias sin red: no busca ni baja, pero lo de dentro sigue', () async {
      await Acceso.instancia.introducir('1D43-B59C-7F4E');
      reloj = _hoy.add(const Duration(days: 8));
      respuesta = (estado: RespuestaAcceso.sinRed, nombre: '');
      await Acceso.instancia.cargar();

      await expectLater(Nucleo.buscar('algo'), throwsA(isA<ErrorNucleo>()));
      await expectLater(Nucleo.importarLista('https://x'), throwsA(isA<ErrorNucleo>()));
      await expectLater(Nucleo.calidad('https://x'), throwsA(isA<ErrorNucleo>()));
      expect(llamadas, isEmpty, reason: 'ni llega al nucleo');
      await Nucleo.biblioteca();
      expect(llamadas, <String>['biblioteca'], reason: 'escuchar lo que ya esta no se toca');
    });

    test('pasados 7 dias con red: se renueva en el momento y busca', () async {
      await Acceso.instancia.introducir('1D43-B59C-7F4E');
      reloj = _hoy.add(const Duration(days: 8));
      await Acceso.instancia.cargar();
      respuesta = (estado: RespuestaAcceso.ok, nombre: 'Carlos');

      await Nucleo.buscar('algo');
      expect(llamadas, <String>['buscar']);
      expect(Acceso.instancia.estado, EstadoAcceso.completo);
    });
  });

  group('la puerta', () {
    Widget app() => MaterialApp(
          theme: Tema.construir(),
          home: const PuertaDeAcceso(hijo: Scaffold(body: Text('ADENTRO'))),
        );

    Future<void> esperar(WidgetTester tester) async {
      for (int i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
        await tester.pump();
      }
    }

    testWidgets('sin codigo pide uno, y uno malo dice por que sin dejar pasar', (WidgetTester tester) async {
      await tester.runAsync(Acceso.instancia.cargar);
      await tester.pumpWidget(app());
      expect(find.text('Acceso a Tumbao'), findsOneWidget);
      expect(find.text('ADENTRO'), findsNothing);

      respuesta = (estado: RespuestaAcceso.otroTelefono, nombre: '');
      await tester.enterText(find.byType(TextField), '1d43-b59c-7f4e');
      await tester.tap(find.text('Entrar'));
      await esperar(tester);
      expect(find.textContaining('otro telefono'), findsOneWidget);
      expect(find.text('ADENTRO'), findsNothing);
    });

    testWidgets('con un codigo bueno entra', (WidgetTester tester) async {
      await tester.runAsync(Acceso.instancia.cargar);
      await tester.pumpWidget(app());
      await tester.enterText(find.byType(TextField), '1D43-B59C-7F4E');
      await tester.tap(find.text('Entrar'));
      await esperar(tester);
      expect(find.text('ADENTRO'), findsOneWidget);
      expect(find.text('Acceso a Tumbao'), findsNothing);
    });

    testWidgets('caducado: ofrece renovar el codigo que ya tiene', (WidgetTester tester) async {
      await tester.runAsync(() async {
        await Acceso.instancia.introducir('1D43-B59C-7F4E');
        reloj = _hoy.add(const Duration(days: 40));
        respuesta = (estado: RespuestaAcceso.sinRed, nombre: '');
        await Acceso.instancia.cargar();
      });
      await tester.pumpWidget(app());
      await esperar(tester); // la renovacion automatica de cargar() acaba (sin red)
      expect(find.text('Renueva tu acceso'), findsOneWidget);
      expect(find.text('ADENTRO'), findsNothing);

      await tester.tap(find.text('Renovar'));
      await esperar(tester);
      expect(find.textContaining('Conectate a internet'), findsWidgets, reason: 'sin red, lo dice');

      respuesta = (estado: RespuestaAcceso.ok, nombre: 'Carlos');
      await tester.tap(find.text('Renovar'));
      await esperar(tester);
      expect(find.text('ADENTRO'), findsOneWidget);
    });

    testWidgets('con acceso (aunque sin descargas) la app abre', (WidgetTester tester) async {
      await tester.runAsync(() async {
        await Acceso.instancia.introducir('1D43-B59C-7F4E');
        reloj = _hoy.add(const Duration(days: 10));
        respuesta = (estado: RespuestaAcceso.sinRed, nombre: '');
        await Acceso.instancia.cargar();
      });
      await tester.pumpWidget(app());
      expect(Acceso.instancia.estado, EstadoAcceso.sinDescargas);
      expect(find.text('ADENTRO'), findsOneWidget);
    });
  });
}
