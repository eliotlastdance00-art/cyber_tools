import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:voicereader/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('emulatorda açylýar — LibraryScreen görkezýär', (tester) async {
    await tester.pumpWidget(const VoiceReaderApp());
    await tester.pumpAndSettle();

    // Brand copy visible — app opened
    expect(find.text('VoiceReader'), findsOneWidget);
    expect(find.text('Listen to anything.'), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);

    // Screenshot for artifact (CI will attach)
    // await binding.takeScreenshot('library');
  });
}
