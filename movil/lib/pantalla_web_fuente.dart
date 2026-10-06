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
  const PantallaWebFuente({
    required this.url,
    required this.titulo,
    this.enIframe = false,
    super.key,
  });

  final String url;
  final String titulo;

  /// Carga la direccion dentro de un iframe propio.
  ///
  /// Algunos reproductores (embed69 y companiia) solo funcionan embebidos y se
  /// borran si son la pagina principal. Envolviendolos en un iframe, se evita
  /// ese bloqueo.
  final bool enIframe;

  @override
  State<PantallaWebFuente> createState() => _PantallaWebFuenteState();
}

class _PantallaWebFuenteState extends State<PantallaWebFuente> {
  late final WebViewController _controlador;
  int _progreso = 0;

  /// Anfitrion del embed: solo se deja navegar dentro de el (o de la web que
  /// lo sirve). Asi el reproductor no salta a paginas de anuncios.
  late final String _anfitrionEmbed = Uri.tryParse(widget.url)?.host ?? '';

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
          onNavigationRequest: (NavigationRequest peticion) {
            if (!widget.enIframe) return NavigationDecision.navigate;
            final String anfitrion = Uri.tryParse(peticion.url)?.host ?? '';
            final bool permitido = anfitrion.isEmpty ||
                anfitrion == _anfitrionEmbed ||
                anfitrion.endsWith('.$_anfitrionEmbed') ||
                anfitrion.contains('pelisplushd');
            return permitido ? NavigationDecision.navigate : NavigationDecision.prevent;
          },
        ),
      );
    if (widget.enIframe) {
      _controlador.loadHtmlString(
        _envoltorio(widget.url),
        baseUrl: 'https://pelisplushd.bz/',
      );
    } else {
      _controlador.loadRequest(Uri.parse(widget.url));
    }
  }

  /// Deja la direccion dentro de un iframe a pantalla completa.
  String _envoltorio(String url) {
    final String segura = url
        .replaceAll('&', '&amp;')
        .replaceAll('"', '&quot;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll("'", '&#39;');
    return '<!doctype html><html><head>'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        '</head><body style="margin:0;background:#000">'
        '<iframe src="$segura" '
        'style="border:0;position:fixed;inset:0;width:100%;height:100%" '
        'allow="autoplay; fullscreen; encrypted-media; picture-in-picture" '
        'allowfullscreen></iframe></body></html>';
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
