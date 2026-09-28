import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
  Fuente _fuente = Fuente.youtube;

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

  Future<void> _buscar(String texto) async {
    FocusScope.of(context).unfocus();
    _control.limpiarMensaje();
    setState(() {
      _buscandoAhora = true;
      _aviso = '';
      _fallo = false;
      _resultados = <Resultado>[];
    });
    try {
      final List<Resultado> encontrados = await Nucleo.buscar(texto, fuente: _fuente.clave);
      if (!mounted) return;
      setState(() {
        _resultados = encontrados;
        _importada = false;
        if (encontrados.isEmpty) {
          _aviso = 'Nada para «$texto» en ${_fuente.etiqueta}. '
              'Prueba con menos palabras o busca en otra fuente.';
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
        QueSeDescarga(titulo: r.titulo, subtitulo: r.autor, miniatura: r.miniatura),
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

  Future<void> _importarLista(String url) async {
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
        _resultados = lista.pistas;
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
  Widget _fuentes() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          const Text('Buscar en', style: TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(width: 8),
          for (final Fuente f in Fuente.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                selected: _fuente == f,
                label: Text(f.etiqueta, style: const TextStyle(fontSize: 12)),
                tooltip: f.pista,
                selectedColor: Tema.acento.withValues(alpha: 0.25),
                backgroundColor: Tema.superficie,
                onSelected: _ocupado
                    ? null
                    : (_) => setState(() {
                          _fuente = f;
                          // Lo encontrado en otra fuente ya no viene al caso.
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
    if (_buscandoAhora) {
      return CargandoMusica(
        texto: _entrada.tipo == TipoEntrada.busqueda ? 'Buscando...' : 'Trayendo la lista...',
      );
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

  Widget _lista() {
    // Un resultado del Archive es un concierto entero: se abre, no se baja.
    final bool sonGrabaciones = _fuente.daListas && !_importada;
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _resultados.length,
      itemBuilder: (BuildContext context, int i) {
        final Resultado r = _resultados[i];
        return _TarjetaResultado(
          resultado: r,
          esGrabacion: sonGrabaciones,
          alPulsar: _ocupado
              ? null
              : () => sonGrabaciones ? _importarLista(r.url) : _descargarResultado(r),
          alEscuchar: () => _escuchar(r),
        );
      },
    );
  }
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
  });

  final Resultado resultado;

  /// Si al tocarlo se abren sus pistas en vez de bajarse de una pieza.
  final bool esGrabacion;
  final VoidCallback? alPulsar;
  final VoidCallback alEscuchar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Tema.superficie,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: alPulsar,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: <Widget>[
                Stack(
                  children: <Widget>[
                    PortadaRemota(url: resultado.miniatura),
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
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Escuchar sin descargar',
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
