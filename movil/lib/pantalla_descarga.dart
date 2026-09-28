import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'busqueda.dart';
import 'calidad.dart';
import 'cargando.dart';
import 'control_descarga.dart';
import 'entrada.dart';
import 'estado_reproductor.dart';
import 'formato.dart';
import 'hoja_descarga.dart';
import 'nucleo.dart';
import 'pantalla_previa.dart';
import 'portadas.dart';
import 'tema.dart';

/// Pantalla principal: un solo campo para buscar o pegar un enlace.
///
/// Sigue el patron de la barra del navegador: la app decide por lo escrito si
/// es una busqueda o un enlace, y lo dice debajo del campo antes de pulsar
/// nada. Como bajarlo (musica o video) se pregunta justo al descargar, con lo
/// que se va a bajar delante, en vez de estar fijo arriba de la pantalla.
class PantallaDescarga extends StatefulWidget {
  const PantallaDescarga({super.key});

  @override
  State<PantallaDescarga> createState() => PantallaDescargaState();
}

class PantallaDescargaState extends State<PantallaDescarga> {
  final TextEditingController _campo = TextEditingController();
  final FocusNode _foco = FocusNode();
  final ControlDescarga _control = ControlDescarga.instancia;
  final EstadoReproductor _reproductor = EstadoReproductor.instancia;

  List<Resultado> _resultados = <Resultado>[];
  bool _buscandoAhora = false;
  bool _importada = false;
  String _nombreLista = '';
  String _aviso = '';
  bool _fallo = false;
  Fuente _fuente = Fuente.todas;

  /// Lo que se busco la ultima vez, para saber que resultados son la cancion.
  String _buscado = '';

  /// Fuentes a las que aun se esta preguntando.
  final Set<Fuente> _pendientes = <Fuente>{};

  /// Las que no respondieron, con el porque.
  final Map<Fuente, String> _sinRespuesta = <Fuente, String>{};

  /// Cada busqueda nueva deja atras lo que aun llegara de la anterior: sin
  /// esto, una respuesta lenta de antes se colaba entre los resultados nuevos.
  int _busqueda = 0;

  /// Lo ya buscado en esta sesion. Repetir una busqueda es instantaneo.
  static final Map<String, List<Resultado>> _recuerdo = <String, List<Resultado>>{};

  /// Lo que se sabe de cada resultado tras comprobarlo, por enlace.
  ///
  /// Sobrevive a la busqueda: si el mismo tema vuelve a salir, ya se sabe.
  static final Map<String, _Comprobacion> _comprobadas = <String, _Comprobacion>{};

  /// Cuantos resultados se comprueban de cada fuente, empezando por arriba.
  ///
  /// De YouTube basta uno: su calidad es siempre la misma (medido, Opus a
  /// unos 127 kb/s) y solo hace falta saber que se deja bajar. En SoundCloud
  /// se miran mas, porque lo de los sellos grandes viene con DRM y no se puede
  /// bajar, y lo que no lo lleva llega a AAC 160 kb/s, mejor que YouTube.
  static const Map<Fuente, int> _aComprobar = <Fuente, int>{
    Fuente.youtube: 1,
    Fuente.soundcloud: 3,
  };

  /// Para las pruebas: lo recordado de una no puede decidir la siguiente.
  @visibleForTesting
  static void olvidarBusquedas() {
    _recuerdo.clear();
    _comprobadas.clear();
  }

  /// El Archive solo devuelve grabaciones con FLAC: su calidad ya se sabe.
  static const CalidadAudio _flac = CalidadAudio(codec: 'flac');

  /// Lo que esta mal de lo escrito, debajo del campo.
  ///
  /// Solo aparece al pulsar el boton y se va al volver a escribir: avisar
  /// mientras aun se esta tecleando es reganar por algo a medio hacer.
  String? _errorCampo;

  Entrada get _entrada => Entrada.de(_campo.text);

  bool get _ocupado => _control.activa || _buscandoAhora;

  @override
  void initState() {
    super.initState();
    _control.addListener(_refrescar);
    _reproductor.addListener(_vigilarReproductor);
    Nucleo.enlaceCompartido.addListener(_alRecibirEnlace);
    // Si la pantalla nace precisamente porque se compartio algo, ya esta ahi.
    _alRecibirEnlace();
    // Quien abre Descargar va a buscar: se carga el motor mientras escribe.
    unawaited(Nucleo.precalentar());
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  /// Un fallo del reproductor se avisa de paso y sin ocupar la pantalla:
  /// la vista previa ya tiene su propio motor y muestra los suyos aparte.
  void _vigilarReproductor() {
    final String? fallo = _reproductor.consumirError();
    if (fallo == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('No se pudo reproducir: $fallo'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// Se atiende tras pintar: la hoja necesita la pantalla ya construida, y asi
  /// el salto de pestania se ve antes de que suba.
  void _alRecibirEnlace() {
    if (Nucleo.enlaceCompartido.value == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _atenderCompartido());
  }

  /// Un enlace compartido desde otra app va directo a como bajarlo.
  ///
  /// Quien comparte a la app ya dijo lo que quiere: hacerle pulsar ademas
  /// «Descargar» seria un paso de mas.
  Future<void> _atenderCompartido() async {
    final String? enlace = Nucleo.enlaceCompartido.value;
    if (enlace == null || !mounted) return;
    Nucleo.enlaceCompartido.value = null;
    _poner(enlace);
    final Entrada e = _entrada;
    if (e.tipo == TipoEntrada.enlace) await _descargarEnlace(e);
    if (e.tipo == TipoEntrada.lista) await _importarLista(e.url);
    // Un nombre compartido (desde las notas, un chat...) se busca sin mas.
    if (e.tipo == TipoEntrada.busqueda) await _buscar(e.texto);
  }

  /// Deja un texto en el campo como si se hubiera escrito.
  void _poner(String texto) {
    _campo.value = TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
    setState(() => _errorCampo = null);
  }

  /// Pega lo copiado. Solo se lee el portapapeles al pulsar: leerlo solo, al
  /// abrir la app, seria mirar lo que el usuario copio sin que lo pidiera.
  Future<void> _pegar() async {
    final ClipboardData? datos = await Clipboard.getData(Clipboard.kTextPlain);
    final String texto = datos?.text?.trim() ?? '';
    if (!mounted) return;
    if (texto.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No hay nada copiado. Copia el enlace en su app y vuelve.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _poner(texto);
  }

  /// Lo que hace el boton grande, segun lo escrito.
  Future<void> _continuar() async {
    final Entrada e = _entrada;
    switch (e.tipo) {
      case TipoEntrada.vacia:
        setState(() => _errorCampo = 'Escribe el nombre de una cancion o pega un enlace.');
        _foco.requestFocus();
      case TipoEntrada.enlaceRoto:
        setState(() => _errorCampo =
            'Ese enlace esta incompleto. Copialo otra vez desde la app donde lo viste.');
      case TipoEntrada.busqueda:
        await _buscar(e.texto);
      case TipoEntrada.lista:
        await _importarLista(e.url);
      case TipoEntrada.enlace:
        await _descargarEnlace(e);
    }
  }

  /// Busca en una fuente o en todas a la vez.
  ///
  /// Con todas, se pregunta a cada una en paralelo y se ensenia lo que llega
  /// segun llega: la espera es la de la mas lenta, no la suma, y lo primero
  /// aparece en cuanto responde la mas rapida.
  Future<void> _buscar(String texto) async {
    FocusScope.of(context).unfocus();
    _control.limpiarMensaje();
    final int esta = ++_busqueda;
    final List<Fuente> donde = _fuente == Fuente.todas ? Fuente.reales : <Fuente>[_fuente];
    setState(() {
      _buscado = texto;
      _aviso = '';
      _fallo = false;
      _importada = false;
      _resultados = <Resultado>[];
      _sinRespuesta.clear();
      _pendientes
        ..clear()
        ..addAll(donde);
    });
    await Future.wait(donde.map((Fuente f) => _buscarEn(f, texto, esta)));
    if (!mounted || esta != _busqueda || _resultados.isNotEmpty) return;
    setState(() {
      _fallo = true;
      _aviso = _sinRespuesta.length == donde.length
          ? _sinRespuesta.values.first
          : _fuente == Fuente.todas
              ? 'Nada para «$texto» en ninguna fuente. Prueba con menos palabras.'
              : 'Nada para «$texto» en ${_fuente.etiqueta}. '
                  'Prueba con menos palabras o busca en todas.';
    });
  }

  Future<void> _buscarEn(Fuente f, String texto, int esta) async {
    final String clave = '${f.clave}|${texto.toLowerCase()}';
    try {
      final List<Resultado> encontrados = _recuerdo[clave] ??
          (await Nucleo.buscar(texto, fuente: f.clave))
              .map((Resultado r) => r.deFuente(f))
              .toList();
      _recuerdo[clave] = encontrados;
      if (!mounted || esta != _busqueda) return;
      setState(() {
        // Cada fuente en su sitio y siempre en el mismo orden: lo que llega
        // despues no empuja lo que ya se estaba leyendo.
        _resultados = <Resultado>[
          for (final Fuente g in Fuente.reales)
            ...(g == f ? encontrados : _resultados.where((Resultado r) => r.fuente == g)),
        ];
      });
      _comprobar(f, encontrados, texto);
    } catch (error) {
      if (mounted && esta == _busqueda) {
        setState(() => _sinRespuesta[f] = error is ErrorNucleo ? error.mensaje : '$error');
      }
    } finally {
      if (mounted && esta == _busqueda) setState(() => _pendientes.remove(f));
    }
  }

  /// Comprueba de verdad los mejores candidatos, sin bajarlos.
  ///
  /// Pregunta por cada uno lo mismo que preguntaria la descarga: que audio
  /// llegaria y si se deja bajar. Asi la «mejor calidad» no es una suposicion
  /// por la fuente, y lo que tiene DRM se sabe antes de intentarlo.
  void _comprobar(Fuente f, List<Resultado> encontrados, String texto) {
    final int cuantos = _aComprobar[f] ?? 0;
    final Iterable<Resultado> candidatos = encontrados
        .where((Resultado r) => pareceLaMisma(texto, titulo: r.titulo, autor: r.autor))
        .take(cuantos);
    for (final Resultado r in candidatos) {
      if (_comprobadas.containsKey(r.url)) continue;
      _comprobadas[r.url] = const _Comprobacion.enCurso();
      Nucleo.calidad(r.url).then(
        (CalidadAudio c) => _comprobado(r.url, _Comprobacion.hecha(c)),
        onError: (Object e) =>
            _comprobado(r.url, _Comprobacion.fallida(e is ErrorNucleo ? e.mensaje : '$e')),
      );
    }
    if (mounted) setState(() {});
  }

  void _comprobado(String url, _Comprobacion resultado) {
    _comprobadas[url] = resultado;
    if (mounted) setState(() {});
  }

  /// La calidad que se sabe de un resultado, comprobada o conocida de antes.
  CalidadAudio? _calidadDe(Resultado r) =>
      r.fuente == Fuente.archive ? _flac : _comprobadas[r.url]?.calidad;

  /// El resultado comprobado con mejor calidad que sea la cancion buscada.
  ///
  /// Los conciertos del Archive quedan fuera: son sin perdida, pero son un
  /// concierto entero, no la cancion que se busco.
  Resultado? get _mejor {
    Resultado? mejor;
    CalidadAudio? suya;
    for (final Resultado r in _resultados) {
      if (r.fuente == Fuente.archive) continue;
      final CalidadAudio? c = _comprobadas[r.url]?.calidad;
      if (c == null || !pareceLaMisma(_buscado, titulo: r.titulo, autor: r.autor)) continue;
      if (suya == null || c.mejorQue(suya)) {
        mejor = r;
        suya = c;
      }
    }
    return mejor;
  }

  /// Pregunta como bajarlo y, si se confirma, lo baja.
  Future<void> _descargar(String url, QueSeDescarga que) async {
    FocusScope.of(context).unfocus();
    final Ajustes? elegidos =
        await preguntarComoDescargar(context, que: que, ajustes: _control.ajustes);
    if (elegidos == null || !mounted) return;
    _control.cambiarAjustes(elegidos);
    setState(() {
      _aviso = '';
      _fallo = false;
    });
    await _control.iniciar(url);
  }

  Future<void> _descargarEnlace(Entrada e) => _descargar(
        e.url,
        QueSeDescarga(titulo: 'Enlace de ${e.sitio}', subtitulo: e.url),
      );

  Future<void> _descargarResultado(Resultado r) => _descargar(
        r.url,
        QueSeDescarga(
          titulo: r.titulo,
          subtitulo: r.autor,
          miniatura: r.miniatura,
          origen: _calidadDe(r),
        ),
      );

  /// Baja la lista entera. Al terminar se recrea en la app con su nombre.
  Future<void> _descargarTodo() async {
    final Ajustes? elegidos = await preguntarComoDescargar(
      context,
      que: QueSeDescarga(
        titulo: _nombreLista.isEmpty ? 'La lista entera' : _nombreLista,
        subtitulo: '${_resultados.length} pistas',
        miniatura: _resultados.first.miniatura,
        cantidad: _resultados.length,
      ),
      ajustes: _control.ajustes,
    );
    if (elegidos == null || !mounted) return;
    _control.cambiarAjustes(elegidos);
    await _control.iniciarVarios(
      _resultados.map((Resultado r) => r.url).toList(),
      nombreLista: _nombreLista,
    );
  }

  /// Abre la vista previa, que reproduce el video de verdad.
  ///
  /// Antes de irse calla lo que sonara de la biblioteca: dos audios a la vez
  /// no se entienden.
  Future<void> _escuchar(Resultado resultado) async {
    _control.limpiarMensaje();
    // Sin esperar: abrir la pantalla no depende de que el audio anterior
    // termine de pararse, y si eso tardara se quedaria el toque sin respuesta.
    unawaited(_reproductor.cerrar());
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PantallaPrevia(resultado: resultado)),
    );
  }

  /// Trae las pistas de una lista. [fuente] marca de donde son, si se sabe.
  Future<void> _importarLista(String url, {Fuente? fuente}) async {
    FocusScope.of(context).unfocus();
    _control.limpiarMensaje();
    setState(() {
      _buscandoAhora = true;
      _aviso = '';
      _fallo = false;
      _resultados = <Resultado>[];
    });
    try {
      final ListaTraida lista = await Nucleo.importarLista(url);
      if (!mounted) return;
      setState(() {
        _resultados = fuente == null
            ? lista.pistas
            : lista.pistas.map((Resultado r) => r.deFuente(fuente)).toList();
        _importada = lista.pistas.isNotEmpty;
        _nombreLista = lista.titulo;
        if (lista.pistas.isEmpty) {
          _aviso = 'Esa lista esta vacia.';
          _fallo = true;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _aviso = '$error';
          _fallo = true;
        });
      }
    } finally {
      if (mounted) setState(() => _buscandoAhora = false);
    }
  }

  @override
  void dispose() {
    Nucleo.enlaceCompartido.removeListener(_alRecibirEnlace);
    _control.removeListener(_refrescar);
    _reproductor.removeListener(_vigilarReproductor);
    _campo.dispose();
    _foco.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Entrada e = _entrada;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _campoEntrada(e),
              const SizedBox(height: 6),
              _queVaAPasar(e),
              const SizedBox(height: 12),
              if (_control.activa)
                _TarjetaProgreso(
                  porcentaje: _control.porcentaje,
                  estado: _control.estado,
                  lote: _control.progresoLote,
                  alCancelar: _control.enLote && !_control.cancelando
                      ? _control.cancelar
                      : null,
                )
              else
                BotonDegradado(
                  texto: switch (e.tipo) {
                    TipoEntrada.lista => 'Ver la lista',
                    TipoEntrada.enlace || TipoEntrada.enlaceRoto => 'Descargar',
                    TipoEntrada.vacia || TipoEntrada.busqueda => 'Buscar',
                  },
                  icono: switch (e.tipo) {
                    TipoEntrada.lista => Icons.queue_music_rounded,
                    TipoEntrada.enlace || TipoEntrada.enlaceRoto => Icons.arrow_downward_rounded,
                    TipoEntrada.vacia || TipoEntrada.busqueda => Icons.search_rounded,
                  },
                  alPulsar: _ocupado ? null : _continuar,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(child: _cuerpo()),
      ],
    );
  }

  Widget _campoEntrada(Entrada e) {
    return TextField(
      controller: _campo,
      focusNode: _foco,
      textInputAction: e.esEnlace ? TextInputAction.go : TextInputAction.search,
      onSubmitted: _ocupado ? null : (_) => _continuar(),
      onChanged: (_) => setState(() => _errorCampo = null),
      decoration: InputDecoration(
        hintText: 'Busca o pega un enlace',
        errorText: _errorCampo,
        errorMaxLines: 2,
        prefixIcon: Icon(e.esEnlace ? Icons.link_rounded : Icons.search_rounded),
        suffixIcon: _campo.text.isEmpty
            // Con el campo vacio, lo mas probable es venir con un enlace copiado.
            ? Padding(
                padding: const EdgeInsets.only(right: 6),
                child: TextButton.icon(
                  onPressed: _ocupado ? null : _pegar,
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('Pegar'),
                ),
              )
            : IconButton(
                tooltip: 'Borrar',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => _poner(''),
              ),
      ),
    );
  }

  /// Dice que va a pasar con lo escrito antes de pulsar nada.
  ///
  /// Era lo que faltaba: no se sabia si lo escrito se iba a buscar o a
  /// descargar hasta pulsar el boton y ver que salia.
  Widget _queVaAPasar(Entrada e) {
    return switch (e.tipo) {
      TipoEntrada.enlace => _Pista(
          icono: Icons.link_rounded,
          texto: 'Enlace de ${e.sitio}: se descarga lo que abre',
          accion: e.listaAparte.isEmpty
              ? null
              : TextButton(
                  onPressed: _ocupado ? null : () => _importarLista(e.listaAparte),
                  child: const Text('Ver la lista entera'),
                ),
        ),
      TipoEntrada.lista => _Pista(
          icono: Icons.queue_music_rounded,
          texto: 'Lista de ${e.sitio}: veras sus pistas antes de bajarlas',
        ),
      // Lo que sale mal se dice al pulsar, debajo del campo; aqui no se adelanta.
      TipoEntrada.enlaceRoto => const SizedBox.shrink(),
      TipoEntrada.vacia || TipoEntrada.busqueda => _fuentes(),
    };
  }

  /// Donde se busca. Solo tiene sentido buscando: un enlace ya dice de donde es.
  ///
  /// Compactas y sin la marca de elegida (ya lo dice el color): con «Todas»
  /// son cuatro, y en un telefono normal la ultima quedaba fuera de la vista.
  /// Se deja el desplazamiento por si la letra del sistema es grande.
  Widget _fuentes() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          for (final Fuente f in Fuente.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                selected: _fuente == f,
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                label: Text(f.etiqueta, style: const TextStyle(fontSize: 12)),
                tooltip: f.pista,
                selectedColor: Tema.acento.withValues(alpha: 0.25),
                backgroundColor: Tema.superficie,
                onSelected: _ocupado
                    ? null
                    : (_) => setState(() {
                          _fuente = f;
                          // Lo encontrado en otra fuente ya no viene al caso,
                          // ni lo que aun este por llegar de ella.
                          _busqueda++;
                          _pendientes.clear();
                          _sinRespuesta.clear();
                          _importada = false;
                          _resultados = <Resultado>[];
                        }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cuerpo() {
    if (_buscandoAhora) return const CargandoMusica(texto: 'Trayendo la lista...');
    // Mientras no llegue nada se espera; en cuanto llega algo, se ensenia.
    if (_pendientes.isNotEmpty && _resultados.isEmpty) {
      return CargandoMusica(texto: 'Buscando en ${_nombres(_pendientes)}...');
    }
    final String mensaje = _aviso.isNotEmpty ? _aviso : _control.mensaje;
    final bool fallo = _aviso.isNotEmpty ? _fallo : _control.fallo;
    if (mensaje.isNotEmpty && _resultados.isEmpty) {
      return _Aviso(
        mensaje: mensaje,
        fallo: fallo,
        detalle: _aviso.isNotEmpty ? const <String>[] : _control.detalle,
      );
    }
    if (_resultados.isEmpty) return const _Vacio();
    return Column(
      children: <Widget>[
        if (_importada) _barraLista(),
        Expanded(child: _lista()),
      ],
    );
  }

  /// Con una lista traida, lo normal es querer bajarla entera.
  Widget _barraLista() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '${_resultados.length} pistas · $_nombreLista',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          FilledButton.icon(
            onPressed: _ocupado ? null : _descargarTodo,
            icon: const Icon(Icons.download_for_offline_rounded, size: 18),
            label: const Text('Descargar todo'),
          ),
        ],
      ),
    );
  }

  static String _nombres(Iterable<Fuente> fuentes) {
    final List<String> n = fuentes.map((Fuente f) => f.etiqueta).toList();
    return n.length <= 1 ? n.join() : '${n.sublist(0, n.length - 1).join(', ')} y ${n.last}';
  }

  Widget _lista() {
    final Resultado? mejor = _importada ? null : _mejor;
    final bool variasFuentes = _fuente == Fuente.todas && !_importada;
    final List<Widget> filas = <Widget>[
      if (mejor != null)
        _MejorOpcion(
          titulo: mejor.titulo,
          fuente: mejor.fuente?.etiqueta ?? '',
          calidad: _calidadDe(mejor)!,
          alPulsar: _ocupado ? null : () => _descargarResultado(mejor),
        ),
      if (_pendientes.isNotEmpty)
        _Nota(icono: Icons.hourglass_top_rounded, texto: 'Aun buscando en ${_nombres(_pendientes)}...'),
      for (final MapEntry<Fuente, String> e in _sinRespuesta.entries)
        _Nota(icono: Icons.cloud_off_rounded, texto: '${e.key.etiqueta} no respondio: ${e.value}'),
    ];
    Fuente? anterior;
    for (final Resultado r in _resultados) {
      // Un resultado del Archive es un concierto entero: se abre, no se baja.
      final bool esGrabacion = (r.fuente ?? _fuente).daListas && !_importada;
      if (variasFuentes && r.fuente != anterior) {
        filas.add(_Seccion(texto: r.fuente?.etiqueta ?? ''));
        anterior = r.fuente;
      }
      filas.add(_TarjetaResultado(
        resultado: r,
        esGrabacion: esGrabacion,
        esLaMejor: identical(r, mejor),
        calidad: _calidadDe(r),
        comprobacion: _comprobadas[r.url],
        alPulsar: _ocupado
            ? null
            : () => esGrabacion
                ? _importarLista(r.url, fuente: r.fuente)
                : _descargarResultado(r),
        alEscuchar: () => _escuchar(r),
      ));
    }
    return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: filas);
  }
}

/// Lo que se sabe de un resultado tras comprobarlo.
class _Comprobacion {
  const _Comprobacion.enCurso()
      : calidad = null,
        error = null,
        enCurso = true;
  const _Comprobacion.hecha(CalidadAudio this.calidad)
      : error = null,
        enCurso = false;
  const _Comprobacion.fallida(String this.error)
      : calidad = null,
        enCurso = false;

  final CalidadAudio? calidad;
  final String? error;
  final bool enCurso;
}

/// Arriba de todo, la mejor opcion encontrada: un toque y a descargar.
class _MejorOpcion extends StatelessWidget {
  const _MejorOpcion({
    required this.titulo,
    required this.fuente,
    required this.calidad,
    required this.alPulsar,
  });

  /// Que cancion es: sin el, habia que bajar hasta su fuente para saberlo.
  final String titulo;
  final String fuente;
  final CalidadAudio calidad;
  final VoidCallback? alPulsar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Tema.acento.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: alPulsar,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            child: Row(
              children: <Widget>[
                const Icon(Icons.workspace_premium_rounded, color: Tema.acento),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        'Mejor calidad encontrada',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '«$titulo»',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      const SizedBox(height: 4),
                      // Wrap y no Row: con un sello largo, en un telefono
                      // estrecho, pasa a la linea de abajo en vez de salirse.
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 4,
                        children: <Widget>[
                          Text('En $fuente  ',
                              style: const TextStyle(color: Colors.white60, fontSize: 12)),
                          SelloCalidad(calidad: calidad),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.download_rounded, color: Tema.acento),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// El nombre de la fuente encima de sus resultados, buscando en todas.
class _Seccion extends StatelessWidget {
  const _Seccion({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
        child: Text(
          texto.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.1,
            color: Colors.white54,
          ),
        ),
      );
}

/// Una linea pequena de aviso entre los resultados.
class _Nota extends StatelessWidget {
  const _Nota({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Row(
          children: <Widget>[
            Icon(icono, size: 14, color: Colors.white38),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                texto,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          ],
        ),
      );
}

/// Una linea con lo que va a pasar, y a veces algo mas que se puede hacer.
class _Pista extends StatelessWidget {
  const _Pista({required this.icono, required this.texto, this.accion});

  final IconData icono;
  final String texto;
  final Widget? accion;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icono, size: 16, color: Tema.acento),
        const SizedBox(width: 8),
        Expanded(
          child: Text(texto, style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ),
        ?accion,
      ],
    );
  }
}

class _TarjetaResultado extends StatelessWidget {
  const _TarjetaResultado({
    required this.resultado,
    required this.esGrabacion,
    required this.alPulsar,
    required this.alEscuchar,
    this.esLaMejor = false,
    this.calidad,
    this.comprobacion,
  });

  final Resultado resultado;

  /// Si al tocarlo se abren sus pistas en vez de bajarse de una pieza.
  final bool esGrabacion;
  final VoidCallback? alPulsar;
  final VoidCallback alEscuchar;
  final bool esLaMejor;

  /// Lo que se sabe de su calidad, comprobado o conocido de antemano.
  final CalidadAudio? calidad;
  final _Comprobacion? comprobacion;

  /// Lo que se sabe de el, en una linea bajo el autor.
  Widget? _estado() {
    final _Comprobacion? c = comprobacion;
    if (c != null && c.enCurso) {
      return const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5)),
          SizedBox(width: 6),
          Text('comprobando calidad', style: TextStyle(color: Colors.white38, fontSize: 10)),
        ],
      );
    }
    if (c?.error != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.block_rounded, size: 12, color: Color(0xFFFF6B81)),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              c!.error!.toLowerCase().contains('protegida') ? 'Protegida: no se puede bajar' : 'No se puede bajar',
              style: const TextStyle(color: Color(0xFFFF6B81), fontSize: 10),
            ),
          ),
        ],
      );
    }
    final CalidadAudio? q = calidad;
    return q == null ? null : SelloCalidad(calidad: q);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: esLaMejor ? Tema.acento.withValues(alpha: 0.10) : Tema.superficie,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: esLaMejor ? const BorderSide(color: Tema.acento, width: 1.2) : BorderSide.none,
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: alPulsar,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: <Widget>[
                Stack(
                  children: <Widget>[
                    // Algo menor que la de siempre: con los dos botones, el
                    // titulo se quedaba en un hilo en un telefono normal.
                    PortadaRemota(url: resultado.miniatura, ancho: 104, alto: 60),
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          formatoTiempo(resultado.duracion),
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        resultado.titulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        esGrabacion
                            ? 'Grabacion completa · toca para ver sus pistas'
                            : resultado.autor,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                      if (_estado() case final Widget estado) ...<Widget>[
                        const SizedBox(height: 6),
                        estado,
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Escuchar sin descargar',
                  visualDensity: VisualDensity.compact,
                  onPressed: alEscuchar,
                  icon: const Icon(
                    Icons.play_circle_outline_rounded,
                    size: 30,
                    color: Colors.white60,
                  ),
                ),
                // Lo mismo que tocar la tarjeta, pero a la vista: sin el no se
                // adivinaba que tocarla era la forma de bajarla.
                IconButton(
                  tooltip: esGrabacion ? 'Ver sus pistas' : 'Descargar',
                  visualDensity: VisualDensity.compact,
                  onPressed: alPulsar,
                  icon: Icon(
                    esGrabacion ? Icons.chevron_right_rounded : Icons.download_rounded,
                    size: 26,
                    color: Tema.acento,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TarjetaProgreso extends StatelessWidget {
  const _TarjetaProgreso({
    required this.porcentaje,
    required this.estado,
    this.lote = '',
    this.alCancelar,
  });

  final double? porcentaje;
  final String estado;
  final String lote;
  final VoidCallback? alCancelar;

  @override
  Widget build(BuildContext context) {
    final String etiqueta =
        porcentaje == null ? '--' : '${(porcentaje! * 100).toStringAsFixed(0)}%';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Tema.superficieAlta,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 46,
            height: 46,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                CircularProgressIndicator(
                  value: porcentaje,
                  strokeWidth: 4,
                  backgroundColor: Colors.white12,
                ),
                Text(etiqueta, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  lote.isEmpty ? 'Descargando' : 'Descargando $lote',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(estado, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
          if (alCancelar != null)
            TextButton(onPressed: alCancelar, child: const Text('Parar')),
        ],
      ),
    );
  }
}

class _Aviso extends StatefulWidget {
  const _Aviso({
    required this.mensaje,
    required this.fallo,
    this.detalle = const <String>[],
  });

  final String mensaje;
  final bool fallo;

  /// Lo que apunto el motor, para cuando el mensaje no basta.
  final List<String> detalle;

  @override
  State<_Aviso> createState() => _AvisoState();
}

class _AvisoState extends State<_Aviso> {

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: widget.fallo ? const Color(0x33FF6B81) : const Color(0x3357D9A3),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(widget.fallo
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded),
                const SizedBox(width: 10),
                Text(
                  widget.fallo ? 'Algo fallo' : 'Listo',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(widget.mensaje, style: const TextStyle(fontSize: 12, height: 1.4)),
            DetalleMotor(lineas: widget.detalle),
          ],
        ),
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 12, 28, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.travel_explore_rounded, size: 48, color: Colors.white24),
          const SizedBox(height: 14),
          Text('Dos formas de encontrar algo', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 14),
          const _Forma(
            icono: Icons.search_rounded,
            texto: 'Escribe una cancion, un artista o un video, y elige donde buscar.',
          ),
          const _Forma(
            icono: Icons.link_rounded,
            texto: 'Pega un enlace de YouTube, TikTok, Instagram, SoundCloud...',
          ),
          const _Forma(
            icono: Icons.share_rounded,
            texto: 'O desde su app: Compartir y elige Tumbao. Se abre listo para bajar.',
          ),
        ],
      ),
    );
  }
}

class _Forma extends StatelessWidget {
  const _Forma({required this.icono, required this.texto});

  final IconData icono;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icono, size: 20, color: Colors.white38),
          const SizedBox(width: 12),
          Expanded(
            child: Text(texto, style: const TextStyle(color: Colors.white54, height: 1.4)),
          ),
        ],
      ),
    );
  }
}


/// Lo que apunto el motor, plegado hasta que se pide.
///
/// Hace falta que se vea en pantalla y no solo en el registro del sistema:
/// hay telefonos (los MIUI, por ejemplo) que filtran lo que escriben las apps,
/// y entonces no hay forma de saber que respondio la web.
class DetalleMotor extends StatefulWidget {
  const DetalleMotor({required this.lineas, super.key});

  /// Cuantas lineas del final se ensenian. Las de antes son el arranque del
  /// motor y solo estorban.
  static const int ultimas = 40;

  /// Arranques del motor que no dicen nada de por que fallo.
  ///
  /// El volcado de parametros es una sola linea de miles de caracteres: si se
  /// deja, llena la pantalla entera y empuja el error fuera de la vista, que
  /// es justo lo unico que se venia a leer.
  static const List<String> _ruido = <String>[
    '[debug] params:',
    '[debug] Encodings:',
    '[debug] Python',
    '[debug] exe versions:',
    '[debug] Optional libraries:',
    '[debug] Proxy map:',
    '[debug] Request Handlers:',
    '[debug] Loaded ',
    '[debug] Plugin directories:',
  ];

  @visibleForTesting
  static List<String> limpiar(List<String> lineas) => lineas
      .where((String l) => !_ruido.any(l.trimLeft().startsWith))
      .toList();

  final List<String> lineas;

  @override
  State<DetalleMotor> createState() => _DetalleMotorState();
}

class _DetalleMotorState extends State<DetalleMotor> {
  bool _abierto = false;

  String get _texto {
    final List<String> utiles = DetalleMotor.limpiar(widget.lineas);
    final List<String> ultimas = utiles.length > DetalleMotor.ultimas
        ? utiles.sublist(utiles.length - DetalleMotor.ultimas)
        : utiles;
    return ultimas.join(String.fromCharCode(10));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.lineas.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 6),
        GestureDetector(
          onTap: () => setState(() => _abierto = !_abierto),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                _abierto ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                size: 18,
                color: Colors.white54,
              ),
              const Text(
                'Ver detalle tecnico',
                style: TextStyle(fontSize: 11, color: Colors.white54),
              ),
            ],
          ),
        ),
        if (_abierto)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(12),
            ),
            child: SelectableText(
              _texto,
              style: const TextStyle(fontSize: 9, height: 1.3, color: Colors.white60),
            ),
          ),
      ],
    );
  }
}
