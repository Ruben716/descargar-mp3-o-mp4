import 'package:descargador_movil/autoeq.dart';
import 'package:descargador_movil/ecualizador.dart';
import 'package:descargador_movil/salida_audio.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('salida de audio', () {
    test('cada salida tiene su clave y su nombre', () {
      final SalidaAudio altavoz =
          SalidaAudio.desdeMapa(<String, String>{'tipo': 'altavoz', 'nombre': '', 'modelo': 'samsung SM-A546E'});
      expect(altavoz.clave, 'altavoz');
      expect(altavoz.titulo, 'Altavoz del samsung SM-A546E');
      expect(altavoz.esAudifono, isFalse);

      final SalidaAudio buds = SalidaAudio.desdeMapa(<String, String>{'tipo': 'bluetooth', 'nombre': ' Galaxy Buds2 '});
      expect(buds.clave, 'bluetooth:galaxy buds2');
      expect(buds.titulo, 'Galaxy Buds2');
      expect(buds.esAudifono, isTrue);
      expect(buds, const SalidaAudio(TipoSalida.bluetooth, nombre: 'galaxy buds2'),
          reason: 'los mismos audifonos aunque cambie la mayuscula');

      expect(const SalidaAudio(TipoSalida.cable, nombre: 'Headset').clave, 'cable',
          reason: 'con cable no se sabe que audifonos son: uno solo');
      expect(SalidaAudio.desdeMapa(<String, String>{'tipo': 'raro'}).tipo, TipoSalida.altavoz);
    });

    test('el ajuste de fabrica: altavoz para el telefono, plano para audifonos', () {
      expect(Ajuste.porNombre('Altavoz del telefono'), Ajuste.altavoz);
      expect(Ecualizador.deFabrica(SalidaAudio.altavoz)['ajuste'], 'Altavoz del telefono');
      expect(Ecualizador.deFabrica(const SalidaAudio(TipoSalida.bluetooth, nombre: 'x'))['ajuste'], 'Plano');
      expect(Ajuste.altavoz.gananciaEn(40), lessThan(-5), reason: 'el altavoz no da graves profundos');
      expect(Ajuste.altavoz.gananciaEn(400), greaterThan(1), reason: 'el cuerpo de la musica sube');
    });
  });

  group('autoeq por el nombre del aparato', () {
    final List<ModeloAudifonos> todos = AutoEq.leerIndice('# Index\n'
        '- [Samsung Galaxy Buds2](./oratory1990/in-ear/Samsung%20Galaxy%20Buds2) by oratory1990\n'
        '- [Samsung Galaxy Buds2 Pro](./oratory1990/in-ear/Samsung%20Galaxy%20Buds2%20Pro) by oratory1990\n'
        '- [Sony WH-1000XM4](./oratory1990/over-ear/Sony%20WH-1000XM4) by oratory1990\n'
        '- [Sony WH-1000XM5](./oratory1990/over-ear/Sony%20WH-1000XM5) by oratory1990\n'
        '- [JBL Tune 510BT](./Rtings/over-ear/JBL%20Tune%20510BT) by Rtings\n');

    test('el nombre de fabrica de unos audifonos da su modelo', () {
      expect(modeloParaAparato(todos, 'Galaxy Buds2')?.nombre, 'Samsung Galaxy Buds2',
          reason: 'no el Pro, que tambien lleva esas palabras');
      expect(modeloParaAparato(todos, 'LE-Galaxy Buds2 Pro')?.nombre, 'Samsung Galaxy Buds2 Pro');
      expect(modeloParaAparato(todos, 'WH-1000XM4')?.nombre, 'Sony WH-1000XM4');
      expect(modeloParaAparato(todos, 'JBL Tune 510BT (A1B2)')?.nombre, 'JBL Tune 510BT');
    });

    test('si hay dudas no se corrige con la curva de otro', () {
      expect(modeloParaAparato(todos, 'Bluetooth'), isNull);
      expect(modeloParaAparato(todos, 'Galaxy'), isNull, reason: 'tres modelos posibles');
      expect(modeloParaAparato(todos, 'MI CARRO'), isNull);
      expect(modeloParaAparato(todos, ''), isNull);
    });
  });
}
