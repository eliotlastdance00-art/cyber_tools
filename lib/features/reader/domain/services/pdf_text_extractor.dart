import 'dart:io';

import 'package:voicereader/core/error/app_failure.dart';
import 'package:voicereader/core/result/result.dart';

/// Extracts plain text from a PDF file. All implementations must be offline
/// and return [PdfFailure] on any error so the caller can show a typed message.
abstract interface class PdfTextExtractor {
  Future<Result<String>> extractText(File pdfFile);
}

/// Deterministic fake for unit/widget tests — never touches PDFium.
final class FakePdfTextExtractor implements PdfTextExtractor {
  FakePdfTextExtractor({
    this.fakeText = 'Hello PDF World. This is a test document with two sentences. '
        'It should be imported correctly.',
    this.shouldFail = false,
    this.failureMessage = 'Fake PDF error',
  });

  final String fakeText;
  final bool shouldFail;
  final String failureMessage;

  @override
  Future<Result<String>> extractText(File pdfFile) async {
    if (shouldFail) return Result.err(PdfFailure(failureMessage));
    if (!await pdfFile.exists()) {
      return const Result.err(PdfFailure('PDF file not found'));
    }
    // Simulate a scanned PDF with no text if file is empty
    final len = await pdfFile.length();
    if (len == 0) return const Result.err(PdfFailure('PDF contains no extractable text'));
    return Result.ok(fakeText);
  }
}

/// Production extractor backed by `pdfrx` (PDFium, MIT).
/// This is the Phase 2 wiring point — uncomment when `pdfrx` is added to pubspec.
/// Keeping it as a stub now ensures the interface is stable and testable.
final class PdfrxPdfTextExtractor implements PdfTextExtractor {
  const PdfrxPdfTextExtractor();

  @override
  Future<Result<String>> extractText(File pdfFile) async {
    // TODO(Phase 2): implement with pdfrx
    //   final doc = await PdfDocument.openFile(pdfFile.path);
    //   final text = StringBuffer();
    //   for (var i = 1; i <= doc.pages.length; i++) {
    //     final page = await doc.pages[i].load();
    //     text.writeln(await page.loadText());
    //     await page.close();
    //   }
    //   await doc.close();
    //   final plain = text.toString().trim();
    //   if (plain.isEmpty) return const Result.err(PdfFailure('PDF has no text layer'));
    //   return Result.ok(plain);
    return const Result.err(PdfFailure('pdfrx not wired yet — use FakePdfTextExtractor in tests'));
  }
}
