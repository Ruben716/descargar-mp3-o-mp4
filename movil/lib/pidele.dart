import 'dart:math';

import 'calidad.dart';
import 'dj.dart';
import 'formato.dart';
import 'nucleo.dart';
import 'ritmos.dart';

/// «Pidele a Tumbao»: una frase en castellano se convierte en una cola.
///
/// Sin red y sin IA: reglas. Primero los numeros (bpm, minutos, cuantas,
/// decadas), luego los artistas de la biblioteca y al final las frases fijas,
/// de la mas larga a la mas corta («sin perdida» antes que «sin»). Lo que no
/// se entiende se ignora, pero lo entendido se ensenia en fichas para que se
/// pueda quitar. Las energias son percentiles de la propia biblioteca: «0,4»
/// quiere decir el 40 % mas tranquilo de lo que tienes.

/// Minusculas, sin tildes ni signos, con «pa» como «para» y un espacio a
/// cada lado, para buscar palabras enteras con `' palabra '`.
String normalizarFrase(String frase) {
  String t = sinTildes(frase);
  t = t.replaceAll(RegExp(r"\bpa'?l\b"), 'para el').replaceAll(RegExp(r"\bpa'?(\s|$)"), r'para ');
  t = t.replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return ' $t ';
}

/// Como se ordena lo que sale.
enum OrdenPeticion { tal, dj, subir, bajar, arco, masEscuchadas, recientes, aleatorio }

/// La calidad minima que se pide.
enum CalidadPedida { alta, sinPerdida, hiRes }

/// Lo que se entendio de una frase.
class Peticion {
  double? energiaMin;
  double? energiaMax;
  double? bpmMin;
  double? bpmMax;
  final Set<String> artistas = <String>{};
  final Set<String> sinArtistas = <String>{};
  final Set<String> generos = <String>{};
  final Set<String> sinGeneros = <String>{};
  bool favoritas = false;
  bool sinEscuchar = false;
  bool olvidadas = false;
  bool radio = false;
  int? minEscuchas;
  CalidadPedida? calidad;
  int? duracionMin;
  int? duracionMax;

  /// Descargada hace como mucho estos dias.
  int? dias;
  int? anioMin;
  int? anioMax;
  int? limite;
  int? minutos;
  OrdenPeticion orden = OrdenPeticion.tal;

  /// Lo entendido, en el orden en que salio, para ensenarlo en fichas.
  final List<String> entendido = <String>[];

  /// Si no se entendio nada que filtre u ordene.
  bool get vacia => entendido.isEmpty;

  bool get pideRitmo => energiaMin != null || energiaMax != null || bpmMin != null || bpmMax != null;

  void energia(double? minimo, double? maximo) {
    if (minimo != null) energiaMin = energiaMin == null ? minimo : max(minimo, energiaMin!);
    if (maximo != null) energiaMax = energiaMax == null ? maximo : min(maximo, energiaMax!);
  }

  void ordenSiNoHay(OrdenPeticion o) {
    if (orden == OrdenPeticion.tal) orden = o;
  }

  ModoDj? get modoDj => switch (orden) {
        OrdenPeticion.dj => ModoDj.flujo,
        OrdenPeticion.subir => ModoDj.subir,
        OrdenPeticion.bajar => ModoDj.bajar,
        OrdenPeticion.arco => ModoDj.arco,
        _ => null,
      };

  @override
  String toString() => entendido.join(' · ');
}

typedef _Regla = void Function(Peticion p);

void _paraDormir(Peticion p) {
  p.energia(null, .25);
  p.bpmMax ??= 100;
  p.ordenSiNoHay(OrdenPeticion.bajar);
  p.minutos ??= 45;
}

void _dormir(Peticion p) {
  p.energia(null, .25);
  p.ordenSiNoHay(OrdenPeticion.bajar);
}

void _tranquila(Peticion p) => p.energia(null, .4);
void _suave(Peticion p) => p.energia(null, .45);

void _lenta(Peticion p) {
  p.bpmMax ??= 95;
  p.energia(null, .5);
}

void _despecho(Peticion p) => p.energia(null, .55);

void _concentrarse(Peticion p) {
  p.energia(.1, .5);
  p.ordenSiNoHay(OrdenPeticion.dj);
}

void _trabajar(Peticion p) {
  p.energia(.2, .6);
  p.ordenSiNoHay(OrdenPeticion.dj);
}

void _leer(Peticion p) => p.energia(null, .35);

void _cocinar(Peticion p) {
  p.energia(.35, .8);
  p.ordenSiNoHay(OrdenPeticion.dj);
}

void _manejar(Peticion p) {
  p.energia(.4, .85);
  p.ordenSiNoHay(OrdenPeticion.dj);
}

void _viaje(Peticion p) {
  p.energia(.3, .85);
  p.ordenSiNoHay(OrdenPeticion.dj);
}

void _entrenar(Peticion p) {
  p.energia(.65, null);
  p.ordenSiNoHay(OrdenPeticion.subir);
}

void _cardio(Peticion p) {
  p.energia(.7, null);
  p.bpmMin ??= 120;
  p.ordenSiNoHay(OrdenPeticion.subir);
}

void _correr(Peticion p) {
  p.energia(.6, null);
  p.bpmMin ??= 150;
  p.bpmMax ??= 185;
  p.ordenSiNoHay(OrdenPeticion.dj);
}

void _fiesta(Peticion p) {
  p.energia(.6, null);
  p.ordenSiNoHay(OrdenPeticion.arco);
}

void _previa(Peticion p) {
  p.energia(.5, null);
  p.ordenSiNoHay(OrdenPeticion.subir);
}

void _bailar(Peticion p) {
  p.energia(.55, null);
  p.ordenSiNoHay(OrdenPeticion.dj);
}

void _perreo(Peticion p) {
  p.generos.add('reggaeton');
  p.energia(.55, null);
  p.ordenSiNoHay(OrdenPeticion.dj);
}

void _animada(Peticion p) => p.energia(.6, null);

void _rapida(Peticion p) {
  p.bpmMin ??= 120;
  p.energia(.5, null);
}

void _aTope(Peticion p) => p.energia(.8, null);
void _subir(Peticion p) => p.orden = OrdenPeticion.subir;
void _bajar(Peticion p) => p.orden = OrdenPeticion.bajar;
void _dj(Peticion p) => p.orden = OrdenPeticion.dj;
void _aleatorio(Peticion p) => p.orden = OrdenPeticion.aleatorio;

void _top(Peticion p) {
  p.minEscuchas = 2;
  p.orden = OrdenPeticion.masEscuchadas;
}

void _favoritas(Peticion p) => p.favoritas = true;
void _sinEscuchar(Peticion p) => p.sinEscuchar = true;

void _olvidadas(Peticion p) {
  p.olvidadas = true;
  p.minEscuchas = 2;
}

void _sinPerdida(Peticion p) => p.calidad = CalidadPedida.sinPerdida;
void _hiRes(Peticion p) => p.calidad = CalidadPedida.hiRes;
void _altaCalidad(Peticion p) => p.calidad ??= CalidadPedida.alta;
void _largas(Peticion p) => p.duracionMin = 360;
void _cortas(Peticion p) => p.duracionMax = 180;

void _recientes(Peticion p) {
  p.dias = 14;
  p.orden = OrdenPeticion.recientes;
}

void _radio(Peticion p) => p.radio = true;

/// Palabras y frases, ya normalizadas, y lo que significan.
final Map<String, (String, _Regla)> _reglas = <String, (String, _Regla)>{
  // Ambiente y actividad
  'para dormir': ('Para dormir', _paraDormir),
  'dormir': ('Para dormir', _dormir),
  'tranquilo': ('Tranquila', _tranquila),
  'tranquila': ('Tranquila', _tranquila),
  'tranquilas': ('Tranquila', _tranquila),
  'tranquilos': ('Tranquila', _tranquila),
  'tranqui': ('Tranquila', _tranquila),
  'relajado': ('Relajada', _tranquila),
  'relajada': ('Relajada', _tranquila),
  'relajarme': ('Relajada', _tranquila),
  'relax': ('Relajada', _tranquila),
  'calma': ('Tranquila', _tranquila),
  'chill': ('Chill', _suave),
  'suave': ('Suave', _suave),
  'suaves': ('Suave', _suave),
  'suavecito': ('Suave', _suave),
  'lento': ('Lenta', _lenta),
  'lenta': ('Lenta', _lenta),
  'lentas': ('Lenta', _lenta),
  'triste': ('Bajon', _tranquila),
  'tristes': ('Bajon', _tranquila),
  'bajon': ('Bajon', _tranquila),
  'despecho': ('Despecho', _despecho),
  'estudiar': ('Para estudiar', _concentrarse),
  'concentrarme': ('Para concentrarse', _concentrarse),
  'concentrarse': ('Para concentrarse', _concentrarse),
  'trabajar': ('Para trabajar', _trabajar),
  'leer': ('Para leer', _leer),
  'cocinar': ('Para cocinar', _cocinar),
  'limpiar': ('Para limpiar', _cocinar),
  'manejar': ('Para manejar', _manejar),
  'viaje': ('De viaje', _viaje),
  'viajar': ('De viaje', _viaje),
  'entrenar': ('Para entrenar', _entrenar),
  'gym': ('Para entrenar', _entrenar),
  'gimnasio': ('Para entrenar', _entrenar),
  'ejercicio': ('Para entrenar', _entrenar),
  'cardio': ('Cardio', _cardio),
  'correr': ('Para correr', _correr),
  'fiesta': ('Fiesta', _fiesta),
  'tono': ('Fiesta', _fiesta),
  'juerga': ('Fiesta', _fiesta),
  'jarana': ('Fiesta', _fiesta),
  'previa': ('Previa', _previa),
  'bailar': ('Para bailar', _bailar),
  'bailable': ('Para bailar', _bailar),
  'bailables': ('Para bailar', _bailar),
  'perreo': ('Perreo', _perreo),
  'animado': ('Animada', _animada),
  'animada': ('Animada', _animada),
  'animadas': ('Animada', _animada),
  'movida': ('Movida', _animada),
  'movidas': ('Movida', _animada),
  'rapido': ('Rapida', _rapida),
  'rapida': ('Rapida', _rapida),
  'rapidas': ('Rapida', _rapida),
  'con todo': ('A tope', _aTope),
  'a tope': ('A tope', _aTope),
  // Orden
  'que vaya subiendo': ('Subiendo', _subir),
  'de menos a mas': ('Subiendo', _subir),
  'subiendo': ('Subiendo', _subir),
  'de mas a menos': ('Bajando', _bajar),
  'bajando': ('Bajando', _bajar),
  'mezcla': ('Mezcla DJ', _dj),
  'mezcladas': ('Mezcla DJ', _dj),
  'estilo dj': ('Mezcla DJ', _dj),
  'sin cortes': ('Mezcla DJ', _dj),
  'aleatorio': ('Aleatorio', _aleatorio),
  'random': ('Aleatorio', _aleatorio),
  // Lo que se escucha
  'lo que mas escucho': ('Lo mas escuchado', _top),
  'lo mas escuchado': ('Lo mas escuchado', _top),
  'mas escuchadas': ('Lo mas escuchado', _top),
  'mi top': ('Lo mas escuchado', _top),
  'top': ('Lo mas escuchado', _top),
  'favoritas': ('Me gusta', _favoritas),
  'favoritos': ('Me gusta', _favoritas),
  'me gusta': ('Me gusta', _favoritas),
  'me gustan': ('Me gusta', _favoritas),
  'con corazon': ('Me gusta', _favoritas),
  'nunca escuche': ('Sin escuchar', _sinEscuchar),
  'sin escuchar': ('Sin escuchar', _sinEscuchar),
  'no he escuchado': ('Sin escuchar', _sinEscuchar),
  'olvidadas': ('Olvidadas', _olvidadas),
  'hace tiempo': ('Olvidadas', _olvidadas),
  // Calidad
  'sin perdida': ('Sin perdida', _sinPerdida),
  'flac': ('Sin perdida', _sinPerdida),
  'lossless': ('Sin perdida', _sinPerdida),
  'hi res': ('Hi-Res', _hiRes),
  'hires': ('Hi-Res', _hiRes),
  'alta resolucion': ('Hi-Res', _hiRes),
  'alta calidad': ('Alta calidad', _altaCalidad),
  'buena calidad': ('Alta calidad', _altaCalidad),
  // Duracion y fecha
  'largas': ('Largas (+6 min)', _largas),
  'largos': ('Largas (+6 min)', _largas),
  'cortas': ('Cortas (-3 min)', _cortas),
  'cortitas': ('Cortas (-3 min)', _cortas),
  'recien bajadas': ('Recien bajadas', _recientes),
  'lo ultimo que baje': ('Recien bajadas', _recientes),
  'nuevas': ('Recien bajadas', _recientes),
  'de hoy': ('De hoy', (Peticion p) => p.dias = 1),
  'esta semana': ('Esta semana', (Peticion p) => p.dias = 7),
  'este mes': ('Este mes', (Peticion p) => p.dias = 31),
  // Radio en vivo
  'radio': ('Radio', _radio),
  'emisora': ('Radio', _radio),
  'emisoras': ('Radio', _radio),
};

/// Un genero: su nombre, las etiquetas que lo delatan y su tempo tipico,
/// para cuando la cancion no trae etiqueta.
class Genero {
  const Genero(this.nombre, this.etiquetas, this.bpmMin, this.bpmMax);

  final String nombre;
  final List<String> etiquetas;
  final double bpmMin;
  final double bpmMax;

  bool get conTempo => bpmMax < 900;

  String get titulo => nombre[0].toUpperCase() + nombre.substring(1);
}

const Genero _reggaeton =
    Genero('reggaeton', <String>['reggaeton', 'regueton', 'dembow', 'urbano', 'latin urban', 'perreo'], 85, 105);
const Genero _salsa = Genero('salsa', <String>['salsa'], 160, 220);
const Genero _cumbia = Genero('cumbia', <String>['cumbia', 'chicha', 'tropical'], 85, 115);
const Genero _balada = Genero('balada', <String>['balada', 'ballad', 'romantic', 'bolero'], 60, 100);
const Genero _hipHop = Genero('hip hop', <String>['hip hop', 'hiphop', 'rap'], 80, 100);
const Genero _lofi = Genero('lofi', <String>['lofi', 'lo fi', 'chillhop'], 60, 95);
const Genero _electronica =
    Genero('electronica', <String>['electronic', 'electronica', 'edm', 'dance'], 118, 140);
const Genero _kpop = Genero('kpop', <String>['k pop', 'kpop'], 90, 140);

/// Las palabras que nombran un genero, ya normalizadas.
const Map<String, Genero> generos = <String, Genero>{
  'reggaeton': _reggaeton,
  'regueton': _reggaeton,
  'dembow': _reggaeton,
  'urbano': _reggaeton,
  'trap': Genero('trap', <String>['trap'], 130, 160),
  'salsa': _salsa,
  'salsita': _salsa,
  'cumbia': _cumbia,
  'cumbias': _cumbia,
  'chicha': _cumbia,
  'bachata': Genero('bachata', <String>['bachata'], 120, 145),
  'merengue': Genero('merengue', <String>['merengue'], 130, 170),
  'huayno': Genero('huayno', <String>['huayno', 'andina', 'andean'], 100, 140),
  'criolla': Genero('criolla', <String>['criolla', 'vals', 'festejo', 'afroperuana'], 0, 999),
  'rock': Genero('rock', <String>['rock'], 100, 160),
  'metal': Genero('metal', <String>['metal'], 100, 200),
  'electronica': _electronica,
  'electro': _electronica,
  'house': Genero('house', <String>['house'], 118, 130),
  'techno': Genero('techno', <String>['techno'], 125, 150),
  'drum and bass': Genero('drum and bass', <String>['drum and bass', 'drum n bass', 'dnb', 'jungle'], 160, 180),
  'lofi': _lofi,
  'lo fi': _lofi,
  'rap': _hipHop,
  'hip hop': _hipHop,
  'pop': Genero('pop', <String>['pop'], 90, 130),
  'balada': _balada,
  'baladas': _balada,
  'romanticas': _balada,
  'romanticos': _balada,
  'bolero': _balada,
  'boleros': _balada,
  'clasica': Genero('clasica', <String>['classical', 'clasica', 'orchestra', 'opera', 'baroque'], 0, 999),
  'jazz': Genero('jazz', <String>['jazz', 'swing', 'bossa'], 0, 999),
  'kpop': _kpop,
  'k pop': _kpop,
  'anime': Genero('anime', <String>['anime', 'j pop', 'jpop'], 0, 999),
};

/// Artistas que delatan un genero aunque el archivo no diga nada. La lista
/// crece sola con las etiquetas reales de la biblioteca (ver [aplicarPeticion]).
const Map<String, List<String>> artistasSemilla = <String, List<String>>{
  'reggaeton': <String>[
    'bad bunny', 'daddy yankee', 'karol g', 'feid', 'j balvin', 'ozuna', 'anuel aa', 'rauw alejandro',
    'maluma', 'nicky jam', 'wisin', 'yandel', 'wisin y yandel', 'don omar', 'myke towers', 'sech',
    'farruko', 'arcangel', 'de la ghetto', 'tego calderon', 'ivy queen', 'jhayco', 'young miko',
  ],
  'salsa': <String>[
    'hector lavoe', 'celia cruz', 'grupo niche', 'marc anthony', 'willie colon', 'ruben blades',
    'gilberto santa rosa', 'oscar d leon', 'el gran combo', 'frankie ruiz', 'eddie santiago',
    'jerry rivera', 'victor manuelle', 'joe arroyo', 'tito nieves', 'la india', 'ismael rivera',
  ],
  'cumbia': <String>[
    'grupo 5', 'agua marina', 'los mirlos', 'armonia 10', 'corazon serrano', 'los shapis', 'chacalon',
    'juaneco y su combo', 'hermanos yaipen', 'los karkiks', 'los angeles azules', 'la sonora dinamita',
    'tony rosado', 'marisol', 'yarita lizeth', 'deyvis orosco',
  ],
  'bachata': <String>['romeo santos', 'aventura', 'prince royce', 'frank reyes', 'anthony santos'],
  'merengue': <String>['juan luis guerra', 'wilfrido vargas', 'elvis crespo', 'los hermanos rosario'],
  'criolla': <String>['chabuca granda', 'eva ayllon', 'lucha reyes', 'arturo zambo cavero', 'los morochucos'],
  'huayno': <String>['dina paucar', 'sonia morales', 'william luna', 'max castro', 'flor pucarina'],
  'rock': <String>[
    'soda stereo', 'los prisioneros', 'heroes del silencio', 'enanitos verdes', 'caifanes', 'mana',
    'queen', 'ac dc', 'guns n roses', 'nirvana', 'led zeppelin', 'the beatles', 'pink floyd',
    'los hermanos', 'pedro suarez vertiz', 'mar de copas', 'libido', 'tk',
  ],
  'metal': <String>['metallica', 'iron maiden', 'slayer', 'megadeth', 'black sabbath', 'rata blanca'],
  'balada': <String>[
    'luis miguel', 'jose jose', 'camilo sesto', 'julio iglesias', 'rocio durcal', 'juan gabriel',
    'ricardo arjona', 'alejandro sanz', 'franco de vita', 'cristian castro', 'chayanne',
  ],
  'electronica': <String>['daft punk', 'avicii', 'david guetta', 'calvin harris', 'martin garrix', 'tiesto'],
  'kpop': <String>['bts', 'blackpink', 'twice', 'stray kids', 'newjeans', 'seventeen', 'aespa'],
  'jazz': <String>['miles davis', 'john coltrane', 'louis armstrong', 'ella fitzgerald', 'bill evans', 'chet baker'],
  'clasica': <String>[
    'mozart', 'beethoven', 'bach', 'chopin', 'vivaldi', 'tchaikovsky', 'debussy', 'schubert', 'brahms',
  ],
  'hip hop': <String>['eminem', 'kendrick lamar', 'drake', 'tupac', 'canserbero', 'residente', 'calle 13'],
  'pop': <String>[
    'taylor swift', 'dua lipa', 'shakira', 'the weeknd', 'ed sheeran', 'ariana grande', 'billie eilish',
  ],
};

/// Etiquetas de genero que no dicen nada: YouTube pone «Music» a todo.
const Set<String> etiquetasVacias = <String>{
  'music', 'musica', 'entertainment', 'people blogs', 'people and blogs', 'film animation', 'gaming',
  'other', 'otros', 'unknown', 'none', 'genre', 'audio', 'video', 'videos', 'education', 'comedy',
};

const List<String> _negaciones = <String>['que no sea', 'nada de', 'excepto', 'menos', 'sin', 'no', 'ni'];

int _anioDeDecada(String d) {
  final int n = int.parse(d);
  return n >= 1900 ? n : 1900 + n;
}

const Map<String, int> _horas = <String, int>{'una': 60, '1': 60, 'dos': 120, '2': 120, 'media': 30};

/// Patrones con numeros: lo primero que se lee.
final List<(RegExp, String Function(Match), _Regla Function(Match))> _patrones =
    <(RegExp, String Function(Match), _Regla Function(Match))>[
  (
    RegExp(r' entre (\d{2,3}) y (\d{2,3}) bpm '),
    (Match m) => '${m[1]}-${m[2]} BPM',
    (Match m) => (Peticion p) {
          p.bpmMin = double.parse(m[1]!);
          p.bpmMax = double.parse(m[2]!);
        },
  ),
  (
    RegExp(r' (?:a )?(\d{2,3}) bpm '),
    (Match m) => '${m[1]} BPM',
    (Match m) => (Peticion p) {
          final double b = double.parse(m[1]!);
          p.bpmMin = b * .97;
          p.bpmMax = b * 1.03;
        },
  ),
  (
    RegExp(r' mas de (\d{1,2}) min(?:utos)? '),
    (Match m) => '+${m[1]} min',
    (Match m) => (Peticion p) => p.duracionMin = int.parse(m[1]!) * 60,
  ),
  (
    RegExp(r' menos de (\d{1,2}) min(?:utos)? '),
    (Match m) => '-${m[1]} min',
    (Match m) => (Peticion p) => p.duracionMax = int.parse(m[1]!) * 60,
  ),
  (
    RegExp(r' (\d{1,3}) (?:canciones|temas|rolas) '),
    (Match m) => '${m[1]} canciones',
    (Match m) => (Peticion p) => p.limite = int.parse(m[1]!),
  ),
  (
    RegExp(r' (una|1|2|dos|media) horas? '),
    (Match m) => _horas[m[1]]! >= 60 ? '${_horas[m[1]]! ~/ 60} h' : '30 min',
    (Match m) => (Peticion p) => p.minutos = _horas[m[1]],
  ),
  (
    RegExp(r' (\d{2,3}) min(?:utos)? '),
    (Match m) => '${m[1]} min',
    (Match m) => (Peticion p) => p.minutos = int.parse(m[1]!),
  ),
  (
    RegExp(r' (?:de los|anos|los) (?:19)?([5-9]0)s? '),
    (Match m) => 'Anos ${m[1]}',
    (Match m) => (Peticion p) {
          p.anioMin = _anioDeDecada(m[1]!);
          p.anioMax = p.anioMin! + 9;
        },
  ),
  (
    RegExp(r' (?:de los|anos|los) (2000|2010|2020)s? '),
    (Match m) => 'Anos ${m[1]}',
    (Match m) => (Peticion p) {
          p.anioMin = int.parse(m[1]!);
          p.anioMax = p.anioMin! + 9;
        },
  ),
  (
    RegExp(r' del (19[5-9]\d|20[0-3]\d) '),
    (Match m) => 'Del ${m[1]}',
    (Match m) => (Peticion p) {
          p.anioMin = int.parse(m[1]!);
          p.anioMax = p.anioMin;
        },
  ),
];

/// Distancia de edicion, para perdonar una errata en un artista.
int levenshtein(String a, String b) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  List<int> antes = List<int>.generate(b.length + 1, (int i) => i);
  for (int i = 0; i < a.length; i++) {
    final List<int> ahora = <int>[i + 1];
    for (int j = 0; j < b.length; j++) {
      ahora.add(<int>[ahora[j] + 1, antes[j + 1] + 1, antes[j] + (a[i] == b[j] ? 0 : 1)].reduce(min));
    }
    antes = ahora;
  }
  return antes.last;
}

/// Entiende [frase]. [artistas] son los de la biblioteca, ya normalizados
/// con [normalizarFrase] (sin los espacios de los lados). Lo que este en
/// [quitar] (etiquetas de [Peticion.entendido]) se lee pero no se aplica:
/// es lo que el usuario descarto tocando la ficha.
Peticion interpretar(
  String frase, {
  Set<String> artistas = const <String>{},
  Set<String> quitar = const <String>{},
}) {
  final Peticion p = Peticion();
  String t = normalizarFrase(frase);

  void quitarTramo(int inicio, int fin) => t = '${t.substring(0, inicio)} ${t.substring(fin)}';

  void apuntar(String etiqueta, void Function() aplicar) {
    if (p.entendido.contains(etiqueta)) return;
    p.entendido.add(etiqueta);
    if (!quitar.contains(etiqueta)) aplicar();
  }

  /// La negacion que va justo delante de [inicio], o null.
  String? negacion(int inicio) {
    final String antes = t.substring(0, inicio).trimRight();
    for (final String n in _negaciones) {
      if (antes == n || antes.endsWith(' $n')) return n;
    }
    return null;
  }

  void quitarNegacion(int inicio, String n) {
    final String antes = t.substring(0, inicio).trimRight();
    t = '${antes.substring(0, antes.length - n.length)} ${t.substring(inicio)}';
  }

  // 1. Numeros (bpm, minutos, cuantas, anios): antes que nada.
  for (final (RegExp patron, String Function(Match) etiqueta, _Regla Function(Match) regla) in _patrones) {
    Match? m;
    while ((m = patron.firstMatch(t)) != null) {
      final Match hallado = m!;
      apuntar(etiqueta(hallado), () => regla(hallado)(p));
      quitarTramo(hallado.start, hallado.end - 1);
    }
  }

  // 2. Artistas de la biblioteca, el nombre mas largo primero; con cinco
  // letras o mas se perdona una errata.
  // Un artista que se llama como una palabra clave («Fiesta») no la tapa.
  final List<String> porLargo = artistas
      .where((String a) => a.length >= 3 && !_reglas.containsKey(a) && !generos.containsKey(a))
      .toList()
    ..sort((String a, String b) => b.length.compareTo(a.length));
  for (final String a in porLargo) {
    int i = t.indexOf(' $a ');
    int largo = a.length;
    if (i < 0 && a.length >= 5) {
      final List<String> palabras = t.trim().split(' ');
      final int n = a.split(' ').length;
      for (int k = 0; k + n <= palabras.length; k++) {
        final String trozo = palabras.sublist(k, k + n).join(' ');
        if (trozo.length >= 4 && levenshtein(trozo, a) <= 1) {
          i = t.indexOf(' $trozo ');
          largo = trozo.length;
          break;
        }
      }
    }
    if (i < 0) continue;
    final String? n = negacion(i);
    final String nombre = a.split(' ').map((String w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ');
    quitarTramo(i, i + largo + 1);
    if (n != null) {
      apuntar('Sin $nombre', () => p.sinArtistas.add(a));
      quitarNegacion(i, n);
    } else {
      apuntar('De $nombre', () => p.artistas.add(a));
    }
  }

  // 3. Frases fijas y generos, de la mas larga a la mas corta.
  final List<String> claves = <String>{..._reglas.keys, ...generos.keys}.toList()
    ..sort((String a, String b) => b.length.compareTo(a.length));
  for (final String c in claves) {
    final int i = t.indexOf(' $c ');
    if (i < 0) continue;
    final Genero? g = generos[c];
    if (g != null) {
      final String? n = negacion(i);
      quitarTramo(i, i + c.length + 1);
      if (n != null) {
        apuntar('Sin ${g.nombre}', () => p.sinGeneros.add(g.nombre));
        quitarNegacion(i, n);
      } else {
        apuntar(g.titulo, () => p.generos.add(g.nombre));
      }
    } else {
      final (String etiqueta, _Regla regla) = _reglas[c]!;
      apuntar(etiqueta, () => regla(p));
      quitarTramo(i, i + c.length + 1);
    }
  }
  return p;
}

/// Lo que sale de aplicar una peticion a la biblioteca.
class Respuesta {
  const Respuesta({
    required this.pistas,
    this.avisos = const <String>[],
    this.sinAnalizar = 0,
  });

  final List<Elemento> pistas;

  /// Lo que se tuvo que relajar para que saliera algo, contado.
  final List<String> avisos;

  /// Cuantas se quedaron fuera solo por no estar analizadas.
  final int sinAnalizar;
}

/// Todo lo que hace falta saber de la biblioteca para aplicar una peticion.
class DatosBiblioteca {
  const DatosBiblioteca({
    required this.canciones,
    this.rasgos = const <String, Rasgos>{},
    this.escuchas = const <String, ({int veces, int ultima})>{},
    this.favoritas = const <String>{},
    this.calidades = const <String, CalidadAudio>{},
    this.percentil,
  });

  final List<Elemento> canciones;
  final Map<String, Rasgos> rasgos;
  final Map<String, ({int veces, int ultima})> escuchas;
  final Set<String> favoritas;
  final Map<String, CalidadAudio> calidades;

  /// El percentil de energia de cada cancion; si no se da, se calcula aqui.
  final double? Function(String uri)? percentil;

  /// Los artistas normalizados, para [interpretar].
  Set<String> get artistas => <String>{
        for (final Elemento e in canciones)
          if (e.artista.trim().isNotEmpty) normalizarFrase(e.artista).trim(),
      };
}

bool _enRango(double bpm, double minimo, double maximo) =>
    <double>[bpm, bpm * 2, bpm / 2].any((double b) => b >= minimo && b <= maximo);

/// La etiqueta de genero, normalizada; vacia si no dice nada.
String _etiquetaUtil(String genero) {
  final String g = normalizarFrase(genero).trim();
  return etiquetasVacias.contains(g) ? '' : g;
}

bool _etiquetaEs(String etiqueta, Genero g) =>
    etiqueta.isNotEmpty && g.etiquetas.any((String e) => ' $etiqueta '.contains(' $e') || etiqueta == e);

/// Si [e] es de [g] con seguridad: por la etiqueta de genero del archivo o
/// porque su artista es de los conocidos del genero. El tempo no basta.
bool cancionDelGenero(Elemento e, Genero g, {Rasgos? rasgos}) =>
    _etiquetaEs(_etiquetaUtil(rasgos?.genero ?? ''), g) ||
    (artistasSemilla[g.nombre] ?? const <String>[]).contains(normalizarFrase(e.artista).trim());

/// Cada genero una vez, en el orden en que se definen.
List<Genero> get generosDistintos => generos.values.toSet().toList();

/// Aplica [p] sobre [datos]. Si no sale nada, relaja por pasos y lo cuenta.
Respuesta aplicarPeticion(Peticion p, DatosBiblioteca datos, {DateTime? ahora, Random? azar}) {
  final DateTime hoy = ahora ?? DateTime.now();
  final Map<String, double> percentiles = <String, double>{};
  if (datos.percentil == null) {
    final List<MapEntry<String, Rasgos>> orden = datos.rasgos.entries.toList()
      ..sort((MapEntry<String, Rasgos> a, MapEntry<String, Rasgos> b) => a.value.energia.compareTo(b.value.energia));
    for (int i = 0; i < orden.length; i++) {
      percentiles[orden[i].key] = orden.length < 2 ? 0.5 : i / (orden.length - 1);
    }
  }
  double? percentil(String uri) => datos.percentil != null ? datos.percentil!(uri) : percentiles[uri];

  // El genero que la biblioteca le da a cada artista por sus etiquetas reales.
  final Map<String, Set<String>> etiquetasDeArtista = <String, Set<String>>{};
  for (final Elemento e in datos.canciones) {
    final String etiqueta = _etiquetaUtil(datos.rasgos[e.uri]?.genero ?? '');
    if (etiqueta.isEmpty) continue;
    etiquetasDeArtista.putIfAbsent(normalizarFrase(e.artista).trim(), () => <String>{}).add(etiqueta);
  }

  Genero? generoDe(String nombre) {
    for (final Genero g in generos.values) {
      if (g.nombre == nombre) return g;
    }
    return null;
  }

  /// Puntos de genero: 3 por etiqueta o artista conocido, 1 por tempo.
  int puntos(Elemento e, Genero g) {
    final String artista = normalizarFrase(e.artista).trim();
    final Rasgos? r = datos.rasgos[e.uri];
    if (_etiquetaEs(_etiquetaUtil(r?.genero ?? ''), g)) return 3;
    if ((artistasSemilla[g.nombre] ?? const <String>[]).contains(artista)) return 3;
    if ((etiquetasDeArtista[artista] ?? const <String>{}).any((String et) => _etiquetaEs(et, g))) return 3;
    // Por tempo, sin perdonar el doble ni la mitad: una salsa a 180 y un
    // reggaeton a 95 (190 al doble) no pueden pasar por lo mismo.
    if (g.conTempo && r != null && r.conPulso && r.bpm! >= g.bpmMin && r.bpm! <= g.bpmMax) return 1;
    return 0;
  }

  int sinAnalizar = 0;

  List<Elemento> filtrar({
    required double? eMin,
    required double? eMax,
    required double? bMin,
    required double? bMax,
    required int minimoGenero,
    required bool conGenero,
    required bool conDuracionYFecha,
  }) {
    final List<Genero> pedidos = <Genero>[for (final String n in p.generos) ?generoDe(n)];
    final List<Genero> fuera = <Genero>[for (final String n in p.sinGeneros) ?generoDe(n)];
    final int ahoraEnSegundos = hoy.millisecondsSinceEpoch ~/ 1000;
    final int haceUnMes = hoy.subtract(const Duration(days: 30)).millisecondsSinceEpoch;
    int faltan = 0;
    final List<Elemento> salen = <Elemento>[];
    for (final Elemento e in datos.canciones) {
      if (!e.audio) continue;
      final String artista = normalizarFrase(e.artista).trim();
      if (p.artistas.isNotEmpty && !p.artistas.contains(artista)) continue;
      if (p.sinArtistas.contains(artista)) continue;
      if (p.favoritas && !datos.favoritas.contains(e.uri)) continue;
      final ({int veces, int ultima})? oida = datos.escuchas[e.uri];
      if (p.sinEscuchar && (oida?.veces ?? 0) > 0) continue;
      if (p.minEscuchas != null && (oida?.veces ?? 0) < p.minEscuchas!) continue;
      if (p.olvidadas && (oida == null || oida.ultima > haceUnMes)) continue;
      final CalidadAudio? calidad = datos.calidades[e.uri];
      switch (p.calidad) {
        case CalidadPedida.hiRes:
          if (calidad == null || !calidad.hiRes) continue;
        case CalidadPedida.sinPerdida:
          if (calidad == null || !calidad.sinPerdida) continue;
        case CalidadPedida.alta:
          if (calidad == null || !(calidad.sinPerdida || (calidad.kbps ?? 0) >= 150)) continue;
        case null:
          break;
      }
      if (conDuracionYFecha) {
        if (p.duracionMin != null && e.duracion < p.duracionMin!) continue;
        if (p.duracionMax != null && e.duracion > p.duracionMax!) continue;
        if (p.dias != null && (e.fecha <= 0 || ahoraEnSegundos - e.fecha > p.dias! * 86400)) continue;
      }
      final Rasgos? r = datos.rasgos[e.uri];
      if (p.anioMin != null) {
        final int? anio = r?.anio;
        if (anio == null || anio < p.anioMin! || anio > (p.anioMax ?? p.anioMin!)) continue;
      }
      if (fuera.any((Genero g) => puntos(e, g) >= 3)) continue;
      if (conGenero && pedidos.isNotEmpty && !pedidos.any((Genero g) => puntos(e, g) >= minimoGenero)) continue;
      if (eMin != null || eMax != null || bMin != null || bMax != null) {
        if (r == null) {
          faltan++;
          continue;
        }
        final double? pe = percentil(e.uri);
        if (eMin != null && (pe == null || pe < eMin)) continue;
        if (eMax != null && (pe == null || pe > eMax)) continue;
        if (bMin != null || bMax != null) {
          if (!r.conPulso || !_enRango(r.bpm!, bMin ?? 0, bMax ?? 999)) continue;
        }
      }
      salen.add(e);
    }
    sinAnalizar = faltan;
    return salen;
  }

  final List<String> avisos = <String>[];
  double? eMin = p.energiaMin;
  double? eMax = p.energiaMax;
  double? bMin = p.bpmMin;
  double? bMax = p.bpmMax;
  int minimoGenero = 3;
  bool conGenero = true;
  bool conDuracionYFecha = true;
  List<Elemento> intento() => filtrar(
        eMin: eMin,
        eMax: eMax,
        bMin: bMin,
        bMax: bMax,
        minimoGenero: minimoGenero,
        conGenero: conGenero,
        conDuracionYFecha: conDuracionYFecha,
      );

  // El genero por tempo solo si en toda la biblioteca no hay ninguna que lo
  // sea por etiqueta o por artista: es una pista floja.
  if (p.generos.isNotEmpty) {
    final List<Genero> pedidos = <Genero>[for (final String n in p.generos) ?generoDe(n)];
    final bool hayDeVerdad = datos.canciones.any((Elemento e) => pedidos.any((Genero g) => puntos(e, g) >= 3));
    if (!hayDeVerdad) {
      minimoGenero = 1;
      avisos.add('Elegidas por ritmo parecido');
    }
  }
  List<Elemento> salen = intento();
  // Relajar nunca deja la peticion sin nada: si lo unico pedido era un
  // genero o un ritmo, mejor no dar nada y ofrecer buscarlo en internet.
  final bool hayMasFiltros = p.artistas.isNotEmpty ||
      p.sinArtistas.isNotEmpty ||
      p.favoritas ||
      p.sinEscuchar ||
      p.minEscuchas != null ||
      p.calidad != null ||
      p.anioMin != null;
  final bool conDuracion = p.duracionMin != null || p.duracionMax != null || p.dias != null;
  // Si no sale nada, se relaja por pasos, de lo menos a lo mas concreto.
  final List<(String, bool Function())> pasos = <(String, bool Function())>[
    (
      'Energia mas abierta',
      () {
        if (eMin == null && eMax == null) return false;
        eMin = eMin == null ? null : max(0, eMin! - .15);
        eMax = eMax == null ? null : min(1, eMax! + .15);
        return true;
      },
    ),
    (
      'Tempo mas abierto',
      () {
        if (bMin == null && bMax == null) return false;
        bMin = bMin == null ? null : bMin! * .9;
        bMax = bMax == null ? null : bMax! * 1.1;
        return true;
      },
    ),
    (
      'Sin mirar el ritmo',
      () {
        if (eMin == null && eMax == null && bMin == null && bMax == null) return false;
        if (!hayMasFiltros && p.generos.isEmpty && !conDuracion) return false;
        eMin = eMax = bMin = bMax = null;
        return true;
      },
    ),
    (
      'Sin el genero',
      () {
        if (p.generos.isEmpty || !conGenero) return false;
        if (!hayMasFiltros && !conDuracion) return false;
        conGenero = false;
        return true;
      },
    ),
    (
      'Sin la duracion ni la fecha',
      () {
        if (!conDuracionYFecha || !conDuracion || !hayMasFiltros) return false;
        conDuracionYFecha = false;
        return true;
      },
    ),
  ];
  final int faltabanAntes = sinAnalizar;
  for (final (String aviso, bool Function() relajar) in pasos) {
    if (salen.isNotEmpty) break;
    if (!relajar()) continue;
    avisos.add(aviso);
    salen = intento();
  }

  salen = ordenarPeticion(p, salen, datos, azar: azar);
  return Respuesta(
    pistas: salen,
    avisos: avisos,
    sinAnalizar: p.pideRitmo ? max(faltabanAntes, sinAnalizar) : 0,
  );
}

/// Ordena y corta lo que salio segun lo pedido.
List<Elemento> ordenarPeticion(Peticion p, List<Elemento> pistas, DatosBiblioteca datos, {Random? azar}) {
  List<Elemento> orden = List<Elemento>.of(pistas);
  switch (p.orden) {
    case OrdenPeticion.masEscuchadas:
      orden.sort((Elemento a, Elemento b) =>
          (datos.escuchas[b.uri]?.veces ?? 0).compareTo(datos.escuchas[a.uri]?.veces ?? 0));
    case OrdenPeticion.recientes:
      orden.sort((Elemento a, Elemento b) => b.fecha.compareTo(a.fecha));
    case OrdenPeticion.aleatorio:
      orden.shuffle(azar ?? Random());
    case OrdenPeticion.tal:
      break;
    case OrdenPeticion.dj:
    case OrdenPeticion.subir:
    case OrdenPeticion.bajar:
    case OrdenPeticion.arco:
      // Primero se corta (al azar, para no dar siempre las mismas) y luego se
      // ordena: una hora de fiesta tiene que tener su subida entera.
      if (p.limite != null || p.minutos != null) {
        orden.shuffle(azar ?? Random());
        orden = _cortar(p, orden);
      }
      return Dj.ordenarElementos(
        orden,
        rasgos: (String uri) => datos.rasgos[uri],
        modo: p.modoDj!,
        azar: azar,
      );
  }
  return _cortar(p, orden);
}

List<Elemento> _cortar(Peticion p, List<Elemento> pistas) {
  List<Elemento> salida = pistas;
  if (p.limite != null && salida.length > p.limite!) salida = salida.take(p.limite!).toList();
  if (p.minutos != null) {
    final double objetivo = p.minutos! * 60.0;
    double suma = 0;
    final List<Elemento> hasta = <Elemento>[];
    for (final Elemento e in salida) {
      if (suma >= objetivo) break;
      hasta.add(e);
      suma += e.duracion;
    }
    salida = hasta;
  }
  return salida;
}

/// Ejemplos para la pastilla y la pantalla, segun la hora.
List<String> ejemplosPara(DateTime ahora) {
  final int h = ahora.hour;
  if (h < 6) return <String>['algo tranquilo para dormir', 'lofi de una hora', 'baladas de los 80'];
  if (h < 12) return <String>['algo animado para empezar', 'lo que baje este mes', 'salsa para cocinar'];
  if (h < 18) return <String>['algo para concentrarme', 'reggaeton pa entrenar', 'mis favoritas sin perdida'];
  return <String>['una hora de cumbia para el tono', 'fiesta sin reggaeton', 'algo tranquilo para cocinar'];
}
