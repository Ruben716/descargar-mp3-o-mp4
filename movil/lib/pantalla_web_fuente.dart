import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'nucleo.dart';
import 'tema.dart';

/// Reproduce un servidor con su propio reproductor, dentro de la app.
///
/// Es la via que funciona con cualquier hosting: en vez de adivinar el enlace
/// real (cada web lo esconde distinto y cambia a menudo), se deja que su
/// reproductor haga su trabajo. Para el usuario es lo mismo: se ve aqui.
class PantallaWebFuente extends StatefulWidget {
  const PantallaWebFuente({required this.url, required this.titulo, super.key});

  final String url;
  final String titulo;

  @override
  State<PantallaWebFuente> createState() => _PantallaWebFuenteState();
}

class _PantallaWebFuenteState extends State<PantallaWebFuente> {
  late final WebViewController _controlador;
  int _progreso = 0;

  @override
  void initState() {
    super.initState();
    _controlador = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.black)
      ..setUserAgent(
        'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36',
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int avance) {
            if (mounted) setState(() => _progreso = avance);
          },
          // Se deja pasar todo: el reproductor abre su propio contenido.
          onNavigationRequest: (NavigationRequest peticion) =>
              NavigationDecision.navigate,
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _navegador() async {
    try {
      await Nucleo.abrirEnlace(widget.url);
    } on ErrorNucleo {
      // Si no hay navegador, ya se esta viendo aqui dentro.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(widget.titulo, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: <Widget>[
          IconButton(
            tooltip: 'Recargar',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _controlador.reload(),
          ),
          IconButton(
            tooltip: 'Abrir en el navegador',
            icon: const Icon(Icons.open_in_new_rounded),
            onPressed: _navegador,
          ),
        ],
        bottom: _progreso < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  value: _progreso / 100,
                  backgroundColor: Tema.superficie,
                ),
              )
            : null,
      ),
      body: WebViewWidget(controller: _controlador),
    );
  }
}
