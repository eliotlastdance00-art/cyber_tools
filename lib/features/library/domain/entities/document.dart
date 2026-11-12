import 'package:meta/meta.dart';

/// Source type of a library document.
enum DocumentSourceType { pdf, text }

/// Domain entity — persisted in drift `documents` table.
@immutable
final class LibraryDocument {
  const LibraryDocument({
    required this.id,
    required this.title,
    required this.sourceType,
    required this.relativePath,
    required this.charCount,
    required this.addedAt,
    required this.lastOpenedAt,
    this.sha256,
    this.lastSentenceIndex,
  });

  final String id; // ULID
  final String title;
  final DocumentSourceType sourceType;
  final String relativePath; // e.g. books/01J...pdf
  final String? sha256;
  final int charCount;
  final DateTime addedAt;
  final DateTime lastOpenedAt;
  final int? lastSentenceIndex;

  double get progress {
    if (charCount == 0) return 0;
    // Approximate via sentence index is refined in Phase 5 with totalSentences.
    // For now: if no position, 0; if has position, at least a small fraction.
    if (lastSentenceIndex == null) return 0;
    return (lastSentenceIndex! + 1) / (charCount / 200 + 1).clamp(1, 1000);
  }

  LibraryDocument copyWith({
    String? id,
    String? title,
    DocumentSourceType? sourceType,
    String? relativePath,
    String? sha256,
    int? charCount,
    DateTime? addedAt,
    DateTime? lastOpenedAt,
    int? lastSentenceIndex,
  }) =>
      LibraryDocument(
        id: id ?? this.id,
        title: title ?? this.title,
        sourceType: sourceType ?? this.sourceType,
        relativePath: relativePath ?? this.relativePath,
        sha256: sha256 ?? this.sha256,
        charCount: charCount ?? this.charCount,
        addedAt: addedAt ?? this.addedAt,
        lastOpenedAt: lastOpenedAt ?? this.lastOpenedAt,
        lastSentenceIndex: lastSentenceIndex ?? this.lastSentenceIndex,
      );

  @override
  bool operator ==(Object other) =>
      other is LibraryDocument &&
      other.id == id &&
      other.title == title &&
      other.sourceType == sourceType &&
      other.relativePath == relativePath &&
      other.sha256 == sha256 &&
      other.charCount == charCount &&
      other.addedAt == addedAt &&
      other.lastOpenedAt == lastOpenedAt &&
      other.lastSentenceIndex == lastSentenceIndex;

  @override
  int get hashCode => Object.hash(
    id,
    title,
    sourceType,
    relativePath,
    sha256,
    charCount,
    addedAt,
    lastOpenedAt,
    lastSentenceIndex,
  );

  @override
  String toString() => 'LibraryDocument($id, $title, $sourceType, $charCount)';
}
