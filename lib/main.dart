import 'package:flutter/material.dart';
import 'package:voicereader/app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = FlutterError.presentError;
  runApp(const VoiceReaderApp());
}
