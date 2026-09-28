/// Que quiere hacer el usuario con lo que escribio en el campo de Descargar.
///
/// Hay un solo campo para buscar y para pegar enlaces, como la barra del
/// navegador. Antes habia dos modos y un boton para cambiar entre ellos, pero
/// el modo no se veia por ninguna parte: con texto en modo enlace se intentaba
/// descargar la frase, y el boton «Descargar» salia incluso sin nada que
/// descargar. Decidirlo aqui, a partir de lo escrito, quita esa eleccion.
enum TipoEntrada {
  /// Nada escrito.
  vacia,

  /// Texto normal: se busca por nombre.
  busqueda,

  /// Un enlace a un video o una cancion suelta.
  enlace,

  /// Un enlace a una lista entera.
  lista,

  /// Parece un enlace pero no se puede abrir: le falta algo.
  enlaceRoto,
}

class Entrada {
  const Entrada._(
    this.tipo, {
    this.texto = '',
    this.url = '',
    this.sitio = '',
    this.listaAparte = '',
  });

  final TipoEntrada tipo;

  /// Lo que se busca, ya sin espacios sobrantes.
  final String texto;

  /// El enlace listo para usar, con https:// aunque se pegara sin el.
  final String url;

  /// De donde es el enlace, dicho como lo diria una persona: «TikTok».
  final String sitio;

  /// Un video abierto desde una lista trae las dos cosas en el enlace. Se baja
  /// el video, que es lo que se estaba viendo, y aqui queda la lista entera
  /// por si se quiere esa. Vacio si no hay lista que ofrecer.
  final String listaAparte;

  bool get esEnlace => tipo == TipoEntrada.enlace || tipo == TipoEntrada.lista;

  static const Entrada _vacia = Entrada._(TipoEntrada.vacia);

  /// Un enlace completo en cualquier parte del texto.
  ///
  /// Al copiar desde TikTok o Instagram muchas veces viene con una frase
  /// delante («Mira este video: https://...»): se aprovecha el enlace.
  static final RegExp _conEsquema = RegExp(r'https?://\S+', caseSensitive: false);

  /// Un enlace pegado sin «https://», como «youtu.be/abc».
  ///
  /// Tiene que llevar ruta. Sin ella, «Mr.Brightside» pareceria una web y
  /// nadie que lo escribe quiere abrirla: quiere buscar la cancion.
  static final RegExp _sinEsquema =
      RegExp(r'^(?:www\.)?[a-z0-9-]+(?:\.[a-z0-9-]+)+/\S*$', caseSensitive: false);

  /// Lo que suele colgar al final de un enlace copiado dentro de una frase.
  static final RegExp _colaDeFrase = RegExp('[.,;:!?)\\]}»"\']+\$');

  static Entrada de(String crudo) {
    final String texto = crudo.trim();
    if (texto.isEmpty) return _vacia;

    final RegExpMatch? dentro = _conEsquema.firstMatch(texto);
    final String? candidato = dentro != null
        ? dentro.group(0)!.replaceFirst(_colaDeFrase, '')
        : (_sinEsquema.hasMatch(texto) ? 'https://$texto' : null);

    if (candidato == null) {
      // Empieza como un enlace pero no se deja leer como tal: mejor decirlo
      // que buscar «https//youtube...» y devolver canciones al azar.
      if (texto.toLowerCase().startsWith('http')) {
        return const Entrada._(TipoEntrada.enlaceRoto);
      }
      return Entrada._(TipoEntrada.busqueda, texto: texto);
    }
    return _deEnlace(candidato);
  }

  static Entrada _deEnlace(String url) {
    final Uri? uri = Uri.tryParse(url);
    // Lo mismo que exige el dominio antes de descargar, para avisar aqui y no
    // despues de arrancar el motor.
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        !uri.host.contains('.') ||
        (uri.hasPort && uri.port == 0)) {
      return const Entrada._(TipoEntrada.enlaceRoto);
    }
    final String sitio = sitioDe(uri.host);
    final String? lista = uri.queryParameters['list'];
    final bool esVideo = uri.queryParameters.containsKey('v') ||
        _anfitrion(uri.host) == 'youtu.be' ||
        uri.path.startsWith('/shorts/');

    if (uri.path.startsWith('/playlist') || (lista != null && !esVideo)) {
      return Entrada._(TipoEntrada.lista, url: url, sitio: sitio);
    }
    return Entrada._(
      TipoEntrada.enlace,
      url: url,
      sitio: sitio,
      // Las «RD...» son las mezclas que YouTube arma solo y no acaban nunca:
      // no son una lista de nadie, asi que no se ofrecen.
      listaAparte: lista != null && lista.isNotEmpty && !lista.startsWith('RD')
          ? 'https://www.youtube.com/playlist?list=$lista'
          : '',
    );
  }

  static const Map<String, String> _sitios = <String, String>{
    'music.youtube.com': 'YouTube Music',
    'youtube.com': 'YouTube',
    'youtu.be': 'YouTube',
    'tiktok.com': 'TikTok',
    'instagram.com': 'Instagram',
    'soundcloud.com': 'SoundCloud',
    'facebook.com': 'Facebook',
    'fb.watch': 'Facebook',
    'x.com': 'X',
    'twitter.com': 'X',
    'vimeo.com': 'Vimeo',
    'twitch.tv': 'Twitch',
    'dailymotion.com': 'Dailymotion',
    'archive.org': 'Internet Archive',
  };

  static String _anfitrion(String host) =>
      host.toLowerCase().replaceFirst(RegExp(r'^(www|m)\.'), '');

  /// El nombre del sitio. Si no se conoce, su direccion sin el «www.».
  static String sitioDe(String host) {
    final String limpio = _anfitrion(host);
    final String? exacto = _sitios[limpio];
    if (exacto != null) return exacto;
    for (final MapEntry<String, String> s in _sitios.entries) {
      // vm.tiktok.com, es.soundcloud.com...
      if (limpio.endsWith('.${s.key}')) return s.value;
    }
    return limpio;
  }
}
