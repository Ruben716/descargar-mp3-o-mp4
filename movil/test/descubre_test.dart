import 'package:descargador_movil/descubre.dart';
import 'package:descargador_movil/hecho_para_ti.dart';
import 'package:descargador_movil/nucleo.dart';
import 'package:flutter_test/flutter_test.dart';

Elemento _cancion(String artista, String tema) => Elemento(
      nombre: '$artista - $tema.opus',
      uri: 'content://$artista/$tema',
      duracion: 200,
      tamano: 1,
      audio: true,
    );

Resultado _deRadio(String video, String titulo, String autor, {double duracion = 210}) => Resultado(
      titulo: titulo,
      autor: autor,
      duracion: duracion,
      url: 'https://www.youtube.com/watch?v=$video',
    );

List<String> _titulos(List<Resultado> l) => <String>[for (final Resultado r in l) r.titulo];

void main() {
  group('semillas de la semana', () {
    // Seis artistas con tres canciones cada uno; A el mas oido, F el que menos.
    final List<Elemento> canciones = <Elemento>[
      for (final String a in <String>['A', 'B', 'C', 'D', 'E', 'F'])
        for (final String t in <String>['uno', 'dos', 'tres']) _cancion(a, t),
    ];
    final Map<String, Escucha> escuchas = <String, Escucha>{
      for (final (int i, String a) in <String>['A', 'B', 'C', 'D', 'E', 'F'].indexed)
        'content://$a/uno': (veces: 60 - i * 10, ultima: 0),
    };
    List<String> artistas(int semana) => <String>[
          for (final Semilla s in Descubre.elegirSemillas(canciones, escuchas, const <String, String>{}, semana: semana))
            s.artista,
        ];

    test('los dos que mas oyes van siempre y el resto cambia de una semana a otra', () {
      expect(artistas(1), hasLength(Descubre.cuantasSemillas));
      expect(artistas(1).take(2), <String>['A', 'B']);
      expect(artistas(1), artistas(1), reason: 'la misma semana, las mismas');
      final Set<String> restos = <String>{for (int s = 1; s <= 20; s++) artistas(s).skip(2).join()};
      expect(restos.length, greaterThan(1));
    });

    test('con el video si la cancion se bajo de YouTube; si no, se buscara', () {
      final List<Elemento> dos = <Elemento>[_cancion('Celia Cruz', 'Quimbara'), _cancion('Rubén Blades', 'Pedro Navaja')];
      final List<Semilla> s = Descubre.elegirSemillas(
        dos,
        const <String, Escucha>{},
        <String, String>{dos.first.uri: 'q1'},
        semana: 3,
      );
      expect(s.map((Semilla x) => (x.artista, x.tema, x.video)), <(String, String, String?)>[
        ('Celia Cruz', 'Quimbara', 'q1'),
        ('Rubén Blades', 'Pedro Navaja', null),
      ]);
      expect(Descubre.elegirSemillas(const <Elemento>[], const <String, Escucha>{}, const <String, String>{}, semana: 1),
          isEmpty);
    });
  });

  group('armar la lista', () {
    test('se turnan las radios y sale lo que ya tienes', () {
      final List<Resultado> lista = Descubre.armar(
        <List<Resultado>>[
          <Resultado>[
            _deRadio('s1', 'Vivir Mi Vida', 'Marc Anthony - Topic'),
            _deRadio('a2', 'Aguanile', 'Marc Anthony - Topic'),
            _deRadio('x9', 'Marc Anthony - Valió La Pena (Official Video)', 'MarcAnthonyVEVO'),
            _deRadio('a3', 'Ahora Quien', 'Marc Anthony - Topic'),
          ],
          <Resultado>[
            _deRadio('b1', 'Quimbara', 'Celia Cruz - Topic'),
            _deRadio('b2', 'Usted Abuso', 'Celia Cruz - Topic'),
          ],
        ],
        tengo: <String>{'s1'},
        conocidas: <String>{Descubre.claveDe('Marc Anthony', 'Valio la pena')},
      );
      expect(_titulos(lista), <String>['Aguanile', 'Quimbara', 'Ahora Quien', 'Usted Abuso'],
          reason: 'la semilla por su video y «Valió La Pena» por su nombre, aunque llegue desde otro video');
    });

    test('la misma cancion desde dos videos o dos radios cuenta una vez', () {
      final List<Resultado> lista = Descubre.armar(
        <List<Resultado>>[
          <Resultado>[_deRadio('i1', 'Idilio', 'Willie Colón - Topic')],
          <Resultado>[
            _deRadio('i2', 'Willie Colón - Idilio (Video Oficial)', 'WillieColonVEVO'),
            _deRadio('i1', 'Idilio', 'Willie Colón - Topic'),
          ],
        ],
        tengo: const <String>{},
        conocidas: const <String>{},
      );
      expect(_titulos(lista), <String>['Idilio']);
    });

    test('ni intros ni mezclas de una hora, y no pasa del largo', () {
      final List<Resultado> lista = Descubre.armar(
        <List<Resultado>>[
          <Resultado>[
            _deRadio('c1', 'Intro', 'X - Topic', duracion: 30),
            _deRadio('c2', 'Salsa mix 1 hora', 'Canal', duracion: 3600),
            _deRadio('c3', 'Sin duracion', 'X - Topic', duracion: 0),
            _deRadio('c4', 'Otra', 'X - Topic'),
            _deRadio('c5', 'Y otra', 'X - Topic'),
          ],
        ],
        tengo: const <String>{},
        conocidas: const <String>{},
        cuantas: 2,
      );
      expect(_titulos(lista), <String>['Sin duracion', 'Otra']);
    });
  });

  test('la radio de un video y la portada si la lista no la trae', () {
    expect(Descubre.radioDe('abc'), 'https://www.youtube.com/watch?v=abc&list=RDAMVMabc');
    expect(Descubre.portadaDe(_deRadio('abc', 'T', 'A')), 'https://i.ytimg.com/vi/abc/hqdefault.jpg');
    expect(Descubre.unir(<String>['A', 'B', 'C']), 'A, B y C');
    final DateTime lunes = DateTime(2026, 10, 12);
    expect(Descubre.semanaDe(lunes), Descubre.semanaDe(lunes));
    expect(Descubre.semanaDe(lunes.add(const Duration(days: 7))), Descubre.semanaDe(lunes) + 1);
  });
}
