import 'package:descargador_movil/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('la pantalla ofrece descargar video o audio', (WidgetTester tester) async {
    await tester.pumpWidget(const AplicacionDescargador());

    expect(find.text('Descargar'), findsOneWidget);
    expect(find.text('Video MP4'), findsOneWidget);
    expect(find.text('Audio MP3'), findsOneWidget);
    // En modo video se elige calidad; en audio esa opcion no aplica.
    expect(find.text('Calidad maxima'), findsOneWidget);
  });

  testWidgets('al elegir audio desaparece el selector de calidad', (WidgetTester tester) async {
    await tester.pumpWidget(const AplicacionDescargador());

    await tester.tap(find.text('Audio MP3'));
    await tester.pumpAndSettle();

    expect(find.text('Calidad maxima'), findsNothing);
  });
}
