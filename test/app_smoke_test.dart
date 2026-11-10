import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicereader/app.dart';

void main() {
  testWidgets('app boots and shows brand copy', (tester) async {
    await tester.pumpWidget(const VoiceReaderApp());
    expect(find.text('VoiceReader'), findsOneWidget);
    expect(find.text('Listen to anything.'), findsOneWidget);
    // Regression guard: Material Icons font must be bundled
    // (uses-material-design: true) — unbundled fonts render as tofu boxes.
    expect(find.byIcon(Icons.search), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
  });
}
