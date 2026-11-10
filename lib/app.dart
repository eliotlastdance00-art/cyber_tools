import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/library/presentation/library_screen.dart';

/// Root widget. Navigation will move to typed go_router routes
/// in Phase 4 (see docs/ROADMAP.md).
class VoiceReaderApp extends StatelessWidget {
  const VoiceReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoiceReader',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const LibraryScreen(),
    );
  }
}
