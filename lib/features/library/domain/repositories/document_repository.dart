import 'package:voicereader/core/result/result.dart';
import 'package:voicereader/features/library/domain/entities/document.dart';

/// Contract for the library data layer — implemented in `data/`.
abstract interface class DocumentRepository {
  Future<Result<List<LibraryDocument>>> getAll({String? query});
  Future<Result<LibraryDocument?>> getById(String id);
  Future<Result<LibraryDocument>> save(LibraryDocument doc);
  Future<Result<void>> delete(String id);
  Future<Result<LibraryDocument?>> findBySha256(String sha256);
  Future<Result<void>> updateLastPosition(String id, int sentenceIndex);
  Stream<List<LibraryDocument>> watchAll({String? query});

  // Plain text cache (drift `document_text` table in production).
  Future<Result<void>> saveText(String docId, String plainText);
  Future<Result<String?>> getText(String docId);
}
