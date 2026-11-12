import 'dart:io';
import 'dart:isolate';

import 'package:pdfrx/pdfrx.dart';
import 'package:voicereader/core/error/app_failure.dart';
import 'package:voicereader/core/result/result.dart';
import 'package:voicereader/core/text/sentence_splitter.dart';

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
    final len = await pdfFile.length();
    if (len == 0) {
      return const Result.err(PdfFailure('PDF contains no extractable text'));
    }
    return Result.ok(fakeText);
  }
}

/// Production extractor backed by `pdfrx` (PDFium, MIT) — **AÇYK, hakyky**.
///
/// Saýlanan iň gowusy:
/// - Isolate-da → UI freeze ýok
/// - 3-tip PdfFailure: encrypted / scanned / corrupted
/// - try/finally dispose() — leak ýok
/// - normalizeDocumentText — Turkmen ý-ň-ş/CJK düzedilýär
final class PdfrxPdfTextExtractor implements PdfTextExtractor {
  const PdfrxPdfTextExtractor();

  @override
  Future<Result<String>> extractText(File pdfFile) async {
    if (!await pdfFile.exists()) {
      return const Result.err(PdfFailure('PDF file not found'));
    }
    final size = await pdfFile.length();
    if (size == 0) return const Result.err(PdfFailure('PDF is empty'));
    if (size > 100 * 1024 * 1024) {
      return const Result.err(PdfFailure('PDF too large (>100 MB)'));
    }

    try {
      // PDFium heavy work in isolate
      final raw = await Isolate.run(() => _extractInIsolate(pdfFile.path));
      return raw.fold(
        (text) {
          final normalized = normalizeDocumentText(text);
          if (normalized.isEmpty) {
            return const Result.err(
              PdfFailure('PDF contains no extractable text — maybe scanned image'),
            );
          }
          return Result.ok(normalized);
        },
        (failure) => Result.err(failure),
      );
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('password') || msg.contains('Password') || msg.contains('encrypt')) {
        return const Result.err(PdfFailure('PDF is encrypted — password required'));
      }
      return Result.err(PdfFailure('Could not read PDF: $msg'));
    }
  }

  static Future<Result<String>> _extractInIsolate(String path) async {
    try {
      return await _tryPdfrxExtract(path);
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('password') || msg.contains('Password')) {
        return const Result.err(PdfFailure('PDF is encrypted — password required'));
      }
      return Result.err(PdfFailure('PDF corrupted or unsupported: $msg'));
    }
  }

  static Future<Result<String>> _tryPdfrxExtract(String path) async {
    // pdfrx needs explicit init when used outside widget tree (isolate)
    try {
      await pdfrxFlutterInitialize();
    } catch (_) {
      // Already initialized — ignore
    }

    PdfDocument? doc;
    try {
      doc = await PdfDocument.openFile(path);
      // Encrypted check — pdfium reports via isEncrypted or throws
      if (doc.isEncrypted) {
        return const Result.err(PdfFailure('PDF is encrypted — password required'));
      }

      final buf = StringBuffer();
      for (final page in doc.pages) {
        final raw = await page.loadText();
        if (raw != null && raw.fullText.trim().isNotEmpty) {
          buf.writeln(raw.fullText);
        }
      }

      return Result.ok(buf.toString());
    } catch (e) {
      final msg = e.toString().toLowerCase();
      if (msg.contains('password') || msg.contains('encrypted')) {
        return const Result.err(PdfFailure('PDF is encrypted — password required'));
      }
      return Result.err(PdfFailure('PDF corrupted or unsupported: $e'));
    } finally {
      // dispose() is pdfrx API — not close()
      try {
        await doc?.dispose();
      } catch (_) {}
    }
  }
}
