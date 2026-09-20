import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'control_descarga.dart';
import 'estado_reproductor.dart';
import 'formato.dart';
import 'nucleo.dart';
import 'tema.dart';

/// Vista previa a pantalla completa: se oye y se ve antes de descargar.
class PantallaPrevia extends StatelessWidget {
  const PantallaPrevia({required this.resultado, super.key});

  final Resultado resultado;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'VISTA PREVIA',
          style: TextStyle(fontSize: 11, letterSpacing: 1.4, fontWeight: FontWeight.w800),
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // La miniatura difuminada da el color del fondo, como en el
          // reproductor de la biblioteca.
          if (resultado.miniatura.isNotEmpty)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 52, sigmaY: 52),
              child: Image.network(resultado.miniatura, fit: BoxFit.cover),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[Color(0xCC08070C), Color(0xF208070C), Tema.fondo],
              ),
            ),
          ),
          SafeArea(child: _Contenido(resultado: resultado)),
        ],
      ),
    );
  }
}

class _Contenido extends StatelessWidget {
  const _Contenido({required this.resultado});

  final Resultado resultado;

  @override
  Widget build(BuildContext context) {
    final EstadoReproductor estado = EstadoReproductor.instancia;
    // Centrado cuando cabe y con desplazamiento cuando no: en pantallas bajas
    // la miniatura mas los controles no entran y se desbordaba.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints limites) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: limites.maxHeight - 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: resultado.miniatura.isEmpty
                      ? const ColoredBox(
                          color: Tema.superficieAlta,
                          child: Icon(Icons.graphic_eq_rounded, size: 64, color: Colors.white24),
                        )
                      : Image.network(resultado.miniatura, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                resultado.titulo,
                maxLines: 3,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                '${resultado.autor}  ·  ${formatoTiempo(resultado.duracion)}',
                style: const TextStyle(color: Colors.white54),
              ),
              const SizedBox(height: 28),
              _Barra(estado: estado),
              const SizedBox(height: 10),
              _Controles(estado: estado),
              const SizedBox(height: 22),
              _Descarga(resultado: resultado),
              const SizedBox(height: 8),
              const Text(
                'Todavia no esta en tu telefono',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Barra extends StatelessWidget {
  const _Barra({required this.estado});

  final EstadoReproductor estado;

  @override
  Widget build(BuildContext context) {
    final AudioPlayer motor = estado.motor;
    return StreamBuilder<Duration>(
      stream: motor.positionStream,
      builder: (BuildContext context, AsyncSnapshot<Duration> instante) {
        final Duration total = motor.duration ?? Duration.zero;
        final Duration actual = instante.data ?? Duration.zero;
        final double maximo = total.inMilliseconds.toDouble();
        return Column(
          children: <Widget>[
            Slider(
              value: actual.inMilliseconds.clamp(0, maximo.toInt()).toDouble(),
              max: maximo <= 0 ? 1 : maximo,
              onChanged: (double v) => motor.seek(Duration(milliseconds: v.round())),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text(
                    formatoTiempo(actual.inSeconds),
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                  Text(
                    formatoTiempo(total.inSeconds),
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _Controles extends StatelessWidget {
  const _Controles({required this.estado});

  final EstadoReproductor estado;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: estado,
      builder: (BuildContext context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          IconButton(
            iconSize: 32,
            color: Colors.white70,
            onPressed: () => estado.saltar(const Duration(seconds: -10)),
            icon: const Icon(Icons.replay_10),
          ),
          const SizedBox(width: 18),
          GestureDetector(
            onTap: estado.alternar,
            child: Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                gradient: Tema.degradado,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Tema.acento.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: estado.preparando
                  ? const Padding(
                      padding: EdgeInsets.all(22),
                      child: CircularProgressIndicator(strokeWidth: 3, color: Colors.black54),
                    )
                  : Icon(
                      estado.sonando ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      size: 38,
                      color: Colors.black87,
                    ),
            ),
          ),
          const SizedBox(width: 18),
          IconButton(
            iconSize: 32,
            color: Colors.white70,
            onPressed: () => estado.saltar(const Duration(seconds: 10)),
            icon: const Icon(Icons.forward_10),
          ),
        ],
      ),
    );
  }
}

/// Descargar lo que se esta oyendo, sin volver atras a buscarlo otra vez.
class _Descarga extends StatelessWidget {
  const _Descarga({required this.resultado});

  final Resultado resultado;

  @override
  Widget build(BuildContext context) {
    final ControlDescarga control = ControlDescarga.instancia;
    return ListenableBuilder(
      listenable: control,
      builder: (BuildContext context, _) {
        if (control.activa) {
          return Column(
            children: <Widget>[
              LinearProgressIndicator(
                value: control.porcentaje,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 8),
              Text(control.estado, style: const TextStyle(color: Colors.white60, fontSize: 12)),
            ],
          );
        }
        if (control.mensaje.isNotEmpty && !control.fallo) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Icon(Icons.check_circle_rounded, color: Color(0xFF57D9A3)),
              const SizedBox(width: 8),
              Text(control.mensaje, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          );
        }
        return BotonDegradado(
          texto: control.ajustes.soloAudio ? 'Descargar MP3' : 'Descargar video',
          icono: Icons.arrow_downward_rounded,
          alPulsar: () => control.iniciar(resultado.url),
        );
      },
    );
  }
}
