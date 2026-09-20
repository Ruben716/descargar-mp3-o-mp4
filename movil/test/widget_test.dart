import 'dart:io';
import 'dart:math';

import 'package:descargador_movil/main.dart';
import 'package:descargador_movil/catalogo.dart';
import 'package:descargador_movil/control_descarga.dart';
import 'package:descargador_movil/ecualizador.dart';
import 'package:descargador_movil/estado_reproductor.dart';
import 'package:descargador_movil/listas.dart';
import 'package:descargador_movil/fila_pista.dart';
import 'package:descargador_movil/formato.dart';
import 'package:descargador_movil/letras.dart';
import 'package:descargador_movil/nucleo.dart';
import 'package:descargador_movil/orden_aleatorio.dart';
import 'package:descargador_movil/pantalla_biblioteca.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Respuestas del canal nativo. Las pruebas no arrancan Python ni tocan la red.
const MethodChannel _canal = MethodChannel('com.ruben.descargador/nucleo');

const String _busqueda = '{"ok":true,"resultados":['
    '{"titulo":"Cancion uno","autor":"Autor","duracion":254,"url":"https://www.youtube.com/watch?v=uno","miniatura":""},'
    '{"titulo":"Cancion dos","autor":"Otro","duracion":100,"url":"https://www.youtube.com/watch?v=dos","miniatura":""}]}';

void main() {
  // El almacenamiento del telefono tampoco existe en las pruebas.
  TestWidgetsFlutterBinding.ensureInitialized();
  // SQLite tampoco: se usa la version de escritorio, en memoria.
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final List<MethodCall> llamadas = <MethodCall>[];
  // Lo que el telefono dice tener; alguna prueba necesita que no este vacio.
  String biblioteca = '{"ok":true,"elementos":[]}';

  setUp(() async {
    llamadas.clear();
    biblioteca = '{"ok":true,"elementos":[]}';
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // El reproductor y la descarga son unicos para toda la app: sin esto
    // una prueba heredaria lo que dejo la anterior.
    EstadoReproductor.instancia.reiniciar();
    ControlDescarga.instancia.reiniciar();
    Listas.instancia.reiniciar();
    await Catalogo.instancia.usarEnMemoria();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canal, (MethodCall llamada) async {
      llamadas.add(llamada);
      return switch (llamada.method) {
        'urlCompartida' => null,
        'biblioteca' => biblioteca,
        'buscar' => _busqueda,
        'importarLista' =>
          '{"ok":true,"titulo":"Mis temas","resultados":'
              '${_busqueda.substring(_busqueda.indexOf('['), _busqueda.length - 1)}}',
        'caratula' => '{"ok":true,"imagen":""}',
        'previsualizar' =>
          '{"ok":true,"url":"https://cdn/p","titulo":"Cancion uno","cabeceras":{}}',
        'eliminar' => '{"ok":true}',
        'avisarLote' => '{"ok":true}',
        'compartirArchivo' => '{"ok":true}',
        'compartirEnlace' => '{"ok":true}',
        'descargar' => '{"ok":true,"archivos":["content://audio/99"]}',
        _ => '{"ok":true}',
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canal, null);
  });

  /// Abre la app y salta a Descargar, que ya no es la primera pestania.
  Future<void> abrir(WidgetTester tester) async {
    await tester.pumpWidget(const AplicacionTumbao());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descargar').last);
    await tester.pumpAndSettle();
  }

  /// Abre la app y se queda en Inicio.
  Future<void> abrirInicio(WidgetTester tester) async {
    await tester.pumpWidget(const AplicacionTumbao());
    await tester.pumpAndSettle();
  }

  /// Abre la app y salta a Biblioteca.
  Future<void> abrirBiblioteca(WidgetTester tester) async {
    await tester.pumpWidget(const AplicacionTumbao());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biblioteca').last);
    await tester.pumpAndSettle();
  }

  testWidgets('arranca en el buscador, con video y musica a elegir', (WidgetTester tester) async {
    await abrir(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
    expect(find.text('Musica'), findsOneWidget);
    // El titulo, el boton y la pestania comparten la palabra.
    expect(find.text('Descargar'), findsWidgets);
  });

  testWidgets('una busqueda pinta los resultados', (WidgetTester tester) async {
    await abrir(tester);

    await tester.enterText(find.byType(TextField), 'cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Cancion uno'), findsOneWidget);
    expect(find.text('Cancion dos'), findsOneWidget);
    expect(llamadas.any((MethodCall c) => c.method == 'buscar'), isTrue);
  });

  testWidgets('elegir un resultado cambia el boton de descarga', (WidgetTester tester) async {
    await abrir(tester);
    await tester.enterText(find.byType(TextField), 'cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancion uno'));
    await tester.pumpAndSettle();

    expect(find.text('Descargar seleccion'), findsOneWidget);
  });

  testWidgets('pegar un enlace de lista en el buscador ofrece traerla entera',
      (WidgetTester tester) async {
    // Regresion: antes habia que cambiar a modo URL primero, y pegarlo en el
    // buscador acababa en "Sin resultados".
    await abrir(tester);

    await tester.enterText(
      find.byType(TextField),
      'https://music.youtube.com/playlist?list=PLabc',
    );
    await tester.pumpAndSettle();
    expect(find.text('Traer la lista'), findsOneWidget);

    await tester.tap(find.text('Traer la lista'));
    await tester.pumpAndSettle();
    expect(find.text('Cancion uno'), findsOneWidget);
  });





  testWidgets('una lista traida dice cuantas trae y ofrece bajarla entera',
      (WidgetTester tester) async {
    await abrir(tester);
    await tester.enterText(
      find.byType(TextField),
      'https://music.youtube.com/playlist?list=PLabc',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Traer la lista'));
    await tester.pumpAndSettle();

    expect(find.text('2 pistas · Mis temas'), findsOneWidget);
    expect(find.text('Todo en video'), findsOneWidget);
  });

  testWidgets('en modo musica el boton del lote ofrece MP3',
      (WidgetTester tester) async {
    await abrir(tester);
    await tester.tap(find.text('Musica'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://music.youtube.com/playlist?list=PLabc',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Traer la lista'));
    await tester.pumpAndSettle();

    expect(find.text('Todo en MP3'), findsOneWidget);
  });

  testWidgets('los resultados de una busqueda no ofrecen descargar todo',
      (WidgetTester tester) async {
    await abrir(tester);
    await tester.enterText(find.byType(TextField), 'cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Cancion uno'), findsOneWidget);
    expect(find.textContaining('pistas ·'), findsNothing);
  });

  testWidgets('buscar con un enlace pegado no busca, lo resuelve',
      (WidgetTester tester) async {
    await abrir(tester);

    await tester.enterText(
      find.byType(TextField),
      'https://www.youtube.com/playlist?list=PLabc',
    );
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Cancion uno'), findsOneWidget);
    expect(llamadas.any((MethodCall c) => c.method == 'importarLista'), isTrue);
    expect(llamadas.any((MethodCall c) => c.method == 'buscar'), isFalse);
  });

  testWidgets('el panel de opciones se abre y ofrece lo del nucleo',
      (WidgetTester tester) async {
    await abrir(tester);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Opciones'), findsOneWidget);
    expect(find.text('SUBTITULOS'), findsOneWidget);
    expect(find.text('Quitar patrocinios'), findsOneWidget);
  });

  testWidgets('la app abre en inicio y guia cuando no hay nada',
      (WidgetTester tester) async {
    await abrirInicio(tester);

    expect(find.text('Empieza tu biblioteca'), findsOneWidget);
    expect(find.text('Buscar musica'), findsOneWidget);
  });

  testWidgets('desde inicio se llega a descargar', (WidgetTester tester) async {
    await abrirInicio(tester);

    await tester.tap(find.text('Buscar musica'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);
  });

  testWidgets('la biblioteca separa canciones, videos y listas',
      (WidgetTester tester) async {
    await abrir(tester);

    await tester.tap(find.text('Biblioteca'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Canciones (0)'), findsOneWidget);
    expect(find.textContaining('Listas (0)'), findsOneWidget);
  });

  testWidgets('escuchar un resultado abre su vista previa',
      (WidgetTester tester) async {
    await abrir(tester);
    await tester.enterText(find.byType(TextField), 'cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // Un boton de escucha por resultado.
    expect(find.byIcon(Icons.play_circle_outline_rounded), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.play_circle_outline_rounded).first);
    // pumpAndSettle no sirve aqui: mientras prepara la pista hay un indicador
    // circular girando y nunca quedaria en reposo. Se bombea a mano lo
    // suficiente para que la navegacion asincrona termine.
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }

    // La vista previa se ve: titulo, autor y aviso de que no esta bajado.
    expect(find.text('VISTA PREVIA'), findsOneWidget);
    expect(find.text('Todavia no esta en tu telefono'), findsOneWidget);
    expect(find.textContaining('Descargar'), findsWidgets);
  });

  testWidgets('cancelar el dialogo de nueva lista no rompe nada',
      (WidgetTester tester) async {
    // Regresion: el controlador del campo se liberaba antes de que el dialogo
    // terminara de cerrarse y Flutter abortaba con _dependents.isEmpty.
    await abrir(tester);
    await tester.tap(find.text('Biblioteca'));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('Listas ('));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nueva lista'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AlertDialog, 'Nueva lista'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(AlertDialog, 'Nueva lista'), findsNothing);
  });

  testWidgets('no se puede crear una lista sin nombre', (WidgetTester tester) async {
    await abrir(tester);
    await tester.tap(find.text('Biblioteca'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Listas ('));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nueva lista'));
    await tester.pumpAndSettle();

    final Finder crear = find.widgetWithText(FilledButton, 'Crear');
    expect(tester.widget<FilledButton>(crear).onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'Para correr');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(crear).onPressed, isNotNull);
  });

  test('una lista recuerda sus pistas y las olvida al borrar la descarga',
      () async {
    final Listas listas = Listas.instancia;
    await listas.crear('Prueba');
    await listas.alternar('Prueba', 'content://audio/1');
    expect(listas.contiene('Prueba', 'content://audio/1'), isTrue);

    // Un nombre repetido no crea una segunda lista.
    expect(await listas.crear('Prueba'), isFalse);

    // Al eliminar el archivo debe desaparecer de todas las listas.
    await listas.olvidar('content://audio/1');
    expect(listas.contiene('Prueba', 'content://audio/1'), isFalse);
    await listas.borrar('Prueba');
    expect(listas.nombres, isNot(contains('Prueba')));
  });

  test('el catalogo reconoce la misma pista aunque cambie la URL', () async {
    final Catalogo catalogo = Catalogo.instancia;
    // La misma cancion llega distinta segun de donde se comparta.
    expect(Catalogo.identificador('https://www.youtube.com/watch?v=abc123'), 'abc123');
    expect(Catalogo.identificador('https://music.youtube.com/watch?v=abc123&list=X'), 'abc123');
    expect(Catalogo.identificador('https://youtu.be/abc123'), 'abc123');

    await catalogo.registrar(
      'https://www.youtube.com/watch?v=abc123',
      audio: true,
      uri: 'content://audio/7',
    );
    final String? hallado = await catalogo.buscar(
      'https://music.youtube.com/watch?v=abc123&list=X',
      audio: true,
    );
    expect(hallado, 'content://audio/7');
  });

  test('tener el MP3 no es tener el video', () async {
    final Catalogo catalogo = Catalogo.instancia;
    await catalogo.registrar('https://y/watch?v=zzz', audio: true, uri: 'content://audio/1');

    expect(await catalogo.buscar('https://y/watch?v=zzz', audio: true), 'content://audio/1');
    expect(await catalogo.buscar('https://y/watch?v=zzz', audio: false), isNull);
  });

  test('al borrar una descarga el catalogo la olvida', () async {
    final Catalogo catalogo = Catalogo.instancia;
    await catalogo.registrar('https://y/watch?v=kkk', audio: true, uri: 'content://audio/9');
    expect(await catalogo.cuantas(), 1);

    await catalogo.olvidar('content://audio/9');
    expect(await catalogo.cuantas(), 0);
    // Y vuelve a considerarse descargable.
    expect(await catalogo.buscar('https://y/watch?v=kkk', audio: true), isNull);
  });

  /// Estas van como pruebas normales y no con testWidgets: alli el reloj es
  /// simulado y las operaciones de SQLite, que corren en otro isolate, nunca
  /// llegarian a terminar.
  Future<void> bajarLote({required bool audio}) async {
    ControlDescarga.instancia.reiniciar();
    ControlDescarga.instancia.cambiarAjustes(Ajustes(url: '', soloAudio: audio));
    await ControlDescarga.instancia.iniciarVarios(
      <String>[
        'https://www.youtube.com/watch?v=uno',
        'https://www.youtube.com/watch?v=dos',
      ],
      nombreLista: 'Mis temas',
    );
  }

  test('el lote deja la lista creada con lo descargado', () async {
    await bajarLote(audio: false);

    expect(Listas.instancia.nombres, contains('Mis temas'));
    expect(Listas.instancia.contiene('Mis temas', 'content://audio/99'), isTrue);
  });

  test('en un lote ninguna pista avisa: hay un solo aviso al final', () async {
    await bajarLote(audio: true);

    final List<MethodCall> descargas =
        llamadas.where((MethodCall c) => c.method == 'descargar').toList();
    expect(descargas.length, 2);
    for (final MethodCall c in descargas) {
      expect((c.arguments as Map<dynamic, dynamic>)['avisar'], isFalse);
    }
    final List<MethodCall> avisos =
        llamadas.where((MethodCall c) => c.method == 'avisarLote').toList();
    expect(avisos.length, 1);
    expect((avisos.single.arguments as Map<dynamic, dynamic>)['cantidad'], 2);
  });

  test('lo ya descargado no se baja otra vez, solo entra en la lista', () async {
    await Catalogo.instancia.registrar(
      'https://www.youtube.com/watch?v=uno',
      audio: true,
      uri: 'content://audio/ya',
    );
    biblioteca = '{"ok":true,"elementos":[{"nombre":"Ya.mp3",'
        '"uri":"content://audio/ya","duracion":10,"tamano":1,"audio":true}]}';

    await bajarLote(audio: true);

    final List<MethodCall> descargas =
        llamadas.where((MethodCall c) => c.method == 'descargar').toList();
    expect(descargas.length, 1);
    expect((descargas.single.arguments as Map<dynamic, dynamic>)['url'],
        'https://www.youtube.com/watch?v=dos');

    // La lista queda completa igual: la que ya estaba y la nueva.
    expect(Listas.instancia.contiene('Mis temas', 'content://audio/ya'), isTrue);
    expect(Listas.instancia.contiene('Mis temas', 'content://audio/99'), isTrue);
  });

  test('si el archivo ya no esta en el telefono se vuelve a bajar', () async {
    // En el catalogo pero borrada por fuera: la biblioteca va vacia.
    await Catalogo.instancia.registrar(
      'https://www.youtube.com/watch?v=uno',
      audio: true,
      uri: 'content://audio/fantasma',
    );

    await bajarLote(audio: true);

    expect(llamadas.where((MethodCall c) => c.method == 'descargar').length, 2);
  });

  test('una descarga suelta si avisa por si misma', () async {
    ControlDescarga.instancia.reiniciar();
    await ControlDescarga.instancia.iniciar('https://y/1');

    final MethodCall descarga =
        llamadas.lastWhere((MethodCall c) => c.method == 'descargar');
    expect((descarga.arguments as Map<dynamic, dynamic>)['avisar'], isTrue);
    expect(llamadas.any((MethodCall c) => c.method == 'avisarLote'), isFalse);
  });

  test('la repeticion cicla entre las tres opciones', () async {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    expect(estado.repeticion, LoopMode.off);

    await estado.alternarRepeticion();
    expect(estado.repeticion, LoopMode.all);

    await estado.alternarRepeticion();
    expect(estado.repeticion, LoopMode.one);

    // Y vuelve al principio, para poder apagarla sin reiniciar la app.
    await estado.alternarRepeticion();
    expect(estado.repeticion, LoopMode.off);
  });

  test('sin cola no hay siguiente ni anterior', () {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    expect(estado.cola, isEmpty);
    expect(estado.haySiguiente, isFalse);
    expect(estado.hayAnterior, isFalse);
  });

  test('los ajustes viajan al nucleo con los nombres que espera Kotlin', () {
    final Map<String, dynamic> mapa = const Ajustes(
      url: 'https://y/1',
      soloAudio: true,
      calidad: 720,
      bitrate: '320',
      subtitulos: 'es',
      fragmento: '00:10-00:20',
      sinPatrocinios: true,
    ).aMapa();

    expect(mapa['soloAudio'], isTrue);
    // En audio la altura no aplica: se manda 0 para que el nucleo la ignore.
    expect(mapa['calidad'], 0);
    expect(mapa['bitrate'], '320');
    expect(mapa['fragmento'], '00:10-00:20');
    expect(mapa['sinPatrocinios'], isTrue);
  });

  // --- Aleatorio, cola y temporizador ------------------------------------

  test('lo encolado a continuacion cae justo detras y no al azar', () {
    // Regresion: el orden de fabrica reparte las altas en un sitio cualquiera,
    // asi que "reproducir a continuacion" no reproducia a continuacion.
    // Se repite: con el reparto al azar acertar la posicion una vez es
    // cuestion de suerte, veinte seguidas no puede pasar.
    for (int intento = 0; intento < 20; intento++) {
      final OrdenAleatorio orden = OrdenAleatorio(azar: Random(intento));
      orden.insert(0, 5);
      orden.shuffle(initialIndex: 2);
      expect(orden.indices.first, 2, reason: 'lo que suena va en cabeza');

      orden.proximaInsercion = 1;
      orden.insert(5, 1);

      expect(orden.indices[1], 5);
      expect(orden.indices.length, 6);
    }
  });

  test('sin decir donde, lo encolado se reparte al azar', () {
    final OrdenAleatorio orden = OrdenAleatorio(azar: Random(7));
    orden.insert(0, 4);
    orden.insert(4, 1);

    // Cae donde sea, pero cae: ni se pierde ni se duplica.
    expect(orden.indices.toSet(), <int>{0, 1, 2, 3, 4});
  });

  test('al insertar en medio, la cola original se recoloca', () {
    final OrdenAleatorio orden = OrdenAleatorio();
    orden.insert(0, 3);
    orden.proximaInsercion = 0;
    orden.insert(1, 1);

    // La nueva ocupa la posicion 1, asi que las que estaban en 1 y 2 corren.
    expect(orden.indices.toSet(), <int>{0, 1, 2, 3});
    expect(orden.indices.first, 1);
  });

  test('al quitar pistas los indices se recolocan', () {
    final OrdenAleatorio orden = OrdenAleatorio();
    orden.insert(0, 5);
    orden.removeRange(1, 3);

    expect(orden.indices.toSet(), <int>{0, 1, 2});
  });

  test('el aleatorio se pone y se quita', () async {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    expect(estado.aleatorio, isFalse);

    await estado.alternarAleatorio();
    expect(estado.aleatorio, isTrue);

    await estado.alternarAleatorio();
    expect(estado.aleatorio, isFalse);
  });

  test('el temporizador queda puesto y se puede quitar', () {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    expect(estado.finSuenio, isNull);
    expect(estado.restanteSuenio, isNull);

    estado.dormirEn(const Duration(minutes: 30));
    expect(estado.finSuenio, isNotNull);
    expect(estado.restanteSuenio!.inMinutes, inInclusiveRange(29, 30));

    estado.cancelarSuenio();
    expect(estado.finSuenio, isNull);
  });

  test('cerrar el reproductor se lleva el temporizador por delante', () async {
    // Si no, la app se pausaria sola un rato despues de que ya no suene nada.
    final EstadoReproductor estado = EstadoReproductor.instancia;
    estado.dormirEn(const Duration(minutes: 15));

    await estado.cerrar();

    expect(estado.finSuenio, isNull);
  });

  // --- Buscar en la biblioteca -------------------------------------------

  test('la busqueda ignora tildes y mayusculas', () {
    expect(coincide('Corazon Partio', 'CORAZON'), isTrue);
    expect(coincide('Corazon Partio', 'partio'), isTrue);
    expect(coincide('Corazon Partio', 'bailando'), isFalse);
  });

  testWidgets('buscar en la biblioteca deja solo lo que casa',
      (WidgetTester tester) async {
    biblioteca = _conCanciones;
    await abrirBiblioteca(tester);
    expect(find.byType(FilaPista), findsNWidgets(3));

    await tester.enterText(find.byType(TextField), 'bailando');
    await tester.pumpAndSettle();

    expect(find.byType(FilaPista), findsOneWidget);
    expect(find.textContaining('Bailando'), findsWidgets);
  });

  testWidgets('una busqueda sin resultados lo dice', (WidgetTester tester) async {
    biblioteca = _conCanciones;
    await abrirBiblioteca(tester);

    await tester.enterText(find.byType(TextField), 'reggaeton');
    await tester.pumpAndSettle();

    expect(find.byType(FilaPista), findsNothing);
    expect(find.text('Nada con ese nombre.'), findsOneWidget);
  });

  testWidgets('ordenar alfabeticamente no se pierde con las tildes',
      (WidgetTester tester) async {
    biblioteca = _conCanciones;
    await abrirBiblioteca(tester);

    await tester.tap(find.byIcon(Icons.swap_vert_rounded));
    await tester.pumpAndSettle();
    // Se toca el elemento del menu y no su texto: el texto va desplazado
    // dentro de la fila y el toque caeria fuera.
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<Orden>, 'A - Z'));
    await tester.pumpAndSettle();

    final List<String> orden = tester
        .widgetList<FilaPista>(find.byType(FilaPista))
        .map((FilaPista f) => f.elemento.nombre)
        .toList();
    // "Amame" con tilde iria detras de la Z si se comparase en crudo.
    expect(orden.first, startsWith('Amame'));
    expect(orden.last, startsWith('Corazon'));
  });

  // --- Letras -------------------------------------------------------------

  test('la consulta se queda con el artista y el tema, sin el ruido', () {
    expect(
      Letras.consultaDe('Bad Bunny - Titi Me Pregunto (Video Oficial) | Un Verano [x1].mp3'),
      'Bad Bunny Titi Me Pregunto',
    );
    expect(
      Letras.consultaDe('Soda Stereo - De Musica Ligera (Official Video) [4K] [x2].mp3'),
      'Soda Stereo De Musica Ligera',
    );
  });

  test('un LRC se convierte en lineas con su instante', () {
    const String lrc = '[ar:Soda Stereo]\n'
        '[00:23.62] Ella durmio al calor de las masas\n'
        '[00:31.28] Y yo desperte queriendo sonarla\n'
        'sin marca, se ignora\n';

    final List<LineaLetra> lineas = Letras.analizarLrc(lrc);

    expect(lineas.length, 2);
    expect(lineas.first.desde, const Duration(seconds: 23, milliseconds: 620));
    expect(lineas.first.texto, 'Ella durmio al calor de las masas');
    expect(lineas.last.desde, const Duration(seconds: 31, milliseconds: 280));
  });

  test('una linea con varias marcas sale repetida en cada una', () {
    // Pasa con los estribillos: el LRC no repite el texto, repite el tiempo.
    final List<LineaLetra> lineas =
        Letras.analizarLrc('[00:10.00][01:20.50] El estribillo');

    expect(lineas.length, 2);
    expect(lineas.map((LineaLetra l) => l.texto).toSet(), <String>{'El estribillo'});
    expect(lineas.first.desde, const Duration(seconds: 10));
    expect(lineas.last.desde, const Duration(minutes: 1, seconds: 20, milliseconds: 500));
  });

  test('antes de la primera linea no se resalta ninguna', () {
    final Letra letra = Letra(
      lineas: Letras.analizarLrc('[00:23.00] Empieza aqui'),
      texto: '',
    );

    expect(letra.lineaEn(Duration.zero), -1);
    expect(letra.lineaEn(const Duration(seconds: 25)), 0);
  });

  test('entre versiones gana la que dura lo que nuestro archivo', () {
    // El mismo tema tiene version de album, remix y directo; la buena es la
    // que coincide en duracion con lo que tenemos bajado.
    final List<dynamic> candidatas = <dynamic>[
      <String, dynamic>{'duration': 180.0, 'syncedLyrics': '[00:01.00] corta'},
      <String, dynamic>{'duration': 291.0, 'syncedLyrics': '[00:01.00] la buena'},
      <String, dynamic>{'duration': 420.0, 'syncedLyrics': '[00:01.00] larga'},
    ];

    final Map<String, dynamic>? elegida = Letras.mejorCandidata(candidatas, 289);

    expect(elegida!['syncedLyrics'], contains('la buena'));
  });

  test('a igualdad de cercania se prefiere la sincronizada', () {
    final List<dynamic> candidatas = <dynamic>[
      <String, dynamic>{'duration': 200.0, 'plainLyrics': 'sin tiempos'},
      <String, dynamic>{'duration': 200.0, 'syncedLyrics': '[00:01.00] con tiempos'},
    ];

    final Map<String, dynamic>? elegida = Letras.mejorCandidata(candidatas, 200);

    expect(elegida!.containsKey('syncedLyrics'), isTrue);
  });

  test('una candidata sin letra no se elige', () {
    final List<dynamic> candidatas = <dynamic>[
      <String, dynamic>{'duration': 200.0, 'instrumental': true},
    ];

    expect(Letras.mejorCandidata(candidatas, 200), isNull);
  });

  test('la letra guardada vuelve tal cual, y "no habia" tambien se guarda', () async {
    final Catalogo catalogo = Catalogo.instancia;
    expect(await catalogo.letraDe('content://audio/1'), isNull);

    await catalogo.guardarLetra(
      'content://audio/1',
      lrc: '[00:05.00] Una linea',
      texto: 'Una linea',
    );
    expect((await catalogo.letraDe('content://audio/1'))!.lrc, contains('Una linea'));

    // Guardar vacio no es lo mismo que no haber buscado: sin distinguirlo se
    // repetiria la consulta fallida cada vez que se abre la cancion.
    await catalogo.guardarLetra('content://audio/2', lrc: '', texto: '');
    expect(await catalogo.letraDe('content://audio/2'), isNotNull);
  });

  test('un catalogo de la version vieja conserva lo descargado al actualizar',
      () async {
    // Lo mas delicado del cambio: en el telefono ya hay una base de la v1 con
    // las descargas dentro. Si la migracion estuviese mal, se perderian y todo
    // se volveria a bajar.
    final Directory temporal = await Directory.systemTemp.createTemp('tumbao');
    final String ruta = '${temporal.path}/catalogo.db';

    // Una base tal y como la dejo la version anterior: sin tabla de letras.
    final Database vieja = await openDatabase(
      ruta,
      version: 1,
      onCreate: (Database bd, int _) => bd.execute(
        'CREATE TABLE descargas (id TEXT NOT NULL, audio INTEGER NOT NULL, '
        'uri TEXT NOT NULL, fecha INTEGER NOT NULL, PRIMARY KEY (id, audio))',
      ),
    );
    await vieja.insert('descargas', <String, Object>{
      'id': 'abc123',
      'audio': 1,
      'uri': 'content://audio/7',
      'fecha': 0,
    });
    await vieja.close();

    final Database nueva = await Catalogo.abrirEn(ruta);
    try {
      expect(await nueva.getVersion(), 2);
      final List<Map<String, Object?>> filas = await nueva.query('descargas');
      expect(filas.length, 1, reason: 'lo descargado no se toca');
      expect(filas.first['uri'], 'content://audio/7');
      // Y la tabla nueva ya esta, lista para usarse.
      expect(await nueva.query('letras'), isEmpty);
    } finally {
      await nueva.close();
      await temporal.delete(recursive: true);
    }
  });

  // --- Ecualizador y volumen ---------------------------------------------

  test('los ajustes del ecualizador valen con cualquier numero de bandas', () {
    // Cada telefono reparte sus bandas como quiere: hay de cinco y de diez.
    for (final int bandas in <int>[5, 10]) {
      final List<double> graves = <double>[
        for (int i = 0; i < bandas; i++)
          Ajuste.graves.ganancia(i / (bandas - 1), 12),
      ];
      expect(graves.first, greaterThan(graves.last),
          reason: 'con $bandas bandas los graves suben abajo');

      final List<double> agudos = <double>[
        for (int i = 0; i < bandas; i++)
          Ajuste.agudos.ganancia(i / (bandas - 1), 12),
      ];
      expect(agudos.last, greaterThan(agudos.first));
    }
  });

  test('el ajuste plano deja todas las bandas a cero', () {
    for (final double posicion in <double>[0, 0.25, 0.5, 0.75, 1]) {
      expect(Ajuste.plano.ganancia(posicion, 12), 0);
    }
  });

  test('la voz sube el centro y la fiesta lo hunde', () {
    expect(Ajuste.voz.ganancia(0.5, 12), greaterThan(Ajuste.voz.ganancia(0, 12)));
    expect(Ajuste.fiesta.ganancia(0.5, 12), lessThan(Ajuste.fiesta.ganancia(0, 12)));
  });

  test('igualar el volumen no viaja con un formato que se copiaria', () {
    // El nucleo rechaza la descarga entera en ese caso, asi que se filtra aqui.
    for (final String formato in formatosSinNormalizar) {
      final Map<String, dynamic> mapa = Ajustes(
        url: 'https://y/1',
        soloAudio: true,
        normalizar: true,
        formatoAudio: formato,
      ).aMapa();
      expect(mapa['normalizar'], isFalse, reason: 'con $formato no se puede');
    }

    final Map<String, dynamic> mp3 = const Ajustes(
      url: 'https://y/1',
      soloAudio: true,
      normalizar: true,
    ).aMapa();
    expect(mp3['normalizar'], isTrue);
  });

  test('igualar el volumen no viaja al bajar video', () {
    final Map<String, dynamic> mapa = const Ajustes(
      url: 'https://y/1',
      normalizar: true,
    ).aMapa();

    expect(mapa['normalizar'], isFalse);
  });
}

/// Tres canciones con tildes y duraciones distintas, para filtrar y ordenar.
const String _conCanciones = '{"ok":true,"elementos":['
    '{"nombre":"Corazon Partio [c1].mp3","tamano":100,"duracion":300,"audio":true,"uri":"content://audio/1"},'
    '{"nombre":"Bailando [c2].mp3","tamano":100,"duracion":100,"audio":true,"uri":"content://audio/2"},'
    '{"nombre":"Amame [c3].mp3","tamano":100,"duracion":200,"audio":true,"uri":"content://audio/3"}]}';