import 'package:flutter/material.dart';
import 'package:voicereader/core/theme/app_theme.dart';
import 'package:voicereader/features/library/presentation/library_screen.dart';

/// Root widget. Navigation will move to typed go_router routes
/// in Phase 4 (see docs/ROADMAP.md).
class VoiceReaderApp extends StatelessWidget {
  const VoiceReaderApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'VoiceReader',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.dark,
    home: const LibraryScreen(),
  );
}
