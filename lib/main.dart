import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:voicereader/app.dart';

void main() {
  runZonedGuarded<void>(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      // pdfrx needs one-time init before any PdfDocument usage (incl. isolate)
      // ignore: discarded_futures
      pdfrxFlutterInitialize();

      // Capture framework errors — in release they would otherwise show
      // a blank/white screen. We log and show a friendly fallback.
      FlutterError.onError = (details) {
        developer.log(
          'FlutterError: ${details.exceptionAsString()}',
          name: 'VoiceReader',
          error: details.exception,
          stackTrace: details.stack,
        );
        // In debug, also present the red screen for developers.
        if (kDebugMode) {
          FlutterError.presentError(details);
        }
      };

      PlatformDispatcher.instance.onError = (error, stack) {
        developer.log(
          'PlatformDispatcher error: $error',
          name: 'VoiceReader',
          error: error,
          stackTrace: stack,
        );
        return true;
      };

      ErrorWidget.builder = (details) => _StartupErrorScreen(details: details);

      runApp(const VoiceReaderApp());
    },
    (error, stack) {
      developer.log(
        'Uncaught zone error: $error',
        name: 'VoiceReader',
        error: error,
        stackTrace: stack,
      );
    },
  );
}

/// Shown when the app throws during build (e.g. theme or provider init).
/// In release this replaces the blank screen with actionable info.
class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.details});

  final FlutterErrorDetails details;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: const Color(0xFF0B1B33),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Color(0xFFFF6B4A)),
              const SizedBox(height: 16),
              const Text(
                'Bir ýalňyşlyk ýüze çykdy',
                style: TextStyle(
                  color: Color(0xFFE8EDF7),
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                kDebugMode
                    ? details.exceptionAsString()
                    : 'Programma başlatylanda ýalňyşlyk boldy. Maglumat log-a ýazyldy.',
                style: const TextStyle(color: Color(0xFF93A4C4), fontSize: 13),
                textAlign: TextAlign.center,
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF12264A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SingleChildScrollView(
                    child: Text(
                      details.stack?.toString() ?? '—',
                      style: const TextStyle(
                        color: Color(0xFF93A4C4),
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
