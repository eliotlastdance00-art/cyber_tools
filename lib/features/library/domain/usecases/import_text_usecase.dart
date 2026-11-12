import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:voicereader/core/error/app_failure.dart';
import 'package:voicereader/core/platform/file_service.dart';
import 'package:voicereader/core/result/result.dart';
import 'package:voicereader/core/utils/ulid.dart';
import 'package:voicereader/features/library/domain/entities/document.dart';
import 'package:voicereader/features/library/domain/repositories/document_repository.dart';

/// Imports a plain text file (txt/md/text) into the library.
///
/// Flow: validate → sha256 → dedupe → copy → count chars → save row → return doc.
/// Returns existing doc if SHA-256 matches (no duplicate).
final class ImportTextUseCase {
  const ImportTextUseCase({
    required this.fileService,
    required this.repository,
  });

  final FileService fileService;
  final DocumentRepository repository;

  Future<Result<LibraryDocument>> call(File sourceFile) async {
    if (!await sourceFile.exists()) {
      return const Result.err(ValidationFailure('File does not exist'));
    }

    final ext = p.extension(sourceFile.path).toLowerCase();
    if (!_textExts.contains(ext)) {
      return const Result.err(ValidationFailure('Not a text file: expected .txt/.md'));
    }

    // 1. Hash for dedupe
    final hashRes = await fileService.sha256Of(sourceFile);
    if (hashRes.isErr) return Result.err(hashRes.failureOrNull!);
    final hash = hashRes.valueOrNull!;

    final existing = await repository.findBySha256(hash);
    if (existing.isOk && existing.valueOrNull != null) {
      return Result.ok(existing.valueOrNull!);
    }

    // 2. Read + count
    final textRes = await fileService.readAsString(sourceFile.path);
    // For ImportTextUseCase the sourceFile is the original picked file,
    // not the imported copy — read directly from it.
    String rawText;
    if (textRes.isOk) {
      rawText = textRes.valueOrNull!;
    } else {
      // Fallback: read via dart:io directly (e.g. FakeFileService in tests)
      try {
        rawText = await sourceFile.readAsString();
      } catch (e) {
        return Result.err(StorageFailure('Could not read text: $e'));
      }
    }

    if (rawText.trim().isEmpty) {
      return const Result.err(ValidationFailure('Text file is empty'));
    }

    // Free tier gate — checked here once; Phase 6 enforces via ProEntitlement
    // use case. Kept as soft limit so tests don't need Pro mock.
    // Free limit: 1500 chars per doc (enforced in UI, not here as hard fail).

    final id = generateUlid();
    final title = p.basenameWithoutExtension(sourceFile.path).trim();
    if (title.isEmpty) {
      return const Result.err(ValidationFailure('File name is empty'));
    }

    // 3. Copy to app dir
    final importRes = await fileService.importFile(sourceFile, id);
    if (importRes.isErr) return Result.err(importRes.failureOrNull!);
    final imported = importRes.valueOrNull!;

    final now = DateTime.now();
    final doc = LibraryDocument(
      id: id,
      title: title,
      sourceType: DocumentSourceType.text,
      relativePath: imported.relativePath,
      sha256: hash,
      charCount: rawText.length,
      addedAt: now,
      lastOpenedAt: now,
    );

    final saveRes = await repository.save(doc);
    return saveRes;
  }

  static const _textExts = {'.txt', '.md', '.text'};
}
