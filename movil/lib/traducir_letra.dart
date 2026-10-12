import 'letras.dart';
import 'traduccion.dart';

/// La letra en castellano, linea a linea, con el traductor del propio movil.
///
/// Es IA en el telefono (ML Kit de Google): sin cuenta, sin pagar y sin
/// mandar la letra a ningun sitio. La primera vez baja el idioma (unos 30 MB)
/// y despues traduce incluso sin internet.
class TraducirLetra {
  TraducirLetra._();

  /// Palabras que delatan una letra en ingles o en castellano.
  static const Set<String> _ingles = <String>{
    'the', 'you', 'and', 'i', 'me', 'my', 'your', 'love', 'it', 'is', 'to', 'in', 'on', 'we',
    "don't", "i'm", "it's", 'baby', 'oh', 'yeah', 'know', 'what', 'when', 'all', 'be', 'like', 'just',
  };
  static const Set<String> _castellano = <String>{
    'el', 'la', 'que', 'de', 'y', 'yo', 'tu', 'mi', 'te', 'me', 'amor', 'no', 'es', 'en', 'un', 'una',
    'por', 'con', 'para', 'quiero', 'eres', 'pero', 'como', 'mas', 'bebe', 'contigo',
  };

  /// Si merece la pena ofrecer traducirla: parece ingles y no castellano.
  ///
  /// Se cuenta, no se adivina: con letras en otros idiomas (coreano,
  /// portugues...) no se ofrece, porque el traductor del telefono va del
  /// ingles al castellano.
  static bool pareceIngles(String texto) {
    final List<String> palabras = texto
        .toLowerCase()
        .split(RegExp(r"[^a-z'ñáéíóú]+"))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (palabras.length < 8) return false;
    final int ingles = palabras.where(_ingles.contains).length;
    final int castellano = palabras.where(_castellano.contains).length;
    return ingles >= 4 && ingles > castellano * 2;
  }

  /// El texto que se manda a traducir: una linea por linea de la letra.
  static String _texto(Letra letra) => letra.sincronizada
      ? letra.lineas.map((LineaLetra l) => l.texto).join('\n')
      : letra.texto;

  static bool ofrecer(Letra letra) => !letra.vacia && pareceIngles(_texto(letra));

  /// Una traduccion por linea, en el mismo orden; null si no se pudo.
  ///
  /// Si el traductor devolviera otro numero de lineas no se podrian casar
  /// con las originales, y se da por fallida antes que descolocarlas.
  static Future<List<String>?> traducir(Letra letra) async {
    final String original = _texto(letra);
    final String? traducida = await Traduccion.alEspanol(original);
    if (traducida == null) return null;
    final List<String> lineas = traducida.split('\n');
    final int esperadas = original.split('\n').length;
    if (lineas.length != esperadas) return null;
    return lineas;
  }
}
