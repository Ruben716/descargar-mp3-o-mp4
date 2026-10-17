import 'package:descargador_movil/animaciones.dart';
import 'package:descargador_movil/movimiento_reproductor.dart';
import 'package:descargador_movil/tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() => Movimiento.bucles = false);

  group('latido al compas', () {
    // 120 BPM: un pulso cada 500 ms, el primero a los 1000 ms.
    double golpe(int ms) => Latido.golpeEn(
          posicion: Duration(milliseconds: ms) + Latido.retraso,
          periodoMs: 500,
          pulsoInicioMs: 1000,
        );

    test('sube en cada pulso y cae antes del siguiente', () {
      expect(golpe(1000), closeTo(1, 1e-9), reason: 'justo en el pulso');
      expect(golpe(1500), closeTo(1, 1e-9), reason: 'y en el siguiente');
      expect(golpe(1250), lessThan(0.06), reason: 'a mitad, casi nada');
      expect(golpe(1100), greaterThan(golpe(1200)), reason: 'cae seguido');
      expect(golpe(900), 0, reason: 'antes del primer pulso no late');
    });

    test('la cuenta del ultimo compas', () {
      expect(Latido.cuentaEn(restante: const Duration(milliseconds: 2250), periodoMs: 500), isNull,
          reason: 'quedan mas de 4 pulsos');
      expect(Latido.cuentaEn(restante: const Duration(milliseconds: 1900), periodoMs: 500), 4);
      expect(Latido.cuentaEn(restante: const Duration(milliseconds: 600), periodoMs: 500), 2);
      expect(Latido.cuentaEn(restante: const Duration(milliseconds: 200), periodoMs: 500), 1);
      expect(Latido.cuentaEn(restante: Duration.zero, periodoMs: 500), isNull);
    });

    testWidgets('sin animaciones sin fin no corre ningun reloj', (WidgetTester tester) async {
      Latido? visto;
      await tester.pumpWidget(MaterialApp(
        home: ConLatido(
          child: Builder(builder: (BuildContext context) {
            visto = Latido.de(context);
            return const SizedBox();
          }),
        ),
      ));
      await tester.pumpAndSettle();
      expect(visto, isNotNull);
      expect(visto!.golpe.value, 0);
      expect(visto!.cuenta.value, isNull);
    });
  });

  group('barra ondulada', () {
    Future<List<double>> montar(WidgetTester tester, {double valor = 0.5}) async {
      final List<double> soltadas = <double>[];
      await tester.pumpWidget(MaterialApp(
        theme: Tema.construir(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 216,
              child: BarraOndulada(valor: valor, sonando: true, alSoltar: soltadas.add),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      return soltadas;
    }

    testWidgets('tocar lleva a ese punto', (WidgetTester tester) async {
      final List<double> soltadas = await montar(tester);
      final Offset izquierda = tester.getTopLeft(find.byType(BarraOndulada));
      await tester.tapAt(izquierda + const Offset(8 + 50, 18));
      expect(soltadas.single, closeTo(0.25, 0.01));
    });

    testWidgets('arrastrar solo salta al soltar', (WidgetTester tester) async {
      final List<double> soltadas = await montar(tester);
      final Offset izquierda = tester.getTopLeft(find.byType(BarraOndulada));
      final TestGesture gesto = await tester.startGesture(izquierda + const Offset(108, 18));
      await gesto.moveBy(const Offset(20, 0));
      await gesto.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(soltadas, isEmpty, reason: 'mientras se arrastra no se salta');
      await gesto.up();
      expect(soltadas.single, closeTo(0.8, 0.02));
    });

    testWidgets('dice su posicion a la accesibilidad', (WidgetTester tester) async {
      final SemanticsHandle semantica = tester.ensureSemantics();
      await montar(tester, valor: 0.3);
      expect(tester.getSemantics(find.bySemanticsLabel('Posicion de la cancion')).value, '30 %');
      semantica.dispose();
    });
  });
}
