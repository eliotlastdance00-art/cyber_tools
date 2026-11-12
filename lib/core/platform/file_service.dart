import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:voicereader/core/error/app_failure.dart';
import 'package:voicereader/core/result/result.dart';

/// Abstraction over file I/O — every call returns [Result] so the data layer
/// never throws across boundaries. Backed by `path_provider` app-docs dir.
abstract interface class FileService {
  /// Copies [source] into `appDocs/books/<ulid><ext>` and returns the new
  /// absolute path. Uses SHA-256 to allow callers to dedupe.
  Future<Result<ImportedFile>> importFile(File source, String ulid);

  /// Computes SHA-256 hex of [file].
  Future<Result<String>> sha256Of(File file);

  /// Returns the app documents directory (cached after first call).
  Future<Directory> appDocsDir();

  /// Deletes the file at [absolutePath] if it exists.
  Future<Result<void>> deleteIfExists(String absolutePath);

  /// Reads text file as string (UTF-8). For PDF this is not used — pdfrx
  /// extracts text via a separate `PdfTextExtractor` interface.
  Future<Result<String>> readAsString(String absolutePath);
}

@immutable
final class ImportedFile {
  const ImportedFile({
    required this.absolutePath,
    required this.relativePath,
    required this.sha256,
    required this.sizeBytes,
  });

  final String absolutePath;
  final String relativePath;
  final String sha256;
  final int sizeBytes;
}

final class DefaultFileService implements FileService {
  DefaultFileService();

  Directory? _cachedDocs;

  @override
  Future<Directory> appDocsDir() async {
    if (_cachedDocs != null) return _cachedDocs!;
    final dir = await getApplicationDocumentsDirectory();
    _cachedDocs = dir;
    return dir;
  }

  @override
  Future<Result<String>> sha256Of(File file) async {
    try {
      if (!await file.exists()) {
        return const Result.err(StorageFailure('Source file does not exist'));
      }
      final bytes = await file.readAsBytes();
      final digest = sha256.convert(bytes);
      return Result.ok(digest.toString());
    } catch (e) {
      return Result.err(StorageFailure('SHA-256 failed: $e'));
    }
  }

  @override
  Future<Result<ImportedFile>> importFile(File source, String ulid) async {
    try {
      if (!await source.exists()) {
        return const Result.err(StorageFailure('Source file not found'));
      }
      final hashResult = await sha256Of(source);
      if (hashResult.isErr) return Result.err(hashResult.failureOrNull!);
      final hash = hashResult.valueOrNull!;

      final docs = await appDocsDir();
      final booksDir = Directory(p.join(docs.path, 'books'));
      if (!await booksDir.exists()) {
        await booksDir.create(recursive: true);
      }

      final ext = p.extension(source.path).toLowerCase();
      // Sanitize: only allow known doc extensions, fallback to .bin
      final safeExt = _allowedExt.contains(ext) ? ext : '.bin';
      final fileName = '$ulid$safeExt';
      final destPath = p.join(booksDir.path, fileName);

      final destFile = await source.copy(destPath);
      final stat = await destFile.stat();

      return Result.ok(
        ImportedFile(
          absolutePath: destFile.path,
          relativePath: p.join('books', fileName),
          sha256: hash,
          sizeBytes: stat.size,
        ),
      );
    } catch (e) {
      return Result.err(StorageFailure('Import failed: $e'));
    }
  }

  @override
  Future<Result<void>> deleteIfExists(String absolutePath) async {
    try {
      final f = File(absolutePath);
      if (await f.exists()) await f.delete();
      return const Result<void>.ok(null);
    } catch (e) {
      return Result<void>.err(StorageFailure('Delete failed: $e'));
    }
  }

  @override
  Future<Result<String>> readAsString(String absolutePath) async {
    try {
      final f = File(absolutePath);
      if (!await f.exists()) {
        return const Result.err(StorageFailure('File not found'));
      }
      final text = await f.readAsString();
      return Result.ok(text);
    } catch (e) {
      return Result.err(StorageFailure('Read failed: $e'));
    }
  }

  static const _allowedExt = {'.pdf', '.txt', '.md', '.text'};
}

/// In-memory fake for unit tests — no disk I/O, deterministic.
final class FakeFileService implements FileService {
  FakeFileService({Directory? docsDir}) : _docsDir = docsDir;

  final Directory? _docsDir;
  final Map<String, String> _files = {};
  int _counter = 0;

  @override
  Future<Directory> appDocsDir() async =>
      _docsDir ?? Directory.systemTemp.createTemp('voicereader_test_');

  @override
  Future<Result<ImportedFile>> importFile(File source, String ulid) async {
    // Simulate copy — store empty content keyed by ulid
    final relative = 'books/$ulid.pdf';
    final abs = '/fake/$relative';
    _files[abs] = 'fake-content-$_counter';
    _counter++;
    return Result.ok(
      ImportedFile(
        absolutePath: abs,
        relativePath: relative,
        sha256: 'fake-sha256-$ulid',
        sizeBytes: 100,
      ),
    );
  }

  @override
  Future<Result<void>> deleteIfExists(String absolutePath) async {
    _files.remove(absolutePath);
    return const Result<void>.ok(null);
  }

  @override
  Future<Result<String>> readAsString(String absolutePath) async {
    final content = _files[absolutePath];
    if (content == null) return const Result.err(StorageFailure('Not found'));
    return Result.ok(content);
  }

  @override
  Future<Result<String>> sha256Of(File file) async =>
      Result.ok('fake-sha256-${file.path.hashCode}');
}
