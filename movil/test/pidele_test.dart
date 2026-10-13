import 'dart:math';

import 'package:descargador_movil/calidad.dart';
import 'package:descargador_movil/nucleo.dart';
import 'package:descargador_movil/pidele.dart';
import 'package:descargador_movil/ritmos.dart';
import 'package:flutter_test/flutter_test.dart';

Elemento _cancion(String artista, String tema, {double duracion = 200, int fecha = 0}) => Elemento(
      nombre: '$artista - $tema.mp3',
      uri: 'content://audio/${artista.toLowerCase()}-${tema.toLowerCase()}',
      duracion: duracion,
      tamano: 1,
      audio: true,
      fecha: fecha,
    );

void main() {
  final Set<String> artistas = <String>{'bad bunny', 'karol g', 'hector lavoe', 'grupo 5'};
  Peticion q(String frase) => interpretar(frase, artistas: artistas);

  group('pidele a tumbao: entender', () {
    test('algo tranquilo para dormir', () {
      final Peticion p = q('algo tranquilo para dormir');
      expect(p.energiaMax, .25);
      expect(p.orden, OrdenPeticion.bajar);
      expect(p.bpmMax, 100);
      expect(p.minutos, 45);
    });

    test('reggaeton pa entrenar', () {
      final Peticion p = q('Reggaetón pa entrenar');
      expect(p.generos, contains('reggaeton'));
      expect(p.energiaMin, .65);
      expect(p.orden, OrdenPeticion.subir);
    });

    test('lo que mas escucho de un artista', () {
      final Peticion p = q('lo que más escucho de Bad Bunny');
      expect(p.artistas, <String>{'bad bunny'});
      expect(p.orden, OrdenPeticion.masEscuchadas);
      expect(p.minEscuchas, 2);
      expect(p.entendido, contains('De Bad Bunny'));
    });

    test('largas, sin perdida y la negacion', () {
      expect(q('canciones largas').duracionMin, 360);
      final Peticion sinPerdida = q('sin pérdida');
      expect(sinPerdida.calidad, CalidadPedida.sinPerdida);
      expect(sinPerdida.sinArtistas, isEmpty);
      expect(sinPerdida.sinGeneros, isEmpty);
      final Peticion fiesta = q('fiesta sin bad bunny ni reggaeton');
      expect(fiesta.sinArtistas, <String>{'bad bunny'});
      expect(fiesta.sinGeneros, <String>{'reggaeton'});
      expect(fiesta.generos, isEmpty);
      expect(fiesta.orden, OrdenPeticion.arco);
      final Peticion trap = q('nada de trap, algo para estudiar');
      expect(trap.sinGeneros, <String>{'trap'});
      expect(trap.energiaMax, .5);
    });

    test('numeros: horas, canciones, bpm y decadas', () {
      final Peticion hora = q('una hora de cumbia para el tono');
      expect(hora.minutos, 60);
      expect(hora.generos, contains('cumbia'));
      expect(hora.energiaMin, .6);
      final Peticion bpm = q('20 canciones a 128 bpm');
      expect(bpm.limite, 20);
      expect(bpm.bpmMin, closeTo(124.16, .01));
      expect(bpm.bpmMax, closeTo(131.84, .01));
      final Peticion ochenta = q('baladas de los 80');
      expect((ochenta.anioMin, ochenta.anioMax), (1980, 1989));
      expect(ochenta.generos, contains('balada'));
      expect(q('salsa de hector lavoe').artistas, contains('hector lavoe'));
    });

    test('perdona una errata en un artista largo', () {
      expect(q('algo de hector labo').artistas, isEmpty, reason: 'dos letras ya es otro');
      expect(q('algo de hektor lavoe').artistas, <String>{'hector lavoe'});
    });

    test('lo quitado se lee pero no se aplica', () {
      final Peticion p = interpretar('salsa para entrenar', artistas: artistas, quitar: <String>{'Para entrenar'});
      expect(p.generos, contains('salsa'));
      expect(p.energiaMin, isNull);
      expect(p.entendido, contains('Para entrenar'));
    });

    test('lo que no se entiende no inventa nada', () {
      final Peticion p = q('xyz qwerty');
      expect(p.vacia, isTrue);
      expect(normalizarFrase("Pa' bailar"), ' para bailar ');
      expect(normalizarFrase('pal tono'), ' para el tono ');
    });
  });

  group('pidele a tumbao: aplicar', () {
    final List<Elemento> biblioteca = <Elemento>[
      _cancion('Bad Bunny', 'Titi', fecha: 1000),
      _cancion('Karol G', 'Provenza', fecha: 2000),
      _cancion('Hector Lavoe', 'El Cantante', duracion: 420),
      _cancion('Grupo 5', 'Motor y Motivo'),
      _cancion('Lofi Chico', 'Lluvia', duracion: 150),
      _cancion('Nadie', 'Algo Raro'),
    ];
    String uri(String artista) => biblioteca.firstWhere((Elemento e) => e.artista == artista).uri;
    final Map<String, Rasgos> rasgos = <String, Rasgos>{
      uri('Bad Bunny'): const Rasgos(bpm: 95, confianza: .5, energia: .8, genero: 'Music'),
      uri('Karol G'): const Rasgos(bpm: 92, confianza: .5, energia: .7),
      uri('Hector Lavoe'): const Rasgos(bpm: 180, confianza: .5, energia: .6, genero: 'Salsa', anio: 1978),
      uri('Grupo 5'): const Rasgos(bpm: 100, confianza: .5, energia: .65),
      uri('Lofi Chico'): const Rasgos(bpm: 75, confianza: .5, energia: .1, genero: 'Lo-Fi'),
    };
    final DatosBiblioteca datos = DatosBiblioteca(
      canciones: biblioteca,
      rasgos: rasgos,
      escuchas: <String, ({int veces, int ultima})>{
        uri('Bad Bunny'): (veces: 9, ultima: DateTime(2026, 10).millisecondsSinceEpoch),
        uri('Karol G'): (veces: 4, ultima: DateTime(2026, 1).millisecondsSinceEpoch),
      },
      favoritas: <String>{uri('Lofi Chico')},
      calidades: <String, CalidadAudio>{
        uri('Hector Lavoe'): const CalidadAudio(codec: 'flac', hz: 44100, bits: 16),
      },
    );
    List<String> artistasDe(String frase, {DateTime? ahora}) => aplicarPeticion(
          interpretar(frase, artistas: datos.artistas),
          datos,
          ahora: ahora ?? DateTime(2026, 10, 13),
          azar: Random(1),
        ).pistas.map((Elemento e) => e.artista).toList();

    test('genero por etiqueta, por artista conocido, y Music no cuenta', () {
      expect(artistasDe('salsa'), <String>['Hector Lavoe'], reason: 'por su etiqueta');
      expect(artistasDe('reggaeton').toSet(), <String>{'Bad Bunny', 'Karol G'},
          reason: 'por artistas conocidos; la etiqueta Music no dice nada');
      expect(artistasDe('cumbia'), contains('Grupo 5'));
      expect(artistasDe('lofi'), <String>['Lofi Chico']);
    });

    test('lo mas escuchado, favoritas, sin perdida y olvidadas', () {
      expect(artistasDe('lo que mas escucho'), <String>['Bad Bunny', 'Karol G']);
      expect(artistasDe('mis favoritas'), <String>['Lofi Chico']);
      expect(artistasDe('sin perdida'), <String>['Hector Lavoe']);
      expect(artistasDe('olvidadas'), <String>['Karol G'], reason: 'no suena desde enero');
      expect(artistasDe('sin escuchar').toSet(),
          <String>{'Hector Lavoe', 'Grupo 5', 'Lofi Chico', 'Nadie'});
    });

    test('energia por percentil y lo sin analizar se cuenta', () {
      final Respuesta r = aplicarPeticion(interpretar('algo animado'), datos);
      // Percentiles: Lofi 0, Lavoe .25, Grupo 5 .5, Karol .75, Bad Bunny 1.
      expect(r.pistas.map((Elemento e) => e.artista).toSet(), <String>{'Bad Bunny', 'Karol G'});
      expect(r.sinAnalizar, 1, reason: 'Nadie no esta analizada');
      expect(artistasDe('fiesta sin bad bunny ni reggaeton'), isNot(contains('Bad Bunny')));
      expect(artistasDe('fiesta sin bad bunny ni reggaeton'), isNot(contains('Karol G')));
    });

    test('si no sale nada se relaja y lo dice', () {
      final Respuesta r = aplicarPeticion(interpretar('salsa a tope'), datos);
      expect(r.pistas.map((Elemento e) => e.artista), <String>['Hector Lavoe']);
      expect(r.avisos, contains('Energia mas abierta'));
    });

    test('el genero por tempo solo cuando no hay ninguna de verdad', () {
      final Respuesta house = aplicarPeticion(interpretar('house'), datos);
      expect(house.pistas, isEmpty, reason: 'nada esta entre 118 y 130 BPM ni dice house');
      final Respuesta lofi = aplicarPeticion(interpretar('lofi'), datos);
      expect(lofi.avisos, isEmpty, reason: 'hay una que lo dice en su etiqueta');
      final Respuesta trap = aplicarPeticion(
        interpretar('trap'),
        DatosBiblioteca(
          canciones: biblioteca,
          rasgos: <String, Rasgos>{uri('Nadie'): const Rasgos(bpm: 140, confianza: .5)},
        ),
      );
      expect(trap.pistas.map((Elemento e) => e.artista), <String>['Nadie']);
      expect(trap.avisos, contains('Elegidas por ritmo parecido'));
    });

    test('pedir solo un ritmo que no hay no devuelve la biblioteca entera', () {
      final Respuesta r = aplicarPeticion(interpretar('algo tranquilo'), DatosBiblioteca(canciones: biblioteca));
      expect(r.pistas, isEmpty);
      expect(r.sinAnalizar, biblioteca.length);
    });

    test('duracion, decada y recien bajadas', () {
      expect(artistasDe('canciones largas'), <String>['Hector Lavoe']);
      expect(artistasDe('salsa de los 70'), <String>['Hector Lavoe']);
      final DateTime ahora = DateTime.fromMillisecondsSinceEpoch(3000 * 1000);
      expect(artistasDe('recien bajadas', ahora: ahora), <String>['Karol G', 'Bad Bunny']);
    });

    test('una hora junta canciones hasta llegar y las ordena como DJ', () {
      final Respuesta r = aplicarPeticion(interpretar('media hora para bailar'), datos, azar: Random(2));
      final double total = r.pistas.fold(0, (double s, Elemento e) => s + e.duracion);
      expect(r.pistas, isNotEmpty);
      expect(total, lessThan(30 * 60 + 420));
    });

    test('ejemplos segun la hora', () {
      expect(ejemplosPara(DateTime(2026, 1, 1, 3)), contains('algo tranquilo para dormir'));
      expect(ejemplosPara(DateTime(2026, 1, 1, 21)), hasLength(3));
    });
  });
}
