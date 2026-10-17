import 'package:descargador_movil/animaciones.dart';
import 'package:descargador_movil/calidad.dart';
import 'package:descargador_movil/catalogo.dart';
import 'package:descargador_movil/favoritas.dart';
import 'package:descargador_movil/letras.dart';
import 'package:descargador_movil/nucleo.dart';
import 'package:descargador_movil/paleta.dart';
import 'package:descargador_movil/panel_letras.dart';
import 'package:descargador_movil/pantalla_lista_auto.dart';
import 'package:descargador_movil/portadas.dart';
import 'package:descargador_movil/secciones_inicio.dart';
import 'package:descargador_movil/tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Las animaciones sueltas: el karaoke, el corazon, el sello, la pastilla de
/// Pidele, las portadas que no existen y el contraste del reproductor.
///
/// Las que no acaban nunca solo se prueban con `Movimiento.bucles` encendido a
/// mano, con `pump` y no `pumpAndSettle`, y desmontando al final: si no, sus
/// temporizadores seguirian vivos al acabar la prueba.
const MethodChannel _canal = MethodChannel('com.ruben.descargador/nucleo');

Widget _app(Widget hijo, {bool reducido = false}) => MaterialApp(
      theme: Tema.construir(),
      home: Builder(
        builder: (BuildContext context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reducido),
          child: Scaffold(body: Center(child: hijo)),
        ),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final List<MethodCall> vibraciones = <MethodCall>[];

  setUp(() async {
    Movimiento.bucles = false;
    vibraciones.clear();
    Favoritas.instancia.reiniciar();
    Nucleo.olvidarCaratulas();
    await Catalogo.instancia.usarEnMemoria();
    final TestDefaultBinaryMessenger mensajero = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // Ninguna caratula: lo que se prueba es la que se inventa.
    mensajero.setMockMethodCallHandler(_canal, (MethodCall _) async => '{"ok":true}');
    mensajero.setMockMethodCallHandler(SystemChannels.platform, (MethodCall llamada) async {
      if (llamada.method == 'HapticFeedback.vibrate') vibraciones.add(llamada);
      return null;
    });
  });

  tearDown(() => Movimiento.bucles = false);

  group('letra karaoke', () {
    final Letra letra = Letra(
      lineas: const <LineaLetra>[
        LineaLetra(Duration(seconds: 10), 'Te llamo'),
        LineaLetra(Duration(seconds: 14), 'para decirte'),
      ],
      texto: '',
    );

    test('lo cantado va del verso actual al siguiente; el ultimo dura 4 s', () {
      expect(fraccionCantada(letra, 0, const Duration(seconds: 12)), closeTo(0.5, 1e-9));
      expect(fraccionCantada(letra, 0, const Duration(seconds: 9)), 0);
      expect(fraccionCantada(letra, 0, const Duration(seconds: 20)), 1);
      expect(fraccionCantada(letra, 1, const Duration(seconds: 15)), closeTo(0.25, 1e-9));
      expect(fraccionCantada(letra, 5, const Duration(seconds: 15)), 0, reason: 'fuera de la letra');
    });

    test('el desfase corre el relleno igual que el resaltado', () {
      final Letra corrida = letra.conDesfase(const Duration(seconds: 1));
      expect(corrida.lineaEn(const Duration(seconds: 13)), 0);
      expect(fraccionCantada(corrida, 0, const Duration(seconds: 13)), closeTo(0.5, 1e-9));
    });

    testWidgets('el verso que suena se tiñe con una mascara de corte duro', (WidgetTester tester) async {
      await tester.pumpWidget(_app(const VersoKaraoke(texto: 'Te llamo', cantado: 0.3)));
      expect(find.text('Te llamo'), findsOneWidget);
      final ShaderMask mascara = tester.widget<ShaderMask>(find.byType(ShaderMask));
      expect(mascara.blendMode, BlendMode.srcIn);
    });
  });

  group('me gusta', () {
    ScaleTransition salto(WidgetTester tester) => tester.widget<ScaleTransition>(
          find.descendant(of: find.byType(BotonMeGusta), matching: find.byType(ScaleTransition)).first,
        );

    testWidgets('al marcar da un salto y vibra; al quitar, no', (WidgetTester tester) async {
      await tester.pumpWidget(_app(const BotonMeGusta(uri: 'content://audio/1')));
      expect(salto(tester).scale.value, 1, reason: 'en reposo, a su tamano');

      await tester.tap(find.byTooltip('Me gusta'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(salto(tester).scale.value, greaterThan(1.05));
      expect(vibraciones.single.arguments, 'HapticFeedbackType.lightImpact');
      await tester.pumpAndSettle();
      expect(salto(tester).scale.value, 1);
      expect(find.byTooltip('Quitar de Me gusta'), findsOneWidget);

      await tester.tap(find.byTooltip('Quitar de Me gusta'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(salto(tester).scale.value, 1, reason: 'quitarlo no se celebra');
      expect(vibraciones, hasLength(1));
      await tester.pumpAndSettle();
    });

    testWidgets('con «Quitar animaciones» no hay salto, pero si vibra', (WidgetTester tester) async {
      await tester.pumpWidget(_app(const BotonMeGusta(uri: 'content://audio/1'), reducido: true));
      await tester.tap(find.byTooltip('Me gusta'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(salto(tester).scale.value, 1);
      expect(vibraciones, hasLength(1));
      expect(Favoritas.instancia.contiene('content://audio/1'), isTrue);
    });
  });

  group('sello con brillo', () {
    const CalidadAudio flac = CalidadAudio(codec: 'flac', bits: 16, hz: 44100);
    Finder reflejo() => find.descendant(of: find.byType(SelloCalidad), matching: find.byType(CustomPaint));

    testWidgets('sin bucles, o sin pedirlo, el sello queda como siempre', (WidgetTester tester) async {
      await tester.pumpWidget(_app(const SelloCalidad(calidad: flac, brillo: true)));
      expect(reflejo(), findsNothing, reason: 'en las pruebas no hay animaciones sin fin');

      Movimiento.bucles = true;
      await tester.pumpWidget(_app(const SelloCalidad(calidad: flac)));
      expect(reflejo(), findsNothing, reason: 'brillo es false por defecto');
      await tester.pumpWidget(_app(const SelloCalidad(
        calidad: CalidadAudio(codec: 'aac', kbps: 160),
        brillo: true,
      )));
      expect(reflejo(), findsNothing, reason: 'solo brilla lo sin perdida');
      expect(find.text('AAC 160 kb/s'), findsOneWidget);
    });

    testWidgets('con bucles, lo sin perdida brilla y al desmontar no deja nada', (WidgetTester tester) async {
      Movimiento.bucles = true;
      await tester.pumpWidget(_app(const SelloCalidad(calidad: flac, brillo: true)));
      expect(reflejo(), findsOneWidget);
      expect(find.text('SIN PERDIDA · FLAC'), findsOneWidget);
      // Primer cruce, descanso y segundo cruce: el ciclo se repite solo.
      await tester.pump(const Duration(milliseconds: 1600));
      await tester.pump(const Duration(milliseconds: 3600));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('pidele se escribe solo', () {
    Finder pastilla(String empieza) => find.textContaining('«$empieza');

    testWidgets('sin bucles se queda el primer ejemplo entero', (WidgetTester tester) async {
      await tester.pumpWidget(_app(const PastillaPidele(hora: 14)));
      expect(find.text('«salsa para cocinar»'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      expect(find.text('«salsa para cocinar»'), findsOneWidget);
    });

    testWidgets('con bucles escribe, espera, borra y pasa al siguiente', (WidgetTester tester) async {
      Movimiento.bucles = true;
      await tester.pumpWidget(_app(const PastillaPidele(hora: 14)));
      for (int i = 0; i < 5; i++) {
        await tester.pump(EjemploQueSeEscribe.paso);
      }
      expect(pastilla('salsa'), findsOneWidget);
      expect(pastilla('salsa '), findsNothing, reason: 'va letra a letra');

      for (int i = 0; i < 13; i++) {
        await tester.pump(EjemploQueSeEscribe.paso);
      }
      expect(pastilla('salsa para cocinar'), findsOneWidget);
      await tester.pump(EjemploQueSeEscribe.pausa);
      expect(pastilla('salsa para cocinar'), findsOneWidget, reason: 'se deja leer');

      // Borrar va de dos en dos: 18 letras en 9 pasos, y luego la siguiente.
      for (int i = 0; i < 16; i++) {
        await tester.pump(EjemploQueSeEscribe.paso);
      }
      expect(pastilla('salsa'), findsNothing);
      expect(pastilla('algo'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('portadas inventadas', () {
    test('cada artista tiene sus colores, siempre los mismos y de la marca', () {
      expect(colorDeArtista('Bad Bunny'), colorDeArtista('  bad bunny '));
      expect(colorDeArtista('Bad Bunny'), isNot(colorDeArtista('Shakira')));
      for (final String artista in <String>['Ana', 'Bad Bunny', 'Shakira', 'Rubén Blades', '', 'x']) {
        final (Color claro, Color oscuro) = colorDeArtista(artista);
        for (final Color c in <Color>[claro, oscuro]) {
          final double tono = HSLColor.fromColor(c).hue;
          expect(tono, inInclusiveRange(150, 285), reason: '$artista: del teal al violeta');
        }
        expect(oscuro.computeLuminance(), lessThan(claro.computeLuminance()), reason: artista);
      }
    });

    test('las iniciales: una o dos, sin signos ni «feat.»', () {
      expect(iniciales('Bad Bunny'), 'BB');
      expect(iniciales('shakira'), 'S');
      expect(iniciales('¡Ana feat. Luis!'), 'AL');
      expect(iniciales('Los Van Van y su orquesta'), 'LV');
      expect(iniciales('Ñengo Flow'), 'ÑF');
      expect(iniciales('  ...  '), '');
    });

    testWidgets('sin caratula se ven las iniciales del artista', (WidgetTester tester) async {
      const Elemento cancion = Elemento(
        nombre: 'Bad Bunny - Titi me pregunto.mp3',
        uri: 'content://audio/bb',
        duracion: 240,
        tamano: 1,
        audio: true,
        etiquetaArtista: 'Bad Bunny',
      );
      await tester.pumpWidget(_app(const PortadaLocal(elemento: cancion, lado: 120)));
      await tester.pumpAndSettle();
      expect(find.text('BB'), findsOneWidget);
      expect(find.byIcon(Icons.music_note), findsOneWidget, reason: 'la nota sigue, muy tenue');
    });
  });

  group('contraste del reproductor', () {
    test('un primario apagado de portada oscura se aclara hasta leerse', () {
      const Color apagado = Color(0xFF2B1E0C);
      expect(contraste(apagado, Tema.fondo), lessThan(4.5));
      final Color claro = conContraste(apagado, Tema.fondo);
      expect(contraste(claro, Tema.fondo), greaterThanOrEqualTo(4.5));
      expect(contraste(claro, Tema.fondo), lessThan(4.8), reason: 'lo justo, no blanco');
      expect(HSLColor.fromColor(claro).hue, closeTo(HSLColor.fromColor(apagado).hue, 2));
    });

    test('lo que ya se lee no se toca', () {
      expect(conContraste(Tema.acento, Tema.fondo), Tema.acento);
      expect(conContraste(Colors.white, Tema.fondo), Colors.white);
    });
  });
}
