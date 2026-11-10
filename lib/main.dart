import 'package:flutter/material.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = FlutterError.presentError;
  runApp(const VoiceReaderApp());
}
