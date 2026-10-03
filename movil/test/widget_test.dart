import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:descargador_movil/main.dart';
import 'package:descargador_movil/busqueda.dart';
import 'package:descargador_movil/calidad.dart';
import 'package:descargador_movil/catalogo.dart';
import 'package:descargador_movil/control_descarga.dart';
import 'package:descargador_movil/ecualizador.dart';
import 'package:descargador_movil/entrada.dart';
import 'package:descargador_movil/estado_reproductor.dart';
import 'package:descargador_movil/hoja_descarga.dart';
import 'package:descargador_movil/lista_secciones.dart';
import 'package:descargador_movil/listas.dart';
import 'package:descargador_movil/fila_pista.dart';
import 'package:descargador_movil/formato.dart';
import 'package:descargador_movil/letras.dart';
import 'package:descargador_movil/nucleo.dart';
import 'package:descargador_movil/orden_aleatorio.dart';
import 'package:descargador_movil/dialogo_etiquetas.dart';
import 'package:descargador_movil/paleta.dart';
import 'package:descargador_movil/pantalla_artista.dart';
import 'package:descargador_movil/pantalla_biblioteca.dart';
import 'package:descargador_movil/pantalla_descarga.dart';
import 'package:descargador_movil/portadas.dart';
import 'package:descargador_movil/reproductor.dart';
import 'package:descargador_movil/tema.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'motor_falso.dart';

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

  // Uno solo para todo el archivo: el reproductor tambien es unico.
  final MotorFalso motorFalso = MotorFalso();

  final List<MethodCall> llamadas = <MethodCall>[];
  // Lo que el telefono dice tener; alguna prueba necesita que no este vacio.
  String biblioteca = '{"ok":true,"elementos":[]}';
  /// Para dejar la lectura de la biblioteca a medias y colar algo por delante.
  Future<void>? frenoBiblioteca;
  /// Lo que otra app le comparte a esta al abrirla.
  String? compartida;
  /// Lo que responde cada fuente al buscar. Las que no esten, nada.
  ///
  /// Buscando en todas a la vez se pregunta a cada una: si todas devolvieran
  /// lo mismo, cada cancion saldria tres veces.
  Map<String, String> respuestas = <String, String>{};
  /// Lo que responde la comprobacion de calidad, por enlace. Por defecto, lo
  /// que da YouTube de verdad: Opus a 127 kb/s.
  Map<String, String> calidades = <String, String>{};
  /// Lo que responde una descarga. null: que sale bien.
  String? respuestaDescarga;
  /// Lo mismo con las caratulas, que es donde espera la cancion que va a sonar.
  Future<void>? frenoCaratula;

  setUp(() async {
    motorFalso.reiniciar();
    JustAudioPlatform.instance = motorFalso;
    // Parado, como al abrir la app: si se quedara activo de la prueba
    // anterior, la siguiente carga no volveria a activarlo y el fallo del
    // ecualizador, que sale justo al activar, no se veria nunca.
    await EstadoReproductor.instancia.motor.stop();
    motorFalso.reiniciar();
    llamadas.clear();
    biblioteca = '{"ok":true,"elementos":[]}';
    frenoBiblioteca = null;
    compartida = null;
    Nucleo.enlaceCompartido.value = null;
    respuestas = <String, String>{'youtube': _busqueda};
    calidades = <String, String>{};
    respuestaDescarga = null;
    PantallaDescargaState.olvidarBusquedas();
    frenoCaratula = null;
    SharedPreferences.setMockInitialValues(<String, Object>{});
    // El reproductor y la descarga son unicos para toda la app: sin esto
    // una prueba heredaria lo que dejo la anterior.
    EstadoReproductor.instancia.reiniciar();
    ControlDescarga.instancia.reiniciar();
    Listas.instancia.reiniciar();
    Nucleo.olvidarCaratulas();
    Paleta.vaciar();
    await Catalogo.instancia.usarEnMemoria();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canal, (MethodCall llamada) async {
      llamadas.add(llamada);
      if (llamada.method == 'biblioteca' && frenoBiblioteca != null) {
        await frenoBiblioteca;
      }
      if (llamada.method == 'caratula' && frenoCaratula != null) {
        await frenoCaratula;
      }
      return switch (llamada.method) {
        'urlCompartida' => compartida,
        'biblioteca' => biblioteca,
        'buscar' => respuestas[(llamada.arguments as Map<dynamic, dynamic>)['fuente']] ??
            '{"ok":true,"resultados":[]}',
        'calidad' => calidades[(llamada.arguments as Map<dynamic, dynamic>)['url']] ??
            '{"ok":true,"codec":"opus","kbps":127.0,"hz":48000,"sinPerdida":false}',
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
        'descargar' => respuestaDescarga ?? '{"ok":true,"archivos":["content://audio/99"]}',
        _ => '{"ok":true}',
      };
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_canal, null);
  });

  /// La pantalla del telefono de verdad (1080x2400), no la de 800x600 de
  /// las pruebas: en esa, lo que va debajo ni se llega a construir.
  void comoElTelefono(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
  }

  /// Abre la app y salta a Descargar, que ya no es la primera pestania.
  Future<void> abrir(WidgetTester tester) async {
    comoElTelefono(tester);
    await tester.pumpWidget(const AplicacionTumbao());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descargar').last);
    await tester.pumpAndSettle();
  }

  /// Abre la app y se queda en Inicio.
  Future<void> abrirInicio(WidgetTester tester) async {
    comoElTelefono(tester);
    await tester.pumpWidget(const AplicacionTumbao());
    await tester.pumpAndSettle();
  }

  /// Abre la app y salta a Biblioteca.
  Future<void> abrirBiblioteca(WidgetTester tester) async {
    comoElTelefono(tester);
    await tester.pumpWidget(const AplicacionTumbao());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Biblioteca').last);
    await tester.pumpAndSettle();
  }

  testWidgets('arranca con un solo campo para buscar o pegar un enlace',
      (WidgetTester tester) async {
    await abrir(tester);

    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Busca o pega un enlace'), findsOneWidget);
    expect(find.text('Pegar'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'YouTube'), findsOneWidget);
    // Ya no hay dos modos entre los que cambiar.
    expect(find.byTooltip('Usar una URL'), findsNothing);
    // Musica o video se elige al descargar, con lo que se baja delante.
    expect(find.text('Musica'), findsNothing);
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

  testWidgets('tocar un resultado pregunta como bajarlo y lo baja asi',
      (WidgetTester tester) async {
    await abrir(tester);
    await tester.enterText(find.byType(TextField), 'cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancion uno'));
    await tester.pumpAndSettle();

    // Lo que se va a bajar, delante, y las dos maneras.
    expect(find.text('¿Como lo quieres?'), findsOneWidget);
    expect(find.text('Cancion uno'), findsWidgets);
    expect(find.text('Musica'), findsOneWidget);
    expect(find.text('Video'), findsOneWidget);

    await tester.tap(find.text('Musica'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descargar musica'));
    await tester.pump();
    // Antes de bajar se consulta el catalogo, que es una base de datos de
    // verdad: necesita tiempo real, no el reloj de mentira de la prueba.
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    // El vigilante del progreso pregunta cada medio segundo hasta que acaba.
    await tester.pump(const Duration(seconds: 1));

    final MethodCall descarga = llamadas.lastWhere((MethodCall c) => c.method == 'descargar');
    expect((descarga.arguments as Map<dynamic, dynamic>)['soloAudio'], isTrue);
  });

  /// Busca, toca el primer resultado y lo baja como musica, esperando al final.
  Future<void> bajarElPrimero(WidgetTester tester) async {
    await abrir(tester);
    await tester.enterText(find.byType(TextField), 'cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancion uno'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Descargar musica'));
    await tester.pump();
    // El catalogo es una base de datos de verdad: necesita tiempo real.
    for (int i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('al acabar se dice como fue, aunque la lista este llena', (WidgetTester tester) async {
    // El fallo que arregla: el resultado solo se pintaba si no habia
    // resultados, y bajando de una busqueda siempre los hay.
    await bajarElPrimero(tester);

    expect(find.text('Cancion dos'), findsOneWidget, reason: 'la lista sigue ahi');
    expect(find.text('Guardado en tu biblioteca.'), findsOneWidget);
  });

  testWidgets('un fallo al descargar tambien se ve, con su detalle', (WidgetTester tester) async {
    respuestaDescarga = '{"ok":false,"error":"No se pudo meter la portada.",'
        '"registro":["ERROR: Postprocessing: mutagen no esta"]}';
    await bajarElPrimero(tester);

    expect(find.text('No se pudo meter la portada.'), findsOneWidget);
    await tester.tap(find.text('Detalle'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver detalle tecnico'));
    await tester.pumpAndSettle();
    expect(find.textContaining('mutagen no esta'), findsOneWidget);
  });

  testWidgets('con un origen sin perdida se puede pedir MP3 para ir rapido',
      (WidgetTester tester) async {
    respuestas['audius'] = '{"ok":true,"resultados":[{"titulo":"Cancion uno","autor":"Grupo",'
        '"duracion":180,"url":"https://audius.co/grupo/cancion-uno","miniatura":"",'
        '"calidad":{"codec":"wav","sinPerdida":true}}]}';
    respuestas.remove('youtube');
    comoElTelefono(tester);
    await abrir(tester);
    await tester.enterText(find.byType(TextField), 'cancion uno');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancion uno'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Pesa mucho mas'), findsOneWidget);

    await tester.tap(find.text('Mejor MP3'));
    await tester.pumpAndSettle();

    expect(find.text('MP3 · 192 kb/s'), findsOneWidget);
    expect(find.textContaining('Pesa mucho mas'), findsNothing);
  });

  testWidgets('cerrar la hoja sin elegir no descarga nada', (WidgetTester tester) async {
    await abrir(tester);
    await tester.enterText(find.byType(TextField), 'cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancion uno'));
    await tester.pumpAndSettle();

    // Tocar fuera de la hoja la cierra, como en cualquier app.
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(find.text('¿Como lo quieres?'), findsNothing);
    expect(llamadas.any((MethodCall c) => c.method == 'descargar'), isFalse);
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
    // Antes de pulsar ya se dice que es y que va a pasar.
    expect(find.text('Lista de YouTube Music: veras sus pistas antes de bajarlas'),
        findsOneWidget);
    expect(find.text('Ver la lista'), findsOneWidget);

    await tester.tap(find.text('Ver la lista'));
    await tester.pumpAndSettle();
    expect(find.text('Cancion uno'), findsOneWidget);
  });





  testWidgets('pulsar sin escribir nada dice que hacer, debajo del campo',
      (WidgetTester tester) async {
    await abrir(tester);

    await tester.tap(find.widgetWithText(BotonDegradado, 'Buscar'));
    await tester.pumpAndSettle();

    expect(find.text('Escribe el nombre de una cancion o pega un enlace.'), findsOneWidget);
    expect(llamadas.any((MethodCall c) => c.method == 'buscar'), isFalse);
  });

  testWidgets('un enlace roto se avisa al pulsar y no arranca nada',
      (WidgetTester tester) async {
    const String aviso =
        'Ese enlace esta incompleto. Copialo otra vez desde la app donde lo viste.';
    await abrir(tester);

    await tester.enterText(find.byType(TextField), 'https//youtube.com/watch?v=abc');
    await tester.pumpAndSettle();
    // Mientras se escribe no se riñe: puede que aun no este terminado.
    expect(find.text(aviso), findsNothing);

    await tester.tap(find.widgetWithText(BotonDegradado, 'Descargar'));
    await tester.pumpAndSettle();
    expect(find.text(aviso), findsOneWidget);
    expect(find.text('¿Como lo quieres?'), findsNothing);
    expect(llamadas.any((MethodCall c) => c.method == 'descargar'), isFalse);

    // Y al volver a escribir se va.
    await tester.enterText(find.byType(TextField), 'https://youtu.be/abc');
    await tester.pumpAndSettle();
    expect(find.text(aviso), findsNothing);
  });

  testWidgets('un enlace dice de donde es, quita las fuentes y ofrece descargar',
      (WidgetTester tester) async {
    await abrir(tester);

    await tester.enterText(find.byType(TextField), 'Mira esto https://vm.tiktok.com/ZM123/ !');
    await tester.pumpAndSettle();

    expect(find.text('Enlace de TikTok: se descarga lo que abre'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'YouTube'), findsNothing);
    expect(find.widgetWithText(BotonDegradado, 'Descargar'), findsOneWidget);

    await tester.tap(find.widgetWithText(BotonDegradado, 'Descargar'));
    await tester.pumpAndSettle();
    expect(find.text('Enlace de TikTok'), findsOneWidget);
    expect(find.text('https://vm.tiktok.com/ZM123/'), findsOneWidget,
        reason: 'se baja el enlace, no la frase que lo acompanaba');
  });

  testWidgets('un video abierto desde una lista ofrece tambien la lista',
      (WidgetTester tester) async {
    await abrir(tester);

    await tester.enterText(
      find.byType(TextField),
      'https://www.youtube.com/watch?v=abc&list=PLxyz',
    );
    await tester.pumpAndSettle();

    // Lo que se estaba viendo es el video: eso es lo que baja el boton.
    expect(find.widgetWithText(BotonDegradado, 'Descargar'), findsOneWidget);
    await tester.tap(find.text('Ver la lista entera'));
    await tester.pumpAndSettle();

    final MethodCall pedida =
        llamadas.lastWhere((MethodCall c) => c.method == 'importarLista');
    expect((pedida.arguments as Map<dynamic, dynamic>)['url'],
        'https://www.youtube.com/playlist?list=PLxyz');
  });

  testWidgets('el boton Pegar trae lo copiado', (WidgetTester tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall llamada) async => llamada.method == 'Clipboard.getData'
          ? <String, dynamic>{'text': '  https://youtu.be/abc  '}
          : null,
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    await abrir(tester);

    await tester.tap(find.text('Pegar'));
    await tester.pumpAndSettle();

    expect(find.text('https://youtu.be/abc'), findsOneWidget);
    expect(find.text('Enlace de YouTube: se descarga lo que abre'), findsOneWidget);
  });

  testWidgets('un enlace compartido abre directamente como bajarlo',
      (WidgetTester tester) async {
    compartida = 'https://www.instagram.com/reel/abc/';

    // Sin tocar la pestania: la app abre en Inicio y tiene que ir sola.
    await abrirInicio(tester);

    expect(find.text('¿Como lo quieres?'), findsOneWidget);
    expect(find.text('Enlace de Instagram'), findsOneWidget);
    final NavigationBar barra = tester.widget(find.byType(NavigationBar));
    expect(barra.selectedIndex, 1, reason: 'se queda en Descargar, donde se vera el progreso');
  });

  testWidgets('un nombre compartido se busca directamente', (WidgetTester tester) async {
    compartida = 'cancion';

    await abrirInicio(tester);

    expect(find.text('Cancion uno'), findsOneWidget);
    expect(llamadas.any((MethodCall c) => c.method == 'buscar'), isTrue);
  });

  testWidgets('una lista traida dice cuantas trae y ofrece bajarla entera',
      (WidgetTester tester) async {
    await abrir(tester);
    await tester.enterText(
      find.byType(TextField),
      'https://music.youtube.com/playlist?list=PLabc',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver la lista'));
    await tester.pumpAndSettle();

    expect(find.text('2 pistas · Mis temas'), findsOneWidget);
    expect(find.text('Descargar todo'), findsOneWidget);
  });

  testWidgets('bajar la lista entera pregunta como y dice cuantas son',
      (WidgetTester tester) async {
    await abrir(tester);
    await tester.enterText(
      find.byType(TextField),
      'https://music.youtube.com/playlist?list=PLabc',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver la lista'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Descargar todo'));
    await tester.pumpAndSettle();
    // La primera vez, musica: es una app para escuchar.
    expect(find.text('Descargar las 2 en musica'), findsOneWidget);

    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    expect(find.text('Descargar las 2 en video'), findsOneWidget);
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
    await tester.enterText(find.byType(TextField), 'cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancion uno'));
    await tester.pumpAndSettle();

    // Las opciones de siempre, ahora desde donde se decide como bajarlo.
    await tester.tap(find.text('Video'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mas opciones'));
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
    expect(find.text('Busca o pega un enlace'), findsOneWidget);
  });

  testWidgets('la biblioteca separa canciones, videos y listas',
      (WidgetTester tester) async {
    await abrir(tester);

    await tester.tap(find.text('Biblioteca'));
    await tester.pumpAndSettle();

    // Fichas y no pestanias con la cuenta: cuatro no cabian en un telefono.
    for (final String seccion in <String>['Canciones', 'Artistas', 'Videos', 'Listas']) {
      expect(find.widgetWithText(ChoiceChip, seccion), findsOneWidget);
    }
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

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Listas'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Listas'));
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
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Listas'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Listas'));
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

  test('lo elegido para descargar se recuerda al volver a abrir la app', () async {
    final ControlDescarga control = ControlDescarga.instancia;
    control.cambiarAjustes(
      const Ajustes(url: '', calidad: 1080, fragmento: '1:00-2:00'),
    );
    await Future<void>.delayed(Duration.zero);

    // Como si se cerrara la app: vuelve a lo de fabrica y se recupera.
    control.reiniciar();
    expect(control.ajustes.soloAudio, isTrue, reason: 'de fabrica es musica');
    await control.recuperarAjustes();

    expect(control.ajustes.soloAudio, isFalse, reason: 'pero se eligio video');
    expect(control.ajustes.calidad, 1080);
    expect(control.ajustes.fragmento, isEmpty,
        reason: 'el trozo era para un video concreto, no para todos');
  });

  test('el trozo se usa en su descarga y despues se quita', () async {
    final ControlDescarga control = ControlDescarga.instancia;
    control.reiniciar();
    control.cambiarAjustes(const Ajustes(url: '', fragmento: '1:00-2:00'));

    await control.iniciar('https://y/1');

    final MethodCall descarga = llamadas.lastWhere((MethodCall c) => c.method == 'descargar');
    expect((descarga.arguments as Map<dynamic, dynamic>)['fragmento'], '1:00-2:00');
    expect(control.ajustes.fragmento, isEmpty,
        reason: 'si no, la siguiente descarga saldria recortada sin pedirlo');
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
      // Salta cinco versiones de una vez, que es lo que le pasa a quien no
      // actualizo la app en un tiempo.
      expect(await nueva.getVersion(), 6);
      final List<Map<String, Object?>> filas = await nueva.query('descargas');
      expect(filas.length, 1, reason: 'lo descargado no se toca');
      expect(filas.first['uri'], 'content://audio/7');
      // Y las tablas nuevas ya estan, listas para usarse.
      expect(await nueva.query('letras'), isEmpty);
      expect(await nueva.query('escuchas'), isEmpty);
      expect(await nueva.query('calidades'), isEmpty);
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

  // --- Lo mas escuchado ---------------------------------------------------

  test('las escuchas se suman y salen de la mas oida a la menos', () async {
    final Catalogo catalogo = Catalogo.instancia;

    await catalogo.anotarEscucha('content://audio/1');
    await catalogo.anotarEscucha('content://audio/2');
    await catalogo.anotarEscucha('content://audio/2');
    await catalogo.anotarEscucha('content://audio/2');
    await catalogo.anotarEscucha('content://audio/3');
    await catalogo.anotarEscucha('content://audio/3');

    final List<({String uri, int veces})> ranking = await catalogo.masEscuchadas();

    expect(ranking.map((({String uri, int veces}) f) => f.uri).toList(),
        <String>['content://audio/2', 'content://audio/3', 'content://audio/1']);
    expect(ranking.first.veces, 3);
  });

  test('borrar una descarga se lleva sus escuchas y su letra', () async {
    // Si no, una pista borrada seguiria encabezando lo mas oido sin poder abrirse.
    final Catalogo catalogo = Catalogo.instancia;
    await catalogo.registrar('https://www.youtube.com/watch?v=abc',
        audio: true, uri: 'content://audio/9');
    await catalogo.anotarEscucha('content://audio/9');
    await catalogo.guardarLetra('content://audio/9', lrc: '[00:01.00] Algo', texto: 'Algo');

    await catalogo.olvidar('content://audio/9');

    expect(await catalogo.vecesEscuchada('content://audio/9'), 0);
    expect(await catalogo.letraDe('content://audio/9'), isNull);
    expect(await catalogo.buscar('https://www.youtube.com/watch?v=abc', audio: true), isNull);
  });

  test('pasar canciones de largo no las cuenta como escuchadas', () async {
    // El minimo existe para que buscar una cancion saltando veinte no deje a
    // las veinte como oidas.
    expect(EstadoReproductor.minimoParaContar, greaterThanOrEqualTo(
        const Duration(seconds: 15)));
  });

  test('el catalogo de la v5 gana los bits sin perder las calidades', () async {
    // La v5 guardaba la calidad sin los bits. Al pasar a la 6 se anaden, y lo
    // que ya estaba anotado tiene que seguir ahi.
    final Directory temporal = await Directory.systemTemp.createTemp('tumbao');
    final String ruta = '${temporal.path}/catalogo.db';
    final Database vieja = await openDatabase(
      ruta,
      version: 5,
      onCreate: (Database bd, int _) async {
        await bd.execute(
          'CREATE TABLE descargas (id TEXT NOT NULL, audio INTEGER NOT NULL, '
          'uri TEXT NOT NULL, fecha INTEGER NOT NULL, PRIMARY KEY (id, audio))',
        );
        await bd.execute(
          'CREATE TABLE letras (uri TEXT PRIMARY KEY, lrc TEXT NOT NULL, texto TEXT NOT NULL, '
          'fecha INTEGER NOT NULL, desfase INTEGER NOT NULL DEFAULT 0)',
        );
        await bd.execute(
          'CREATE TABLE escuchas (uri TEXT PRIMARY KEY, veces INTEGER NOT NULL, ultima INTEGER NOT NULL)',
        );
        await bd.execute(
          'CREATE TABLE calidades (uri TEXT PRIMARY KEY, codec TEXT NOT NULL, kbps REAL, '
          'hz INTEGER, fecha INTEGER NOT NULL)',
        );
      },
    );
    await vieja.insert('calidades', <String, Object>{
      'uri': 'content://audio/1', 'codec': 'opus', 'kbps': 127.0, 'hz': 48000, 'fecha': 0,
    });
    await vieja.close();

    final Database nueva = await Catalogo.abrirEn(ruta);
    try {
      expect(await nueva.getVersion(), 6);
      final List<Map<String, Object?>> filas = await nueva.query('calidades');
      expect(filas.single['codec'], 'opus', reason: 'lo anotado no se pierde');
      expect(filas.single.containsKey('bits'), isTrue, reason: 'y la columna nueva ya esta');
    } finally {
      await nueva.close();
      await temporal.delete(recursive: true);
    }
  });

  test('el catalogo de la v2 tambien se actualiza sin perder nada', () async {
    final Directory temporal = await Directory.systemTemp.createTemp('tumbao');
    final String ruta = '${temporal.path}/catalogo.db';

    final Database vieja = await openDatabase(
      ruta,
      version: 2,
      onCreate: (Database bd, int _) async {
        await bd.execute(
          'CREATE TABLE descargas (id TEXT NOT NULL, audio INTEGER NOT NULL, '
          'uri TEXT NOT NULL, fecha INTEGER NOT NULL, PRIMARY KEY (id, audio))',
        );
        await bd.execute(
          'CREATE TABLE letras (uri TEXT PRIMARY KEY, lrc TEXT NOT NULL, '
          'texto TEXT NOT NULL, fecha INTEGER NOT NULL)',
        );
      },
    );
    await vieja.insert('descargas', <String, Object>{
      'id': 'xyz', 'audio': 1, 'uri': 'content://audio/5', 'fecha': 0,
    });
    await vieja.insert('letras', <String, Object>{
      'uri': 'content://audio/5', 'lrc': '[00:01.00] Hola', 'texto': 'Hola', 'fecha': 0,
    });
    await vieja.close();

    final Database nueva = await Catalogo.abrirEn(ruta);
    try {
      expect(await nueva.getVersion(), 6);
      expect((await nueva.query('descargas')).length, 1, reason: 'lo descargado no se toca');
      // Las letras si se tiran, y a proposito: las guardadas antes se
      // eligieron sin comprobar que la cancion fuera la pedida, asi que
      // algunas eran de otro tema. Se vuelven a buscar bien.
      expect(await nueva.query('letras'), isEmpty);
      expect(await nueva.query('escuchas'), isEmpty);
    } finally {
      await nueva.close();
      await temporal.delete(recursive: true);
    }
  });

  // --- La letra tiene que ser la de esta cancion --------------------------

  test('el nombre se parte en artista y tema', () {
    expect(Letras.partesDe('Soda Stereo - De Musica Ligera [x1].mp3'),
        (artista: 'Soda Stereo', tema: 'De Musica Ligera'));
    expect(Letras.partesDe('KAROL G, Shakira - TQG (Official Video) [x2].mp3'),
        (artista: 'KAROL G, Shakira', tema: 'TQG'));
    // Sin guion no hay artista que sacar, y el tema es el nombre entero.
    expect(Letras.partesDe('Un tema suelto [x3].mp3'),
        (artista: '', tema: 'Un tema suelto'));
  });

  test('el parecido ignora tildes, mayusculas y puntuacion', () {
    expect(Letras.parecido('De Música Ligera', 'de musica ligera'), 1);
    // El servidor a veces repite el artista dentro del nombre del tema.
    expect(Letras.parecido('Soda Stereo - De Música Ligera', 'De Musica Ligera'), 1);
    expect(Letras.parecido('Adios Amor', 'Motor y Motivo'), 0);
  });

  test('no se acepta la letra de otra cancion aunque dure lo mismo', () {
    // Esto es lo que pasaba de verdad: buscando un tema de un grupo, el
    // servidor devuelve medio catalogo del grupo, y se colaba el que durase
    // parecido. Una letra equivocada es peor que ninguna.
    final List<dynamic> candidatas = <dynamic>[
      <String, dynamic>{
        'trackName': 'Adios Amor',
        'duration': 245.0,
        'syncedLyrics': '[00:01.00] linea',
      },
      <String, dynamic>{
        'trackName': 'Motor Y Motivo',
        'duration': 197.0,
        'syncedLyrics': '[00:01.00] linea',
      },
    ];

    final Map<String, dynamic>? elegida =
        Letras.mejorCandidata(candidatas, 245, tema: 'Motor y Motivo');

    expect(elegida!['trackName'], 'Motor Y Motivo');
  });

  test('si ninguna es la cancion pedida, se prefiere quedarse sin letra', () {
    final List<dynamic> candidatas = <dynamic>[
      <String, dynamic>{
        'trackName': 'Otra Cosa',
        'duration': 200.0,
        'syncedLyrics': '[00:01.00] linea',
      },
    ];

    expect(Letras.mejorCandidata(candidatas, 200, tema: 'Motor y Motivo'), isNull);
  });

  test('una candidata sin duracion no le gana a la que si encaja', () {
    // Antes puntuaba cero, que es la mejor nota posible, y salia elegida
    // siempre por no poder compararla.
    final List<dynamic> candidatas = <dynamic>[
      <String, dynamic>{'trackName': 'El Tema', 'syncedLyrics': '[00:01.00] sin duracion'},
      <String, dynamic>{
        'trackName': 'El Tema',
        'duration': 200.0,
        'syncedLyrics': '[00:01.00] con duracion',
      },
    ];

    final Map<String, dynamic>? elegida =
        Letras.mejorCandidata(candidatas, 200, tema: 'El Tema');

    expect(elegida!['duration'], 200.0);
  });

  test('el desfase corre la letra entera', () {
    final Letra letra = Letra(
      lineas: Letras.analizarLrc('[00:10.00] una\n[00:20.00] otra'),
      texto: '',
    );
    expect(letra.lineaEn(const Duration(seconds: 12)), 0);
    expect(letra.lineaEn(const Duration(seconds: 22)), 1);

    // Con cinco segundos de retraso, a los 12 aun no ha entrado la primera.
    final Letra retrasada = letra.conDesfase(const Duration(seconds: 5));
    expect(retrasada.lineaEn(const Duration(seconds: 12)), -1);
    expect(retrasada.lineaEn(const Duration(seconds: 16)), 0);

    // Y adelantandola, entra antes.
    final Letra adelantada = letra.conDesfase(const Duration(seconds: -5));
    expect(adelantada.lineaEn(const Duration(seconds: 6)), 0);
  });

  test('el ajuste de sincronia se guarda y vuelve con la letra', () async {
    final Catalogo catalogo = Catalogo.instancia;
    await catalogo.guardarLetra('content://audio/4', lrc: '[00:01.00] algo', texto: 'algo');
    expect((await catalogo.letraDe('content://audio/4'))!.desfase, 0);

    await catalogo.guardarDesfase('content://audio/4', 1500);

    expect((await catalogo.letraDe('content://audio/4'))!.desfase, 1500);
  });

  // --- El video vertical tiene que caber -----------------------------------

  /// Un movil en vertical, que es donde se vio el fallo.
  Future<void> enPantallaDeMovil(WidgetTester tester, Widget hijo) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: hijo)));
  }

  testWidgets('un video vertical no empuja los controles fuera de la pantalla',
      (WidgetTester tester) async {
    await enPantallaDeMovil(
      tester,
      const MarcoVideo(
        // 9:16, un reel. Con la altura libre se estiraba a 1,78 veces el ancho.
        proporcion: 9 / 16,
        video: ColoredBox(color: Colors.black),
        controles: SizedBox(height: 200, key: ValueKey<String>('controles')),
      ),
    );

    expect(tester.takeException(), isNull);
    // Y los controles se ven enteros, no solo "sin excepcion".
    final double abajo = tester.getBottomLeft(find.byKey(const ValueKey<String>('controles'))).dy;
    expect(abajo, lessThanOrEqualTo(tester.view.physicalSize.height / tester.view.devicePixelRatio));
  });

  testWidgets('el hueco libre era lo que desbordaba', (WidgetTester tester) async {
    // Demuestra la causa: el mismo contenido con Spacer, como estaba antes.
    await enPantallaDeMovil(
      tester,
      const Column(
        children: <Widget>[
          Spacer(),
          AspectRatio(aspectRatio: 9 / 16, child: ColoredBox(color: Colors.black)),
          Spacer(),
          SizedBox(height: 200),
        ],
      ),
    );

    expect(tester.takeException(), isNotNull);
  });

  testWidgets('un video apaisado se sigue viendo igual', (WidgetTester tester) async {
    await enPantallaDeMovil(
      tester,
      const MarcoVideo(
        proporcion: 16 / 9,
        video: ColoredBox(color: Colors.black, key: ValueKey<String>('video')),
        controles: SizedBox(height: 200),
      ),
    );

    expect(tester.takeException(), isNull);
    final Size medida = tester.getSize(find.byKey(const ValueKey<String>('video')));
    // Cabe de sobra, asi que manda el ancho y conserva su proporcion.
    expect(medida.width / medida.height, closeTo(16 / 9, 0.01));
  });

  testWidgets('un video que aun no se ha medido no rompe nada',
      (WidgetTester tester) async {
    await enPantallaDeMovil(
      tester,
      const MarcoVideo(
        proporcion: 0,
        video: ColoredBox(color: Colors.black),
        controles: SizedBox(height: 200),
      ),
    );

    expect(tester.takeException(), isNull);
  });

  // --- Que abrir la app no cueste una vida --------------------------------

  int peticionesDePortada() =>
      llamadas.where((MethodCall c) => c.method == 'caratula').length;

  testWidgets('una portada no se vuelve a pedir en cada reconstruccion',
      (WidgetTester tester) async {
    // Regresion: la peticion salia dentro de build(), asi que cada
    // reconstruccion cruzaba a Kotlin, leia MediaStore y recomprimia el JPEG.
    const Elemento pista = Elemento(
      nombre: 'Una [x].mp3',
      uri: 'content://audio/1',
      duracion: 100,
      tamano: 10,
      audio: true,
    );

    await tester.pumpWidget(const MaterialApp(home: PortadaLocal(elemento: pista)));
    await tester.pumpAndSettle();
    expect(peticionesDePortada(), 1);

    // Se reconstruye desde cero y ya no hace falta volver a pedirla.
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: PortadaLocal(elemento: pista, lado: 120)),
    ));
    await tester.pumpAndSettle();
    expect(peticionesDePortada(), 1);
  });

  testWidgets('varias filas de la misma pista comparten una sola peticion',
      (WidgetTester tester) async {
    const Elemento pista = Elemento(
      nombre: 'Una [x].mp3',
      uri: 'content://audio/1',
      duracion: 100,
      tamano: 10,
      audio: true,
    );

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Column(
          children: <Widget>[
            PortadaLocal(elemento: pista),
            PortadaLocal(elemento: pista),
            PortadaLocal(elemento: pista),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(peticionesDePortada(), 1);
  });

  testWidgets('al arrancar no se prepara la biblioteca entera',
      (WidgetTester tester) async {
    // El IndexedStack construia las tres pestanias a la vez y cada una pedia
    // las portadas de lo suyo antes de que se viera nada.
    biblioteca = _conCanciones;
    await abrirInicio(tester);

    expect(find.byType(FilaPista), findsNothing,
        reason: 'la biblioteca no se construye hasta que se abre');
    // Inicio ensenia la misma pista en «continuar» y en el carrusel, pero solo
    // se pide una portada por cancion distinta.
    expect(peticionesDePortada(), 3);

    await tester.tap(find.text('Biblioteca').last);
    await tester.pumpAndSettle();

    expect(find.byType(FilaPista), findsWidgets);
    // Y al abrirla no se vuelve a pedir ninguna: ya estaban guardadas.
    expect(peticionesDePortada(), 3);
  });

  testWidgets('borrar una descarga olvida su portada', (WidgetTester tester) async {
    const Elemento pista = Elemento(
      nombre: 'Una [x].mp3',
      uri: 'content://audio/1',
      duracion: 100,
      tamano: 10,
      audio: true,
    );
    await tester.pumpWidget(const MaterialApp(home: PortadaLocal(elemento: pista)));
    await tester.pumpAndSettle();
    expect(Nucleo.caratulaConocida(pista.uri), isTrue);

    Nucleo.olvidarCaratula(pista.uri);

    expect(Nucleo.caratulaConocida(pista.uri), isFalse);
  });

  // --- Retomar donde se dejo ----------------------------------------------

  Elemento pistaDe(String nombre, String uri) => Elemento(
        nombre: nombre,
        uri: uri,
        duracion: 100,
        tamano: 10,
        audio: true,
      );

  test('al volver a abrir se retoma la cola donde estaba', () {
    final String guardado = jsonEncode(<String, dynamic>{
      'uris': <String>['content://audio/1', 'content://audio/2', 'content://audio/3'],
      'indice': 1,
      'posicion': 42000,
    });

    final ({List<Elemento> cola, int indice, Duration posicion})? sesion =
        EstadoReproductor.sesionDesde(guardado, _biblioteca3);

    expect(sesion!.cola.map((Elemento e) => e.uri).toList(),
        <String>['content://audio/1', 'content://audio/2', 'content://audio/3']);
    expect(sesion.indice, 1, reason: 'se queda en la que sonaba, no en la primera');
    expect(sesion.posicion, const Duration(seconds: 42));
  });

  test('lo que ya se borro se cae de la cola al retomarla', () {
    // La sesion guardo tres, pero la primera ya no esta en el telefono. El
    // sitio se busca por la cancion, no por el numero que tenia.
    final String guardado = jsonEncode(<String, dynamic>{
      'uris': <String>['content://audio/9', 'content://audio/1', 'content://audio/2'],
      'indice': 2,
      'posicion': 0,
    });

    final ({List<Elemento> cola, int indice, Duration posicion})? sesion =
        EstadoReproductor.sesionDesde(guardado, _biblioteca3);

    expect(sesion!.cola.length, 2, reason: 'la que ya no existe no se encola');
    expect(sesion.cola[sesion.indice].uri, 'content://audio/2');
  });

  test('si no queda nada de la sesion, no se retoma', () {
    final String guardado = jsonEncode(<String, dynamic>{
      'uris': <String>['content://audio/borrada'],
      'indice': 0,
      'posicion': 0,
    });

    expect(EstadoReproductor.sesionDesde(guardado, _biblioteca3), isNull);
  });

  test('una sesion ilegible no impide abrir la app', () {
    for (final String basura in <String>['esto no es json', '[]', '{}', '{"uris":[]}']) {
      expect(EstadoReproductor.sesionDesde(basura, _biblioteca3), isNull,
          reason: 'con $basura');
    }
  });

  test('sin sesion guardada no se inventa ninguna cola', () async {
    biblioteca = _conCanciones;
    final EstadoReproductor estado = EstadoReproductor.instancia;

    await estado.restaurarSesion();

    expect(estado.cola, isEmpty);
    expect(estado.actual, isNull);
  });

  test('lo que pida el usuario manda sobre la sesion que se esta retomando', () async {
    // El fallo que arregla: retomar la sesion tarda -leer la biblioteca y una
    // caratula por pista- y al terminar cargaba su cola a lo bruto. Si en esa
    // espera el usuario tocaba una cancion, se la quitaba de debajo: la
    // pantalla seguia mostrando la suya, el motor se quedaba con la vieja y
    // parada, y el telefono anunciaba otra cancion distinta.
    SharedPreferences.setMockInitialValues(<String, Object>{
      EstadoReproductor.claveSesion: jsonEncode(<String, dynamic>{
        'uris': <String>['content://audio/1', 'content://audio/2'],
        'indice': 0,
        'posicion': 42000,
      }),
    });
    biblioteca = _conCanciones;
    final EstadoReproductor estado = EstadoReproductor.instancia;

    // El freno deja el retomado parado leyendo la biblioteca, que es donde
    // estaba cuando el usuario toco la pantalla.
    final Completer<void> puerta = Completer<void>();
    frenoBiblioteca = puerta.future;

    final Future<void> retomando = estado.restaurarSesion();
    await Future<void>.delayed(Duration.zero);
    await estado.cerrar();
    puerta.complete();
    await runZonedGuarded(() => retomando, (Object _, StackTrace _) {});

    expect(estado.cola, isEmpty, reason: 'lo retomado llego tarde y no manda');
    expect(estado.actual, isNull);
  });

  test('sin nadie tocando nada, la sesion si se retoma', () async {
    // La otra cara: el corte solo puede saltar cuando el usuario ha pedido
    // algo, no siempre.
    SharedPreferences.setMockInitialValues(<String, Object>{
      EstadoReproductor.claveSesion: jsonEncode(<String, dynamic>{
        'uris': <String>['content://audio/1', 'content://audio/2'],
        'indice': 1,
        'posicion': 0,
      }),
    });
    biblioteca = _conCanciones;
    final EstadoReproductor estado = EstadoReproductor.instancia;

    await estado.restaurarSesion();

    expect(estado.cola.map((Elemento e) => e.uri).toList(),
        <String>['content://audio/1', 'content://audio/2']);
    expect(estado.actual?.elemento?.uri, 'content://audio/2',
        reason: 'se queda en la que sonaba, no en la primera');
    expect(estado.motor.audioSources.length, 2, reason: 'y el motor la tiene de verdad');
  });

  test('guardar sin cola no borra la sesion que hay que retomar', () async {
    // El fallo que arregla: el motor avisa de su posicion nada mas crearse,
    // con la cola aun vacia, y guardar en ese momento borraba lo guardado. Si
    // ese aviso llegaba antes que el retomado, la sesion se perdia al abrir.
    final String guardada = jsonEncode(<String, dynamic>{
      'uris': <String>['content://audio/1'],
      'indice': 0,
      'posicion': 0,
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      EstadoReproductor.claveSesion: guardada,
    });

    await EstadoReproductor.instancia.guardarSesion();

    final SharedPreferences memoria = await SharedPreferences.getInstance();
    expect(memoria.getString(EstadoReproductor.claveSesion), guardada);
  });

  test('cerrar si olvida la sesion', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      EstadoReproductor.claveSesion: '{"uris":["content://audio/1"],"indice":0,"posicion":0}',
    });

    await EstadoReproductor.instancia.cerrar();
    // cerrar no espera a borrarla; se deja terminar.
    await Future<void>.delayed(Duration.zero);

    final SharedPreferences memoria = await SharedPreferences.getInstance();
    expect(memoria.getString(EstadoReproductor.claveSesion), isNull,
        reason: 'quien cierra el reproductor no quiere que vuelva al abrir');
  });

  test('retomar la sesion deja de pedir caratulas en cuanto el usuario toca algo', () async {
    // El fallo que arregla: al abrir, retomar pide una caratula por cancion,
    // de ocho en ocho y por el mismo canal que usa todo lo demas. Si el
    // usuario tocaba una cancion a mitad, retomar seguia hasta la ultima y lo
    // suyo esperaba detras. Con una biblioteca grande era una espera larga.
    final List<String> uris = <String>[
      for (int i = 0; i < 40; i++) 'content://audio/$i',
    ];
    biblioteca = jsonEncode(<String, dynamic>{
      'ok': true,
      'elementos': <Map<String, dynamic>>[
        for (final String u in uris)
          <String, dynamic>{
            'nombre': 'Tema ${u.split('/').last} [x].mp3',
            'tamano': 100,
            'duracion': 100,
            'audio': true,
            'uri': u,
          },
      ],
    });
    SharedPreferences.setMockInitialValues(<String, Object>{
      EstadoReproductor.claveSesion:
          jsonEncode(<String, dynamic>{'uris': uris, 'indice': 0, 'posicion': 0}),
    });
    final EstadoReproductor estado = EstadoReproductor.instancia;
    final Completer<void> puerta = Completer<void>();
    frenoCaratula = puerta.future;

    await runZonedGuarded(() async {
      final Future<void> retomando = estado.restaurarSesion();
      // Deja que llegue a la primera tanda y se quede esperandola.
      while (!llamadas.any((MethodCall l) => l.method == 'caratula')) {
        await Future<void>.delayed(Duration.zero);
      }
      await estado.cerrar();
      puerta.complete();
      await retomando;
    }, (Object _, StackTrace _) {});

    final int pedidas = llamadas.where((MethodCall l) => l.method == 'caratula').length;
    expect(pedidas, lessThanOrEqualTo(8),
        reason: 'la primera tanda ya estaba en camino; las otras cuatro sobraban');
  });

  test('una carga que el usuario deja atras no se anuncia como error', () async {
    // El fallo que arregla: poner una cola larga espera a tener una caratula
    // por cancion. Si en esa espera el usuario pedia otra cosa, el motor
    // abandonaba la primera con un «Loading interrupted» y la pantalla lo
    // sacaba como si algo se hubiera roto, justo encima de la que si iba a
    // sonar.
    biblioteca = _conCanciones;
    final EstadoReproductor estado = EstadoReproductor.instancia;
    final Completer<void> puerta = Completer<void>();
    frenoCaratula = puerta.future;

    // Todo dentro de la zona: en el escritorio no hay motor de audio y lo que
    // protesta por lo bajo no es lo que se esta mirando aqui.
    await runZonedGuarded(() async {
      final Future<void> poniendo = estado.reproducirLista(_biblioteca3, 0);
      await Future<void>.delayed(Duration.zero);
      await estado.cerrar();
      puerta.complete();
      await poniendo;
    }, (Object _, StackTrace _) {});

    expect(estado.error, isNull, reason: 'la abandono el usuario, no fallo');
  });

  group('el ecualizador de Android que a veces no esta', () {
    // En el telefono, al abrir, el plugin preguntaba por las bandas antes de
    // que Android hubiera creado el ecualizador: NullPointerException, la
    // carga fallaba, y el motor se quedaba con esa activacion rota.
    final PlatformException delEcualizador =
        PlatformException(code: 'Error', message: falloDelEcualizadorEnAndroid);
    const List<Duration> sinEsperar = <Duration>[Duration.zero, Duration.zero];

    test('se reinicia el motor y se vuelve a cargar', () async {
      int intentos = 0;
      int reinicios = 0;
      await EstadoReproductor.cargarConReintentos(
        () async {
          if (++intentos < 3) throw delEcualizador;
        },
        reiniciar: () async => reinicios++,
        sigueVigente: () => true,
        esperas: sinEsperar,
      );

      expect(intentos, 3);
      expect(reinicios, 2, reason: 'sin reiniciar, el motor repite el fallo guardado');
    });

    test('cualquier otro fallo se cuenta a la primera', () async {
      int intentos = 0;
      final Future<void> carga = EstadoReproductor.cargarConReintentos(
        () async {
          intentos++;
          throw PlatformException(code: 'Error', message: 'Source error: el archivo no existe');
        },
        reiniciar: () async => fail('no hay nada que reiniciar'),
        sigueVigente: () => true,
        esperas: sinEsperar,
      );

      await expectLater(carga, throwsA(isA<PlatformException>()));
      expect(intentos, 1, reason: 'esperar no arregla un archivo borrado');
    });

    test('si el usuario ya pidio otra cosa, no se insiste', () async {
      int intentos = 0;
      final Future<void> carga = EstadoReproductor.cargarConReintentos(
        () async {
          intentos++;
          throw delEcualizador;
        },
        reiniciar: () async {},
        sigueVigente: () => false,
        esperas: sinEsperar,
      );

      await expectLater(carga, throwsA(isA<PlatformException>()));
      expect(intentos, 1, reason: 'insistir pisaria lo que el usuario acaba de poner');
    });

    test('al abrir la app, la sesion se retoma aunque el ecualizador falle', () async {
      // El caso exacto del telefono, pasando por el just_audio de verdad.
      SharedPreferences.setMockInitialValues(<String, Object>{
        EstadoReproductor.claveSesion: jsonEncode(<String, dynamic>{
          'uris': <String>['content://audio/1', 'content://audio/2'],
          'indice': 0,
          'posicion': 0,
        }),
      });
      biblioteca = _conCanciones;
      motorFalso.fallosDelEcualizador = 1;
      final EstadoReproductor estado = EstadoReproductor.instancia;

      await estado.restaurarSesion();

      expect(estado.motor.audioSources.length, 2, reason: 'el motor tiene la cola');
      expect(estado.cola.length, 2);
      expect(motorFalso.activaciones, greaterThanOrEqualTo(2),
          reason: 'la primera activacion se tiro y se hizo otra desde cero');
    });

    test('si no se recupera, la pantalla no ensena una cancion que no va a sonar', () async {
      // Antes la pantalla se quedaba con la cancion retomada y el boton de
      // pausa, pero el motor no tenia nada: tocar play no hacia nada.
      SharedPreferences.setMockInitialValues(<String, Object>{
        EstadoReproductor.claveSesion: jsonEncode(<String, dynamic>{
          'uris': <String>['content://audio/1'],
          'indice': 0,
          'posicion': 0,
        }),
      });
      biblioteca = _conCanciones;
      motorFalso.fallosDelEcualizador = 99;
      final EstadoReproductor estado = EstadoReproductor.instancia;

      await estado.restaurarSesion();

      expect(estado.actual, isNull);
      expect(estado.cola, isEmpty);
    });
  });

  group('calidad de origen', () {
    test('la etiqueta dice lo que llego, no en que se guardo', () {
      expect(const CalidadAudio(codec: 'opus', kbps: 127, hz: 48000).etiqueta, 'Opus 127 kb/s');
      expect(const CalidadAudio(codec: 'aac', kbps: 160).etiqueta, 'AAC 160 kb/s');
      expect(const CalidadAudio(codec: 'flac').etiqueta, 'FLAC · sin perdida');
      expect(const CalidadAudio(codec: 'flac', hz: 96000).etiqueta, 'FLAC · 96 kHz');
      // Lo que salio del archivo del remix de Audius: 24 bits a 48 kHz.
      expect(const CalidadAudio(codec: 'wav', bits: 24, hz: 48000).etiqueta, 'WAV · 24 bits · 48 kHz');
      // Lo tipico de una fuente no se da por comprobado.
      expect(CalidadAudio.tipicaDeYoutube.etiqueta, 'Opus ~127 kb/s');
    });

    test('los niveles separan lo que se midio', () {
      expect(const CalidadAudio(codec: 'flac', hz: 96000).nivel, NivelCalidad.hiRes);
      expect(const CalidadAudio(codec: 'wav', bits: 24, hz: 48000).nivel, NivelCalidad.hiRes,
          reason: '24 bits ya es mas que un CD aunque la frecuencia sea la normal');
      expect(const CalidadAudio(codec: 'wav', bits: 16, hz: 44100).nivel, NivelCalidad.sinPerdida);
      expect(const CalidadAudio(codec: 'flac', hz: 44100).nivel, NivelCalidad.sinPerdida);
      expect(const CalidadAudio(codec: 'aac', kbps: 160).nivel, NivelCalidad.alta);
      expect(const CalidadAudio(codec: 'opus', kbps: 127).nivel, NivelCalidad.buena);
      expect(const CalidadAudio(codec: 'mp3', kbps: 64).nivel, NivelCalidad.basica);
    });

    test('sin perdida gana siempre; entre comprimidos, el bitrate', () {
      const CalidadAudio youtube = CalidadAudio(codec: 'opus', kbps: 127);
      const CalidadAudio soundcloud = CalidadAudio(codec: 'aac', kbps: 160);
      const CalidadAudio archive = CalidadAudio(codec: 'flac');
      expect(soundcloud.mejorQue(youtube), isTrue);
      expect(archive.mejorQue(soundcloud), isTrue);
      expect(youtube.mejorQue(soundcloud), isFalse);
    });

    test('un Opus a 127 suena mejor que un MP3 a 128, y asi se ordena', () {
      const CalidadAudio mp3 = CalidadAudio(codec: 'mp3', kbps: 128);
      expect(CalidadAudio.tipicaDeYoutube.mejorQue(mp3), isTrue);
      expect(const CalidadAudio(codec: 'mp3', kbps: 320).mejorQue(CalidadAudio.tipicaDeYoutube), isTrue);
    });

    test('el formato se ajusta al origen, y se dice', () {
      const Ajustes mp3 = Ajustes(url: '', soloAudio: true);
      const CalidadAudio entero = CalidadAudio(codec: 'wav');
      final ({Ajustes ajustes, String? motivo}) a = formatoSegunOrigen(mp3, entero);
      expect(a.ajustes.formatoAudio, 'flac');
      expect(a.motivo, contains('sin perdida'));

      final ({Ajustes ajustes, String? motivo}) b = formatoSegunOrigen(
          mp3.copiar(formatoAudio: 'wav'), CalidadAudio.tipicaDeYoutube);
      expect(b.ajustes.formatoAudio, 'mp3');

      // Sin saber el origen, o bajando video, no se toca nada.
      expect(formatoSegunOrigen(mp3, null).motivo, isNull);
      expect(formatoSegunOrigen(mp3.copiar(soloAudio: false), entero).motivo, isNull);
    });

    test('el consejo de formato no deja inflar ni desperdiciar', () {
      const CalidadAudio comprimido = CalidadAudio(codec: 'opus', kbps: 127);
      const CalidadAudio entero = CalidadAudio(codec: 'flac');
      expect(consejoDeFormato(comprimido, 'flac'), contains('sonara igual'));
      expect(consejoDeFormato(comprimido, 'mp3'), isNull);
      expect(consejoDeFormato(entero, 'mp3'), contains('FLAC'));
      expect(consejoDeFormato(entero, 'flac'), isNull);
    });
  });

  group('es la misma cancion', () {
    test('con las palabras buscadas en el titulo o el autor', () {
      expect(pareceLaMisma('armin sarabande',
          titulo: 'Sarabande (feat. Anna Timofei)', autor: 'Armin van Buuren'), isTrue);
      expect(pareceLaMisma('armin sarabande', titulo: 'Blah Blah Blah', autor: 'Armin'), isFalse);
    });

    test('un remix o un directo no es la cancion, salvo que se pida', () {
      expect(pareceLaMisma('sarabande', titulo: 'Sarabande (Deka Remix)'), isFalse);
      expect(pareceLaMisma('sarabande', titulo: 'Sarabande - Live at Tomorrowland'), isFalse);
      expect(pareceLaMisma('sarabande remix', titulo: 'Sarabande (Deka Remix)'), isTrue);
    });

    test('las tildes y las mayusculas no cuentan', () {
      expect(pareceLaMisma('corazon partio', titulo: 'CORAZÓN PARTÍO'), isTrue);
    });
  });

  group('el nombre que se ensenia', () {
    // Casos sacados de la biblioteca de verdad del telefono.
    test('las etiquetas buenas mandan sobre el nombre del archivo', () {
      final ({String artista, String tema}) n = nombreVisible('Te Olvidare [k9xV2H_Ae9g].mp3',
          titulo: 'Te Olvidare', artista: 'Antologia, Miguel Mans');
      expect(n.artista, 'Antologia, Miguel Mans', reason: 'antes salia sin artista');
      expect(n.tema, 'Te Olvidare');
    });

    test('si el titulo aun lleva «Artista - Tema», el artista de la etiqueta es el canal', () {
      final ({String artista, String tema}) n = nombreVisible(
          'Piso 21 - Puntos Suspensivos (Audio) [KgMdDclEyN].mp3',
          titulo: 'Piso 21 - Puntos Suspensivos (Audio)',
          artista: 'TheStruckFernVEVO');
      expect(n.artista, 'Piso 21');
      expect(n.tema, 'Puntos Suspensivos', reason: 'sin la coletilla');
    });

    test('una etiqueta mal codificada no gana al archivo', () {
      final ({String artista, String tema}) n = nombreVisible(
          'Wuicho Kun & Orión - En el Próximo Big Bang [x].mp3',
          titulo: 'En el Pr\u9ad5imo Big Bang',
          artista: 'Wuicho Kun & Ori\u9ac7');
      expect(n.artista, 'Wuicho Kun & Orión');
      expect(n.tema, 'En el Próximo Big Bang');
    });

    test('los nombres en coreano no se toman por mal codificados', () {
      final ({String artista, String tema}) n = nombreVisible('(로제) ROSÉ - messy [2097].mp3',
          titulo: 'messy (from the movie F1)', artista: '(로제) ROSÉ');
      expect(n.artista, '(로제) ROSÉ');
      expect(n.tema, 'messy (from the movie F1)');
    });

    test('el artista con el disco pegado y los canales «Topic» se arreglan', () {
      expect(nombreVisible('x.mp3', titulo: 'Mentira La Verdad', artista: 'AIRBAG - Cicatrices').artista,
          'AIRBAG');
      expect(nombreVisible('x.mp3', titulo: 'Bohemian Rhapsody', artista: 'Queen - Topic').artista,
          'Queen');
    });

    test('sin etiquetas se parte el nombre del archivo, como siempre', () {
      final ({String artista, String tema}) n =
          nombreVisible('Alex Warren - Eternity (Official Video) [abc].mp3');
      expect(n.artista, 'Alex Warren');
      expect(n.tema, 'Eternity');
    });
  });

  group('secciones de la biblioteca', () {
    final DateTime ahora = DateTime(2026, 9, 28, 12);
    int dia(int y, int m, int d) => DateTime(y, m, d, 10).millisecondsSinceEpoch ~/ 1000;

    test('por fecha, en tramos que se entienden', () {
      expect(seccionPorFecha(dia(2026, 9, 28), ahora), 'Hoy');
      expect(seccionPorFecha(dia(2026, 9, 27), ahora), 'Ayer');
      expect(seccionPorFecha(dia(2026, 9, 23), ahora), 'Esta semana');
      expect(seccionPorFecha(dia(2026, 9, 3), ahora), 'Este mes');
      expect(seccionPorFecha(dia(2026, 8, 14), ahora), 'Agosto 2026');
      expect(seccionPorFecha(0, ahora), 'Antes');
    });

    test('por letra, sin tildes y con lo demas bajo #', () {
      expect(seccionPorLetra('Ángeles'), 'A');
      expect(seccionPorLetra('zoe'), 'Z');
      expect(seccionPorLetra('10.000 Razones'), '#');
      expect(seccionPorLetra('사랑'), '#');
    });

    test('el resumen dice cuantas, cuanto duran y cuanto ocupan', () {
      final List<Elemento> dos = <Elemento>[
        const Elemento(nombre: 'a.mp3', uri: 'u1', duracion: 1800, tamano: 1048576, audio: true),
        const Elemento(nombre: 'b.mp3', uri: 'u2', duracion: 2400, tamano: 1048576, audio: true),
      ];
      expect(PantallaBibliotecaState.resumen(dos, audio: true), '2 canciones · 1 h 10 min · 2.0 MB');
    });
  });

  testWidgets('la biblioteca parte por fechas y reproduce todo desde arriba',
      (WidgetTester tester) async {
    final int hoy = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    biblioteca = '{"ok":true,"elementos":['
        '{"nombre":"Piso 21 - Puntos Suspensivos (Audio) [k].mp3","titulo":"Piso 21 - Puntos Suspensivos (Audio)",'
        '"artista":"TheStruckFernVEVO","fecha":$hoy,"tamano":100,"duracion":200,"audio":true,"uri":"content://audio/1"},'
        '{"nombre":"Vieja [v].mp3","titulo":"Vieja","artista":"Alguien","fecha":0,'
        '"tamano":100,"duracion":100,"audio":true,"uri":"content://audio/2"}]}';
    comoElTelefono(tester);
    await abrirBiblioteca(tester);

    // Lo que se ve sale de las etiquetas, no del nombre del archivo.
    expect(find.text('Puntos Suspensivos'), findsOneWidget);
    expect(find.textContaining('Piso 21  ·'), findsOneWidget);
    expect(find.text('HOY'), findsOneWidget);
    expect(find.text('ANTES'), findsOneWidget);
    expect(find.textContaining('2 canciones'), findsOneWidget);

    await tester.tap(find.text('Reproducir'));
    await tester.pumpAndSettle();
    expect(EstadoReproductor.instancia.cola.length, 2);
    expect(EstadoReproductor.instancia.actual?.elemento?.uri, 'content://audio/1',
        reason: 'reproducir empieza por la primera que se ve');
  });

  testWidgets('en orden alfabetico sale el indice y lleva a su letra', (WidgetTester tester) async {
    final StringBuffer json = StringBuffer('{"ok":true,"elementos":[');
    final List<String> temas = <String>[
      for (final String l in <String>['A', 'B', 'C', 'M', 'Z'])
        for (int i = 0; i < 6; i++) '$l tema $i',
    ];
    for (int i = 0; i < temas.length; i++) {
      json.write('${i == 0 ? '' : ','}{"nombre":"${temas[i]}.mp3","titulo":"${temas[i]}",'
          '"artista":"X","fecha":0,"tamano":1,"duracion":1,"audio":true,"uri":"content://audio/$i"}');
    }
    json.write(']}');
    biblioteca = json.toString();
    comoElTelefono(tester);
    await abrirBiblioteca(tester);

    await tester.tap(find.byTooltip('Ordenar'));
    await tester.pumpAndSettle();
    // Se toca el elemento del menu y no su texto, que va desplazado en la fila.
    await tester.tap(find.widgetWithText(CheckedPopupMenuItem<Orden>, 'A - Z'));
    await tester.pumpAndSettle();

    final Finder indice = find.byWidgetPredicate(
        (Widget w) => w is Semantics && w.properties.label == 'Indice alfabetico');
    expect(indice, findsOneWidget);
    expect(find.text('Z tema 0'), findsNothing, reason: 'la Z queda muy abajo');

    await tester.tap(find.descendant(of: indice, matching: find.text('Z')));
    await tester.pumpAndSettle();
    expect(find.text('Z tema 0'), findsOneWidget, reason: 'el indice lleva a la Z');
  });

  testWidgets('tocar una cancion de la biblioteca deja las demas en cola',
      (WidgetTester tester) async {
    // El fallo: el reproductor, al abrirse, volvia a poner la cancion sola si
    // el motor avisaba antes de su posicion en la cola nueva. Sin cola no habia
    // siguiente, y la cola vieja ensenaba la portada de otra cancion.
    biblioteca = _conCanciones;
    comoElTelefono(tester);
    await abrirBiblioteca(tester);
    final EstadoReproductor estado = EstadoReproductor.instancia;

    await tester.tap(find.text('Bailando'));
    await tester.pumpAndSettle();
    // La carga del motor pasa por canales que necesitan tiempo real, no el
    // reloj de mentira de la prueba.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await tester.pumpAndSettle();
    expect(estado.actual?.elemento?.uri, 'content://audio/2');
    expect(estado.motor.audioSources.length, 3, reason: 'la cola entera, no solo esa');
    expect(estado.haySiguiente, isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Amame'));
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 800)));
    await tester.pumpAndSettle();
    expect(estado.actual?.elemento?.uri, 'content://audio/3',
        reason: 'la que se toco, no la de antes');
    expect(estado.motor.audioSources.length, 3);
    expect(estado.cola.length, estado.motor.audioSources.length,
        reason: 'la cola de la app y la del motor, siempre la misma');
  });

  test('poner una pista sola deja una sola en la cola', () async {
    // Sin esperar a play(): en este motor no acaba hasta que la musica se para.
    final EstadoReproductor estado = EstadoReproductor.instancia;
    Future<void> hastaQue(bool Function() listo) async {
      for (int i = 0; i < 100 && !listo(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    unawaited(estado.reproducirLista(_biblioteca3, 0));
    await hastaQue(() => estado.motor.audioSources.length == 3);
    expect(estado.cola.length, 3);

    unawaited(estado.reproducirElemento(_biblioteca3[2]));
    await hastaQue(() => estado.motor.audioSources.length == 1);

    expect(estado.cola.length, 1, reason: 'si no, el indice 0 del motor apuntaria a otra');
    expect(estado.motor.audioSources.length, 1);
    await estado.cerrar();
  });

  group('que es lo escrito', () {
    test('nada, texto o enlace', () {
      expect(Entrada.de('   ').tipo, TipoEntrada.vacia);
      expect(Entrada.de(' bad bunny ').tipo, TipoEntrada.busqueda);
      expect(Entrada.de(' bad bunny ').texto, 'bad bunny');
      expect(Entrada.de('https://www.youtube.com/watch?v=abc').tipo, TipoEntrada.enlace);
    });

    test('un enlace sin https tambien vale, si lleva ruta', () {
      final Entrada e = Entrada.de('youtu.be/abc');
      expect(e.tipo, TipoEntrada.enlace);
      expect(e.url, 'https://youtu.be/abc');
      // Sin ruta es mas probable que sea un titulo con un punto.
      expect(Entrada.de('Mr.Brightside').tipo, TipoEntrada.busqueda);
    });

    test('del texto que acompana a un enlace se saca el enlace', () {
      final Entrada e = Entrada.de('Mira este video: https://vm.tiktok.com/ZM123/.');
      expect(e.tipo, TipoEntrada.enlace);
      expect(e.url, 'https://vm.tiktok.com/ZM123/');
      expect(e.sitio, 'TikTok');
    });

    test('lista, video dentro de lista y mezclas', () {
      expect(Entrada.de('https://www.youtube.com/playlist?list=PL1').tipo, TipoEntrada.lista);
      final Entrada video = Entrada.de('https://www.youtube.com/watch?v=abc&list=PL1');
      expect(video.tipo, TipoEntrada.enlace);
      expect(video.listaAparte, 'https://www.youtube.com/playlist?list=PL1');
      // Las mezclas de YouTube no acaban nunca y no son la lista de nadie.
      expect(Entrada.de('https://youtu.be/abc?list=RDabc').listaAparte, isEmpty);
    });

    test('lo que parece un enlace pero no se puede abrir', () {
      expect(Entrada.de('https//youtube.com/watch?v=abc').tipo, TipoEntrada.enlaceRoto);
      expect(Entrada.de('https://youtube').tipo, TipoEntrada.enlaceRoto);
    });

    test('el sitio se dice como lo diria una persona', () {
      expect(Entrada.sitioDe('music.youtube.com'), 'YouTube Music');
      expect(Entrada.sitioDe('m.youtube.com'), 'YouTube');
      expect(Entrada.sitioDe('vm.tiktok.com'), 'TikTok');
      expect(Entrada.sitioDe('www.ejemplo.pe'), 'ejemplo.pe');
    });
  });

  test('el resumen dice que va a salir sin abrir las opciones', () {
    const Ajustes base = Ajustes(url: '');
    expect(resumenDescarga(base.copiar(soloAudio: true)), 'MP3 · 192 kb/s');
    expect(resumenDescarga(base.copiar(soloAudio: true, formatoAudio: 'flac')),
        'FLAC · sin perdida');
    expect(resumenDescarga(base.copiar(calidad: 0)), 'MP4 · la mejor calidad');
    expect(resumenDescarga(base.copiar(calidad: 1080, fragmento: '1:00-2:00')),
        'MP4 · hasta 1080p · solo un trozo');
  });

  test('la velocidad pasa por todos sus valores y vuelve al principio', () {
    final List<double> vistas = <double>[];
    double actual = EstadoReproductor.velocidades.first;

    for (int i = 0; i < EstadoReproductor.velocidades.length; i++) {
      actual = EstadoReproductor.siguienteVelocidad(actual);
      vistas.add(actual);
    }

    expect(vistas.toSet(), EstadoReproductor.velocidades.toSet());
    expect(actual, EstadoReproductor.velocidades.first,
        reason: 'una vuelta entera lo deja como estaba');
  });

  test('una velocidad rara vuelve a la primera', () {
    expect(EstadoReproductor.siguienteVelocidad(3.7), EstadoReproductor.velocidades.first);
  });

  // --- Por artista ---------------------------------------------------------

  test('las canciones se agrupan por quien las canta', () {
    final List<Elemento> pistas = <Elemento>[
      pistaDe('Soda Stereo - De Musica Ligera [x1].mp3', 'content://audio/1'),
      pistaDe('Grupo 5 - Motor y Motivo [x2].mp3', 'content://audio/2'),
      pistaDe('Soda Stereo - Persiana Americana [x3].mp3', 'content://audio/3'),
      pistaDe('Un tema sin guion [x4].mp3', 'content://audio/4'),
    ];

    final Map<String, List<Elemento>> grupos = Artistas.agrupar(pistas);

    // Alfabetico, y el cajon de sastre al final.
    expect(grupos.keys.toList(), <String>['Grupo 5', 'Soda Stereo', Artistas.sinNombre]);
    expect(grupos['Soda Stereo']!.length, 2);
    expect(grupos[Artistas.sinNombre]!.single.uri, 'content://audio/4');
  });

  test('el artista se ordena sin que las tildes lo manden al final', () {
    final List<Elemento> pistas = <Elemento>[
      pistaDe('Zoe - Labios Rotos [x1].mp3', 'content://audio/1'),
      pistaDe('Ángeles Azules - Nunca Es Suficiente [x2].mp3', 'content://audio/2'),
    ];

    expect(Artistas.agrupar(pistas).keys.first, 'Ángeles Azules');
  });

  testWidgets('la biblioteca tiene una pestania de artistas',
      (WidgetTester tester) async {
    biblioteca = _conCanciones;
    await abrirBiblioteca(tester);

    expect(find.widgetWithText(ChoiceChip, 'Artistas'), findsOneWidget);
  });

  // --- Editar etiquetas ----------------------------------------------------

  /// Abre el dialogo de etiquetas sobre una pista suelta.
  Future<void> abrirEtiquetas(WidgetTester tester, Elemento pista) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => editarEtiquetas(context, pista),
            child: const Text('abrir'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('el dialogo llega con el artista y el titulo ya puestos',
      (WidgetTester tester) async {
    await abrirEtiquetas(
      tester,
      pistaDe('Soda Stereo - De Musica Ligera [T_Fk].mp3', 'content://audio/1'),
    );

    expect(find.widgetWithText(TextField, 'Soda Stereo'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'De Musica Ligera'), findsOneWidget);
  });

  testWidgets('un nombre sin guion deja el artista vacio',
      (WidgetTester tester) async {
    await abrirEtiquetas(
      tester,
      pistaDe('Un tema suelto [x].mp3', 'content://audio/1'),
    );

    expect(find.widgetWithText(TextField, 'Un tema suelto'), findsOneWidget);
    // El campo del artista existe, pero vacio: no se inventa nada.
    expect(find.widgetWithText(TextField, 'Artista'), findsOneWidget);
  });

  testWidgets('sin titulo no se deja guardar', (WidgetTester tester) async {
    await abrirEtiquetas(
      tester,
      pistaDe('Artista - Tema [x].mp3', 'content://audio/1'),
    );

    final Finder guardar = find.widgetWithText(FilledButton, 'Guardar');
    expect(tester.widget<FilledButton>(guardar).onPressed, isNotNull);

    await tester.enterText(find.widgetWithText(TextField, 'Tema'), '   ');
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(guardar).onPressed, isNull);
  });

  testWidgets('guardar manda al nucleo lo escrito', (WidgetTester tester) async {
    await abrirEtiquetas(
      tester,
      pistaDe('Mal escrito [x].mp3', 'content://audio/1'),
    );

    await tester.enterText(find.widgetWithText(TextField, 'Artista'), 'Soda Stereo');
    await tester.enterText(find.widgetWithText(TextField, 'Mal escrito'), 'De Musica Ligera');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();

    final MethodCall envio =
        llamadas.lastWhere((MethodCall c) => c.method == 'etiquetar');
    expect(envio.arguments['uri'], 'content://audio/1');
    expect(envio.arguments['artista'], 'Soda Stereo');
    expect(envio.arguments['titulo'], 'De Musica Ligera');
  });

  testWidgets('editar etiquetas se ofrece en las canciones y no en los videos',
      (WidgetTester tester) async {
    biblioteca = '{"ok":true,"elementos":['
        '{"nombre":"Una [c1].mp3","tamano":100,"duracion":100,"audio":true,"uri":"content://audio/1"},'
        '{"nombre":"Un video [c2].mp4","tamano":100,"duracion":100,"audio":false,"uri":"content://video/1"}]}';
    await abrirBiblioteca(tester);

    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Editar etiquetas'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Videos'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Videos'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
    await tester.pumpAndSettle();
    expect(find.text('Editar etiquetas'), findsNothing);
  });

  // --- El detalle del motor -----------------------------------------------

  testWidgets('sin detalle no se ofrece nada', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: DetalleMotor(lineas: <String>[])),
    ));

    expect(find.text('Ver detalle tecnico'), findsNothing);
  });

  testWidgets('el detalle se ofrece plegado y se abre al tocarlo',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DetalleMotor(lineas: <String>['primera linea', 'segunda linea']),
      ),
    ));

    expect(find.text('Ver detalle tecnico'), findsOneWidget);
    expect(find.textContaining('segunda linea'), findsNothing);

    await tester.tap(find.text('Ver detalle tecnico'));
    await tester.pumpAndSettle();

    expect(find.textContaining('segunda linea'), findsOneWidget);
  });

  testWidgets('de un registro largo se ensenia solo el final',
      (WidgetTester tester) async {
    // Las primeras lineas son el arranque del motor; lo que explica el fallo
    // esta siempre al final.
    final List<String> muchas = <String>[
      for (int i = 0; i < 200; i++) 'linea $i',
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DetalleMotor(lineas: muchas)),
    ));
    await tester.tap(find.text('Ver detalle tecnico'));
    await tester.pumpAndSettle();

    expect(find.textContaining('linea 199'), findsOneWidget);
    expect(find.textContaining('linea 0\n'), findsNothing);
  });

  test('el volcado de parametros no cuenta como detalle', () {
    // Es una sola linea de miles de caracteres: si se deja, llena la pantalla
    // y empuja fuera de la vista el error, que es lo unico que se venia a leer.
    final List<String> crudo = <String>[
      '[debug] Encodings: locale utf-8, fs utf-8',
      '[debug] yt-dlp version stable@2026.08.19',
      "[debug] params: {'paths': {'home': '/algo'}, 'format': 'bv*'}",
      '[TikTok] 768: Downloading webpage',
      'ERROR: [TikTok] 768: Unexpected response from webpage request',
    ];

    final List<String> limpio = DetalleMotor.limpiar(crudo);

    expect(limpio, <String>[
      '[debug] yt-dlp version stable@2026.08.19',
      '[TikTok] 768: Downloading webpage',
      'ERROR: [TikTok] 768: Unexpected response from webpage request',
    ]);
  });

  testWidgets('tras filtrar el ruido, el error queda a la vista',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: DetalleMotor(lineas: <String>[
          "[debug] params: {'mucho': 'texto'}",
          'ERROR: lo que de verdad paso',
        ]),
      ),
    ));
    await tester.tap(find.text('Ver detalle tecnico'));
    await tester.pumpAndSettle();

    expect(find.textContaining('lo que de verdad paso'), findsOneWidget);
    expect(find.textContaining('mucho'), findsNothing);
  });

  // --- De donde se busca ---------------------------------------------------

  testWidgets('el buscador ofrece las tres fuentes', (WidgetTester tester) async {
    await abrir(tester);

    expect(find.widgetWithText(ChoiceChip, 'YouTube'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'SoundCloud'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Archive'), findsOneWidget);
  });

  testWidgets('la fuente elegida viaja al nucleo', (WidgetTester tester) async {
    await abrir(tester);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'SoundCloud'));

    await tester.tap(find.widgetWithText(ChoiceChip, 'SoundCloud'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'algo');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    final MethodCall envio = llamadas.lastWhere((MethodCall c) => c.method == 'buscar');
    expect(envio.arguments['fuente'], 'soundcloud');
  });

  testWidgets('por defecto se busca en todas a la vez', (WidgetTester tester) async {
    await abrir(tester);
    await tester.enterText(find.byType(TextField).first, 'algo');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    final Set<Object?> donde = llamadas
        .where((MethodCall c) => c.method == 'buscar')
        .map((MethodCall c) => (c.arguments as Map<dynamic, dynamic>)['fuente'])
        .toSet();
    expect(donde, <String>{'youtube', 'soundcloud', 'audius', 'bandcamp', 'archive'});
  });

  /// La altura en pantalla de la tarjeta de una fuente, para ver el orden.
  double alturaDe(WidgetTester tester, String fuente) => tester
      .getTopLeft(find.descendant(of: find.byType(ListView), matching: find.text(fuente)).first)
      .dy;

  testWidgets('en todas sale una sola lista, de la mejor calidad a la peor',
      (WidgetTester tester) async {
    // Lo medido de verdad: Audius da el original en WAV cuando el artista lo
    // deja; SoundCloud sin DRM, AAC 160; YouTube, Opus ~127.
    respuestas['audius'] = '{"ok":true,"resultados":[{"titulo":"Cancion uno","autor":"Grupo",'
        '"duracion":180,"url":"https://audius.co/grupo/cancion-uno","miniatura":"",'
        '"calidad":{"codec":"wav","kbps":null,"hz":null,"sinPerdida":true}}]}';
    respuestas['soundcloud'] = '{"ok":true,"resultados":['
        '{"titulo":"Cancion uno","autor":"Grupo","duracion":180,'
        '"url":"https://soundcloud.com/grupo/cancion-uno","miniatura":""}]}';
    calidades['https://soundcloud.com/grupo/cancion-uno'] =
        '{"ok":true,"codec":"aac","kbps":160.0,"hz":44100,"sinPerdida":false}';
    comoElTelefono(tester);
    await abrir(tester);

    await tester.enterText(find.byType(TextField), 'cancion uno');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    // Sin grupos por fuente: cada tarjeta dice de donde es.
    expect(find.text('YOUTUBE'), findsNothing);
    expect(find.text('MEJOR CALIDAD'), findsOneWidget);
    expect(find.text('SIN PERDIDA · WAV'), findsOneWidget);
    expect(alturaDe(tester, 'Audius'), lessThan(alturaDe(tester, 'SoundCloud')));
    expect(alturaDe(tester, 'SoundCloud'), lessThan(alturaDe(tester, 'YouTube')));
  });

  testWidgets('lo que tiene DRM se dice antes de intentarlo y se va al final',
      (WidgetTester tester) async {
    respuestas['soundcloud'] = '{"ok":true,"resultados":['
        '{"titulo":"Cancion uno","autor":"Sello","duracion":180,'
        '"url":"https://soundcloud.com/sello/cancion-uno","miniatura":""}]}';
    calidades['https://soundcloud.com/sello/cancion-uno'] =
        '{"ok":false,"error":"Esa pista esta protegida por su sello y no se puede descargar."}';
    comoElTelefono(tester);
    await abrir(tester);

    await tester.enterText(find.byType(TextField), 'cancion uno');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    await tester.dragUntilVisible(
      find.text('Protegida: no se puede bajar'),
      find.byType(ListView),
      const Offset(0, -200),
    );
    expect(find.text('Protegida: no se puede bajar'), findsOneWidget);
    // La mejor es la que si se puede bajar, aunque sea de menos bitrate.
    expect(alturaDe(tester, 'YouTube'), lessThan(alturaDe(tester, 'SoundCloud')));
  });

  testWidgets('un origen sin perdida elige FLAC solo al descargar', (WidgetTester tester) async {
    respuestas['audius'] = '{"ok":true,"resultados":[{"titulo":"Cancion uno","autor":"Grupo",'
        '"duracion":180,"url":"https://audius.co/grupo/cancion-uno","miniatura":"",'
        '"calidad":{"codec":"wav","sinPerdida":true}}]}';
    respuestas.remove('youtube');
    comoElTelefono(tester);
    await abrir(tester);
    await tester.enterText(find.byType(TextField), 'cancion uno');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancion uno'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Elegido FLAC'), findsOneWidget);
    expect(find.text('FLAC · sin perdida'), findsOneWidget, reason: 'el resumen de Musica');
  });

  testWidgets('una fuente que no responde no tapa lo que dieron las demas',
      (WidgetTester tester) async {
    respuestas['soundcloud'] = '{"ok":false,"error":"sin conexion"}';
    await abrir(tester);

    await tester.enterText(find.byType(TextField), 'cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Cancion uno'), findsOneWidget);
    expect(find.text('SoundCloud no respondio: sin conexion'), findsOneWidget);
  });

  testWidgets('repetir una busqueda no vuelve a preguntar', (WidgetTester tester) async {
    await abrir(tester);
    await tester.enterText(find.byType(TextField), 'otra cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    final int antes = llamadas.where((MethodCall c) => c.method == 'buscar').length;

    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(llamadas.where((MethodCall c) => c.method == 'buscar').length, antes);
  });

  testWidgets('la hoja dice con que calidad llega y aconseja el formato',
      (WidgetTester tester) async {
    comoElTelefono(tester);
    await abrir(tester);
    await tester.enterText(find.byType(TextField), 'cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancion uno'));
    await tester.pumpAndSettle();

    expect(find.text('Llega en  '), findsOneWidget);

    // Pedir FLAC de algo que llego comprimido no lo mejora: se avisa.
    await tester.tap(find.text('Mas opciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FLAC'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sonara igual'), findsOneWidget);

    await tester.tap(find.text('Usar MP3'));
    await tester.pumpAndSettle();
    expect(find.textContaining('sonara igual'), findsNothing);
  });

  testWidgets('cambiar de fuente limpia lo encontrado en la anterior',
      (WidgetTester tester) async {
    await abrir(tester);
    await tester.enterText(find.byType(TextField).first, 'cancion');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(find.text('Cancion uno'), findsOneWidget);

    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Archive'));

    await tester.tap(find.widgetWithText(ChoiceChip, 'Archive'));
    await tester.pumpAndSettle();

    expect(find.text('Cancion uno'), findsNothing);
  });

  test('solo el Archive devuelve grabaciones enteras', () {
    // Sus resultados son conciertos: se abren como lista, no se bajan de una
    // pieza. Espeja FUENTES_DE_LISTAS del nucleo.
    expect(Fuente.archive.daListas, isTrue);
    expect(Fuente.youtube.daListas, isFalse);
    expect(Fuente.soundcloud.daListas, isFalse);
  });

  testWidgets('tocar un concierto del Archive trae sus pistas',
      (WidgetTester tester) async {
    respuestas['archive'] = _busqueda;
    await abrir(tester);
    await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Archive'));
    await tester.tap(find.widgetWithText(ChoiceChip, 'Archive'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'grateful dead');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancion uno'));
    await tester.pumpAndSettle();

    // No se baja de una pieza: se piden sus pistas.
    expect(llamadas.any((MethodCall c) => c.method == 'importarLista'), isTrue);
    expect(find.text('¿Como lo quieres?'), findsNothing);
  });

  // --- El color sale de la portada ----------------------------------------

  testWidgets('sin portada se usa la paleta del tema', (WidgetTester tester) async {
    // El canal de prueba responde con una portada vacia.
    final ColorScheme colores = await Paleta.de('content://audio/1');

    expect(colores, Paleta.neutra);
  });

  testWidgets('la paleta no se recalcula en cada reconstruccion',
      (WidgetTester tester) async {
    // Sacar los colores de una imagen cuesta, y la pantalla se redibuja cada
    // segundo mientras suena.
    await Paleta.de('content://audio/1');
    final int tras = llamadas.where((MethodCall c) => c.method == 'caratula').length;

    await Paleta.de('content://audio/1');
    await Paleta.de('content://audio/1');

    expect(llamadas.where((MethodCall c) => c.method == 'caratula').length, tras);
    expect(Paleta.guardada('content://audio/1'), isNotNull);
  });

  testWidgets('olvidar una pista tira su paleta', (WidgetTester tester) async {
    await Paleta.de('content://audio/1');
    expect(Paleta.guardada('content://audio/1'), isNotNull);

    Paleta.olvidar('content://audio/1');

    expect(Paleta.guardada('content://audio/1'), isNull);
  });

  testWidgets('la paleta viste lo que tiene debajo', (WidgetTester tester) async {
    late ColorScheme visto;
    await tester.pumpWidget(MaterialApp(
      home: ConPaletaDe(
        uri: 'content://audio/1',
        hijo: Builder(
          builder: (BuildContext context) {
            visto = Theme.of(context).colorScheme;
            return const SizedBox.shrink();
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(visto, Paleta.neutra);
  });
}

/// Las mismas tres canciones de _conCanciones, ya como objetos.
final List<Elemento> _biblioteca3 = <Elemento>[
  for (final (String nombre, String uri) in <(String, String)>[
    ('Corazon Partio [c1].mp3', 'content://audio/1'),
    ('Bailando [c2].mp3', 'content://audio/2'),
    ('Amame [c3].mp3', 'content://audio/3'),
  ])
    Elemento(nombre: nombre, uri: uri, duracion: 100, tamano: 100, audio: true),
];

/// Tres canciones con tildes y duraciones distintas, para filtrar y ordenar.
const String _conCanciones = '{"ok":true,"elementos":['
    '{"nombre":"Corazon Partio [c1].mp3","tamano":100,"duracion":300,"audio":true,"uri":"content://audio/1"},'
    '{"nombre":"Bailando [c2].mp3","tamano":100,"duracion":100,"audio":true,"uri":"content://audio/2"},'
    '{"nombre":"Amame [c3].mp3","tamano":100,"duracion":200,"audio":true,"uri":"content://audio/3"}]}';