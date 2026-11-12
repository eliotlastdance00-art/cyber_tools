import 'dart:async';

import 'package:voicereader/core/error/app_failure.dart';
import 'package:voicereader/core/result/result.dart';
import 'package:voicereader/features/library/domain/entities/document.dart';
import 'package:voicereader/features/library/domain/repositories/document_repository.dart';

/// In-memory repository — used in tests and as fallback before drift lands.
/// Thread-safe for single-isolate use (Flutter is single-threaded).
final class InMemoryDocumentRepository implements DocumentRepository {
  final Map<String, LibraryDocument> _byId = {};
  final Map<String, String> _shaToId = {};
  final Map<String, String> _texts = {};
  final _controller = StreamController<List<LibraryDocument>>.broadcast();

  void _emit() => _controller.add(_sorted());

  List<LibraryDocument> _sorted() {
    final list = _byId.values.toList()
      ..sort((a, b) => b.lastOpenedAt.compareTo(a.lastOpenedAt));
    return List.unmodifiable(list);
  }

  List<LibraryDocument> _filtered(String? query) {
    if (query == null || query.trim().isEmpty) return _sorted();
    final q = query.toLowerCase();
    return _sorted().where((d) => d.title.toLowerCase().contains(q)).toList();
  }

  @override
  Future<Result<List<LibraryDocument>>> getAll({String? query}) async {
    try {
      return Result.ok(_filtered(query));
    } catch (e) {
      return Result.err(StorageFailure('getAll failed: $e'));
    }
  }

  @override
  Future<Result<LibraryDocument?>> getById(String id) async {
    try {
      return Result.ok(_byId[id]);
    } catch (e) {
      return Result.err(StorageFailure('getById failed: $e'));
    }
  }

  @override
  Future<Result<LibraryDocument?>> findBySha256(String sha256) async {
    try {
      final id = _shaToId[sha256];
      if (id == null) return const Result<LibraryDocument?>.ok(null);
      return Result<LibraryDocument?>.ok(_byId[id]);
    } catch (e) {
      return Result<LibraryDocument?>.err(StorageFailure('findBySha256 failed: $e'));
    }
  }

  @override
  Future<Result<LibraryDocument>> save(LibraryDocument doc) async {
    try {
      _byId[doc.id] = doc;
      if (doc.sha256 != null) _shaToId[doc.sha256!] = doc.id;
      _emit();
      return Result.ok(doc);
    } catch (e) {
      return Result.err(StorageFailure('save failed: $e'));
    }
  }

  @override
  Future<Result<void>> saveText(String docId, String plainText) async {
    try {
      if (!_byId.containsKey(docId)) {
        return const Result<void>.err(StorageFailure('Document not found for text'));
      }
      _texts[docId] = plainText;
      return const Result<void>.ok(null);
    } catch (e) {
      return Result<void>.err(StorageFailure('saveText failed: $e'));
    }
  }

  @override
  Future<Result<String?>> getText(String docId) async {
    try {
      return Result<String?>.ok(_texts[docId]);
    } catch (e) {
      return Result<String?>.err(StorageFailure('getText failed: $e'));
    }
  }

  @override
  Future<Result<void>> delete(String id) async {
    try {
      final doc = _byId.remove(id);
      if (doc?.sha256 != null) _shaToId.remove(doc!.sha256);
      _texts.remove(id);
      _emit();
      return const Result<void>.ok(null);
    } catch (e) {
      return Result<void>.err(StorageFailure('delete failed: $e'));
    }
  }

  @override
  Future<Result<void>> updateLastPosition(String id, int sentenceIndex) async {
    try {
      final doc = _byId[id];
      if (doc == null) {
        return const Result<void>.err(StorageFailure('Document not found'));
      }
      _byId[id] = doc.copyWith(lastSentenceIndex: sentenceIndex, lastOpenedAt: DateTime.now());
      _emit();
      return const Result<void>.ok(null);
    } catch (e) {
      return Result<void>.err(StorageFailure('update position failed: $e'));
    }
  }

  @override
  Stream<List<LibraryDocument>> watchAll({String? query}) async* {
    yield _filtered(query);
    yield* _controller.stream.map((_) => _filtered(query));
  }

  void dispose() => _controller.close();
}
