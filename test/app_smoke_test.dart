import 'package:flutter_test/flutter_test.dart';
import 'package:voicereader/app.dart';

void main() {
  testWidgets('app boots and shows brand copy', (tester) async {
    await tester.pumpWidget(const VoiceReaderApp());
    expect(find.text('VoiceReader'), findsOneWidget);
    expect(find.text('Listen to anything.'), findsOneWidget);
  });
}
