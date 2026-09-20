import 'dart:async';

import 'package:flutter/material.dart';

import 'control_descarga.dart';
import 'estado_reproductor.dart';
import 'formato.dart';
import 'hoja_ajustes.dart';
import 'nucleo.dart';
import 'pantalla_previa.dart';
import 'portadas.dart';
import 'tema.dart';

/// Pantalla principal: buscar o pegar una URL, ajustar y descargar.
class PantallaDescarga extends StatefulWidget {
  const PantallaDescarga({super.key});

  @override
  State<PantallaDescarga> createState() => PantallaDescargaState();
}

class PantallaDescargaState extends State<PantallaDescarga> with WidgetsBindingObserver {
  final TextEditingController _entrada = TextEditingController();
  final ControlDescarga _control = ControlDescarga.instancia;
  final EstadoReproductor _reproductor = EstadoReproductor.instancia;

  bool _buscando = true;
  List<Resultado> _resultados = <Resultado>[];
  Resultado? _elegido;
  bool _buscandoAhora = false;
  bool _importada = false;
  String _aviso = '';
  bool _fallo = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _control.addListener(_refrescar);
    _reproductor.addListener(_vigilarReproductor);
    _recogerCompartido();
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  /// Si falla escuchar una vista previa hay que decirlo: antes se quedaba
  /// callado y parecia que el boton no hacia nada.
  void _vigilarReproductor() {
    final String? fallo = _reproductor.consumirError();
    if (fallo == null || !mounted) return;
    setState(() {
      _aviso = 'No se pudo reproducir la vista previa.\n\n$fallo';
      _fallo = true;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _recogerCompartido();
  }

  /// Un enlace compartido desde YouTube llega con la app ya abierta.
  Future<void> _recogerCompartido() async {
    final String? enlace = await Nucleo.urlCompartida();
    if (enlace == null || enlace.isEmpty || !mounted) return;
    setState(() {
      _buscando = false;
      _entrada.text = enlace;
      _elegido = null;
      _resultados = <Resultado>[];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Enlace recibido desde otra app'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _buscar() async {
    final String texto = _texto;
    if (texto.isEmpty) return;
    // Buscar un enlace no tiene sentido; se hace lo que el enlace pide.
    if (_esEnlace) {
      await _accionPrincipal();
      return;
    }
    FocusScope.of(context).unfocus();
    _control.limpiarMensaje();
    setState(() {
      _buscandoAhora = true;
      _aviso = '';
      _fallo = false;
      _resultados = <Resultado>[];
    });
    try {
      final List<Resultado> encontrados = await Nucleo.buscar(texto);
      if (!mounted) return;
      setState(() {
        _resultados = encontrados;
        _importada = false;
        if (encontrados.isEmpty) {
          _aviso = 'Sin resultados.';
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

  Future<void> _descargar() async {
    final String url = _elegido?.url ?? _entrada.text.trim();
    if (url.isEmpty) {
      setState(() {
        _aviso = 'Elige un resultado o pega una URL.';
        _fallo = true;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _aviso = '';
      _fallo = false;
    });
    await _control.iniciar(url);
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

  Future<void> _abrirAjustes() async {
    final Ajustes? nuevos = await showModalBottomSheet<Ajustes>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tema.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => HojaAjustes(inicial: _control.ajustes),
    );
    if (nuevos != null) _control.cambiarAjustes(nuevos);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _control.removeListener(_refrescar);
    _reproductor.removeListener(_vigilarReproductor);
    _entrada.dispose();
    super.dispose();
  }

  bool get _ocupado => _control.activa || _buscandoAhora;

  String get _texto => _entrada.text.trim();

  bool get _esEnlace => _texto.startsWith('http');

  /// Un enlace de lista se reconoce por llevar list= o /playlist.
  ///
  /// A proposito no mira en que modo estamos: pegar el enlace en el buscador
  /// es lo natural, y obligar a cambiar antes de modo no hay quien lo adivine.
  bool get _esLista =>
      _esEnlace && (_texto.contains('list=') || _texto.contains('/playlist'));

  Future<void> _descargarTodo() async {
    final List<String> urls = _resultados.map((Resultado r) => r.url).toList();
    await _control.iniciarVarios(urls);
  }

  /// Lo que hace el boton grande segun lo que haya escrito.
  Future<void> _accionPrincipal() => _esLista ? _importarLista() : _descargar();

  Future<void> _importarLista() async {
    FocusScope.of(context).unfocus();
    _control.limpiarMensaje();
    setState(() {
      _buscandoAhora = true;
      _aviso = '';
      _fallo = false;
      _resultados = <Resultado>[];
    });
    try {
      final List<Resultado> pistas = await Nucleo.importarLista(_texto);
      if (!mounted) return;
      setState(() {
        _resultados = pistas;
        _importada = pistas.isNotEmpty;
        if (pistas.isEmpty) {
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
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Descargar', style: Theme.of(context).textTheme.displaySmall),
              const SizedBox(height: 16),
              _buscador(),
              const SizedBox(height: 14),
              _controles(),
              const SizedBox(height: 14),
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
                  texto: _esLista
                      ? 'Traer la lista'
                      : (_elegido == null ? 'Descargar' : 'Descargar seleccion'),
                  icono: _esLista
                      ? Icons.playlist_add_rounded
                      : Icons.arrow_downward_rounded,
                  alPulsar: _ocupado ? null : _accionPrincipal,
                ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        Expanded(child: _cuerpo()),
      ],
    );
  }

  Widget _buscador() {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _entrada,
            textInputAction: _buscando ? TextInputAction.search : TextInputAction.done,
            onSubmitted: _ocupado
                ? null
                // Un enlace nunca se busca: se descarga o se trae entero.
                : (_) => (_buscando && !_esEnlace) ? _buscar() : _accionPrincipal(),
            decoration: InputDecoration(
              hintText: _buscando ? 'Busca una cancion o video' : 'Pega la URL',
              prefixIcon: Icon(_buscando ? Icons.search_rounded : Icons.link_rounded),
              suffixIcon: _entrada.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => setState(_entrada.clear),
                    ),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        const SizedBox(width: 10),
        // Alternar entre buscar por nombre y pegar un enlace.
        IconButton.filledTonal(
          onPressed: _ocupado
              ? null
              : () => setState(() {
                    _buscando = !_buscando;
                    _elegido = null;
                    _resultados = <Resultado>[];
                  }),
          tooltip: _buscando ? 'Usar una URL' : 'Buscar por nombre',
          icon: Icon(_buscando ? Icons.link_rounded : Icons.search_rounded),
        ),
      ],
    );
  }

  Widget _controles() {
    return Row(
      children: <Widget>[
        Expanded(
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            style: ButtonStyle(
              shape: WidgetStateProperty.all(
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
            ),
            segments: const <ButtonSegment<bool>>[
              ButtonSegment<bool>(
                value: false,
                label: Text('Video'),
                icon: Icon(Icons.movie_outlined, size: 18),
              ),
              ButtonSegment<bool>(
                value: true,
                label: Text('Musica'),
                icon: Icon(Icons.music_note_outlined, size: 18),
              ),
            ],
            selected: <bool>{_control.ajustes.soloAudio},
            onSelectionChanged: _ocupado
                ? null
                : (Set<bool> e) =>
                    _control.cambiarAjustes(_control.ajustes.copiar(soloAudio: e.first)),
          ),
        ),
        const SizedBox(width: 10),
        IconButton.filledTonal(
          onPressed: _ocupado ? null : _abrirAjustes,
          tooltip: 'Opciones',
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
    );
  }

  Widget _cuerpo() {
    final String mensaje = _aviso.isNotEmpty ? _aviso : _control.mensaje;
    final bool fallo = _aviso.isNotEmpty ? _fallo : _control.fallo;
    if (mensaje.isNotEmpty && _resultados.isEmpty) {
      return _Aviso(mensaje: mensaje, fallo: fallo);
    }
    if (_resultados.isEmpty) {
      return _Vacio(buscando: _buscando);
    }
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
              '${_resultados.length} pistas en la lista',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
          FilledButton.icon(
            onPressed: _ocupado ? null : _descargarTodo,
            icon: const Icon(Icons.download_for_offline_rounded, size: 18),
            label: Text(
              _control.ajustes.soloAudio ? 'Todo en MP3' : 'Todo en video',
            ),
          ),
        ],
      ),
    );
  }

  Widget _lista() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _resultados.length,
      itemBuilder: (BuildContext context, int i) {
        final Resultado r = _resultados[i];
        return _TarjetaResultado(
          resultado: r,
          marcado: identical(r, _elegido),
          alPulsar: () => setState(() => _elegido = identical(r, _elegido) ? null : r),
          alEscuchar: () => _escuchar(r),
        );
      },
    );
  }
}

class _TarjetaResultado extends StatelessWidget {
  const _TarjetaResultado({
    required this.resultado,
    required this.marcado,
    required this.alPulsar,
    required this.alEscuchar,
  });

  final Resultado resultado;
  final bool marcado;
  final VoidCallback alPulsar;
  final VoidCallback alEscuchar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: marcado ? Tema.acento.withValues(alpha: 0.16) : Tema.superficie,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: marcado ? Tema.acento : Colors.transparent, width: 1.5),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: alPulsar,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: <Widget>[
                  Stack(
                    alignment: Alignment.center,
                    children: <Widget>[
                      PortadaRemota(url: resultado.miniatura),
                      if (marcado)
                        const DecoratedBox(
                          decoration: BoxDecoration(color: Colors.black54),
                          child: SizedBox(
                            width: 128,
                            height: 74,
                            child: Icon(Icons.check_circle_rounded, color: Tema.acento, size: 34),
                          ),
                        ),
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
                          resultado.autor,
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
                      size: 32,
                      color: Colors.white60,
                    ),
                  ),
                ],
              ),
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

class _Aviso extends StatelessWidget {
  const _Aviso({required this.mensaje, required this.fallo});

  final String mensaje;
  final bool fallo;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: fallo ? const Color(0x33FF6B81) : const Color(0x3357D9A3),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(fallo ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded),
                const SizedBox(width: 10),
                Text(
                  fallo ? 'Algo fallo' : 'Listo',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(mensaje, style: const TextStyle(fontSize: 12, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class _Vacio extends StatelessWidget {
  const _Vacio({required this.buscando});

  final bool buscando;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              buscando ? Icons.travel_explore_rounded : Icons.content_paste_rounded,
              size: 56,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              buscando
                  ? 'Busca por nombre y escucha\nantes de descargar.'
                  : 'Pega una URL, o compartela\ndesde YouTube.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
