import 'dart:async';

import 'package:flutter/material.dart';

import 'estado_reproductor.dart';
import 'formato.dart';
import 'hoja_ajustes.dart';
import 'nucleo.dart';
import 'portadas.dart';
import 'tema.dart';

/// Pantalla principal: buscar o pegar una URL, ajustar y descargar.
class PantallaDescarga extends StatefulWidget {
  const PantallaDescarga({required this.alDescargar, super.key});

  /// Avisa para que la biblioteca se refresque sin tener que recargarla a mano.
  final VoidCallback alDescargar;

  @override
  State<PantallaDescarga> createState() => PantallaDescargaState();
}

class PantallaDescargaState extends State<PantallaDescarga> with WidgetsBindingObserver {
  final TextEditingController _entrada = TextEditingController();

  bool _buscando = true;
  Ajustes _ajustes = const Ajustes(url: '');
  List<Resultado> _resultados = <Resultado>[];
  Resultado? _elegido;

  bool _ocupado = false;
  String _estado = '';
  double? _porcentaje;
  String _mensaje = '';
  bool _fallo = false;
  Timer? _reloj;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _recogerCompartido();
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
    final String texto = _entrada.text.trim();
    if (texto.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _ocupado = true;
      _mensaje = '';
      _fallo = false;
      _resultados = <Resultado>[];
    });
    try {
      final List<Resultado> encontrados = await Nucleo.buscar(texto);
      if (!mounted) return;
      setState(() {
        _resultados = encontrados;
        if (encontrados.isEmpty) {
          _mensaje = 'Sin resultados.';
          _fallo = true;
        }
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _mensaje = '$error';
          _fallo = true;
        });
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _descargar() async {
    final String url = _elegido?.url ?? _entrada.text.trim();
    if (url.isEmpty) {
      setState(() {
        _mensaje = 'Elige un resultado o pega una URL.';
        _fallo = true;
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _ocupado = true;
      _porcentaje = null;
      _estado = 'Preparando...';
      _mensaje = '';
      _fallo = false;
    });
    _vigilar();

    try {
      await Nucleo.descargar(_ajustes.copiar(url: url));
      if (!mounted) return;
      setState(() {
        _mensaje = 'Guardado en tu biblioteca.';
        _fallo = false;
      });
      widget.alDescargar();
    } on ErrorNucleo catch (error) {
      if (!mounted) return;
      final String detalle = error.registro.isEmpty
          ? ''
          : '\n\n--- registro del motor ---\n${error.registro.join('\n')}';
      setState(() {
        _mensaje = '${error.mensaje}$detalle';
        _fallo = true;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _mensaje = '$error';
          _fallo = true;
        });
      }
    } finally {
      _reloj?.cancel();
      if (mounted) {
        setState(() {
          _ocupado = false;
          _estado = '';
          _porcentaje = null;
        });
      }
    }
  }

  /// Python publica el avance y aqui se consulta mientras dure la descarga.
  void _vigilar() {
    _reloj?.cancel();
    _reloj = Timer.periodic(const Duration(milliseconds: 500), (Timer reloj) async {
      if (!_ocupado) {
        reloj.cancel();
        return;
      }
      try {
        final Avance avance = await Nucleo.progreso();
        if (!mounted) return;
        setState(() {
          _porcentaje = avance.porcentaje >= 0 ? avance.porcentaje / 100 : null;
          _estado = switch (avance.estado) {
            'downloading' => '${formatoTamano(avance.velocidad)}/s',
            'finished' => 'Uniendo con FFmpeg...',
            _ => 'Preparando...',
          };
        });
      } catch (_) {
        // Una consulta perdida no debe romper la descarga en curso.
      }
    });
  }

  Future<void> _abrirAjustes() async {
    final Ajustes? nuevos = await showModalBottomSheet<Ajustes>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Tema.superficie,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => HojaAjustes(inicial: _ajustes),
    );
    if (nuevos != null) setState(() => _ajustes = nuevos);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reloj?.cancel();
    _entrada.dispose();
    super.dispose();
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
              if (_ocupado && _estado.isNotEmpty)
                _TarjetaProgreso(porcentaje: _porcentaje, estado: _estado)
              else
                BotonDegradado(
                  texto: _elegido == null ? 'Descargar' : 'Descargar seleccion',
                  icono: Icons.arrow_downward_rounded,
                  alPulsar: _ocupado ? null : _descargar,
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
            onSubmitted: _ocupado ? null : (_) => _buscando ? _buscar() : _descargar(),
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
            selected: <bool>{_ajustes.soloAudio},
            onSelectionChanged: _ocupado
                ? null
                : (Set<bool> e) => setState(() => _ajustes = _ajustes.copiar(soloAudio: e.first)),
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
    if (_mensaje.isNotEmpty && _resultados.isEmpty) {
      return _Aviso(mensaje: _mensaje, fallo: _fallo);
    }
    if (_resultados.isEmpty) {
      return _Vacio(buscando: _buscando);
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: _resultados.length,
      itemBuilder: (BuildContext context, int i) {
        final Resultado r = _resultados[i];
        return _TarjetaResultado(
          resultado: r,
          marcado: identical(r, _elegido),
          alPulsar: () => setState(() => _elegido = identical(r, _elegido) ? null : r),
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
  });

  final Resultado resultado;
  final bool marcado;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: marcado ? Tema.acento.withValues(alpha: 0.16) : Tema.superficie,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: marcado ? Tema.acento : Colors.transparent,
            width: 1.5,
          ),
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
                  _BotonEscucha(resultado: resultado),
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
  const _TarjetaProgreso({required this.porcentaje, required this.estado});

  final double? porcentaje;
  final String estado;

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
                const Text('Descargando', style: TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(estado, style: const TextStyle(color: Colors.white54, fontSize: 12)),
              ],
            ),
          ),
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
                  ? 'Busca por nombre y elige\nde la lista.'
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


/// Escucha el resultado sin descargarlo, para comprobar que es el que se busca.
class _BotonEscucha extends StatelessWidget {
  const _BotonEscucha({required this.resultado});

  final Resultado resultado;

  @override
  Widget build(BuildContext context) {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    return ListenableBuilder(
      listenable: estado,
      builder: (BuildContext context, _) {
        final bool esta = estado.actual?.fuente == resultado.url;
        if (esta && estado.preparando) {
          return const Padding(
            padding: EdgeInsets.all(14),
            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4)),
          );
        }
        return IconButton(
          tooltip: 'Escuchar sin descargar',
          onPressed: () => estado.previsualizar(resultado),
          icon: Icon(
            esta && estado.sonando ? Icons.pause_circle_rounded : Icons.play_circle_outline_rounded,
            size: 32,
            color: esta ? Tema.acento : Colors.white60,
          ),
        );
      },
    );
  }
}
