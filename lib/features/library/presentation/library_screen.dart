import 'package:flutter/material.dart';
import 'package:voicereader/core/theme/app_theme.dart';

/// Phase 0 placeholder — the real library (import, search, progress) ships
/// in Phase 4. Keeps the app compiling and demo-able from day one.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    appBar: AppBar(
      title: Text('VoiceReader'),
      actions: [
        IconButton(icon: Icon(Icons.search), tooltip: 'Search your library'),
      ],
    ),
    body: Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.menu_book_rounded, size: 72, color: BrandColors.coral),
          SizedBox(height: 16),
          Text(
            'Listen to anything.',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: BrandColors.text,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'PDF & text, read aloud — private, offline.',
            style: TextStyle(color: BrandColors.muted),
          ),
        ],
      ),
    ),
  );
}
