import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:voicereader/core/error/app_failure.dart';
import 'package:voicereader/core/platform/file_service.dart';
import 'package:voicereader/core/result/result.dart';
import 'package:voicereader/core/utils/ulid.dart';
import 'package:voicereader/features/library/domain/entities/document.dart';
import 'package:voicereader/features/library/domain/repositories/document_repository.dart';
import 'package:voicereader/features/reader/domain/services/pdf_text_extractor.dart';

/// Imports a PDF file into the library:
/// validate → sha256 → dedupe → extract text → copy → save doc+text.
///
/// Returns existing doc if SHA-256 matches (no duplicates).
final class ImportPdfUseCase {
  const ImportPdfUseCase({
    required this.fileService,
    required this.repository,
    required this.pdfExtractor,
  });

  final FileService fileService;
  final DocumentRepository repository;
  final PdfTextExtractor pdfExtractor;

  Future<Result<LibraryDocument>> call(File sourceFile) async {
    if (!await sourceFile.exists()) {
      return const Result.err(ValidationFailure('File does not exist'));
    }

    final ext = p.extension(sourceFile.path).toLowerCase();
    if (ext != '.pdf') {
      return const Result.err(ValidationFailure('Not a PDF: expected .pdf'));
    }

    final size = await sourceFile.length();
    if (size == 0) {
      return const Result.err(ValidationFailure('PDF is empty'));
    }
    // Guard against huge PDFs in tests / low-end devices
    if (size > 100 * 1024 * 1024) {
      return const Result.err(ValidationFailure('PDF too large (>100 MB)'));
    }

    // 1. Hash for dedupe
    final hashRes = await fileService.sha256Of(sourceFile);
    if (hashRes.isErr) return Result.err(hashRes.failureOrNull!);
    final hash = hashRes.valueOrNull!;

    final existing = await repository.findBySha256(hash);
    if (existing.isOk && existing.valueOrNull != null) {
      return Result.ok(existing.valueOrNull!);
    }

    // 2. Extract text (may be heavy — runs on IO isolate in production)
    final textRes = await pdfExtractor.extractText(sourceFile);
    if (textRes.isErr) return Result.err(textRes.failureOrNull!);
    final plainText = textRes.valueOrNull!.trim();
    if (plainText.isEmpty) {
      return const Result.err(PdfFailure('PDF contains no extractable text — maybe scanned image'));
    }

    // 3. Copy to app dir
    final id = generateUlid();
    final title = p.basenameWithoutExtension(sourceFile.path).trim();
    if (title.isEmpty) {
      return const Result.err(ValidationFailure('File name is empty'));
    }

    final importRes = await fileService.importFile(sourceFile, id);
    if (importRes.isErr) return Result.err(importRes.failureOrNull!);
    final imported = importRes.valueOrNull!;

    final now = DateTime.now();
    final doc = LibraryDocument(
      id: id,
      title: title,
      sourceType: DocumentSourceType.pdf,
      relativePath: imported.relativePath,
      sha256: hash,
      charCount: plainText.length,
      addedAt: now,
      lastOpenedAt: now,
    );

    // 4. Save doc + text atomically (text in separate table in drift, here in memory map)
    final saveDoc = await repository.save(doc);
    if (saveDoc.isErr) return saveDoc;

    final saveText = await repository.saveText(doc.id, plainText);
    if (saveText.isErr) {
      // Rollback doc if text save fails (best effort)
      await repository.delete(doc.id);
      return Result.err(saveText.failureOrNull!);
    }

    return Result.ok(doc);
  }
}
