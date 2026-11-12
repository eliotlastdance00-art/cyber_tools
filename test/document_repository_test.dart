import 'package:flutter_test/flutter_test.dart';
import 'package:voicereader/features/library/data/repositories/in_memory_document_repository.dart';
import 'package:voicereader/features/library/domain/entities/document.dart';

LibraryDocument doc(String id, String title, {String? sha256, DateTime? at}) {
  final now = at ?? DateTime(2026, 1, 1, 12, 0);
  return LibraryDocument(
    id: id,
    title: title,
    sourceType: DocumentSourceType.text,
    relativePath: 'books/$id.txt',
    sha256: sha256,
    charCount: 100,
    addedAt: now,
    lastOpenedAt: now,
  );
}

void main() {
  group('InMemoryDocumentRepository', () {
    late InMemoryDocumentRepository repo;

    setUp(() => repo = InMemoryDocumentRepository());
    tearDown(() => repo.dispose());

    test('save and getAll sorted by lastOpenedAt desc', () async {
      final d1 = doc('01', 'Alpha', at: DateTime(2026, 1, 1, 10));
      final d2 = doc('02', 'Beta', at: DateTime(2026, 1, 1, 12));
      await repo.save(d1);
      await repo.save(d2);
      final res = await repo.getAll();
      expect(res.isOk, isTrue);
      final list = res.valueOrNull!;
      expect(list.map((e) => e.id), ['02', '01']);
    });

    test('findBySha256 dedupe', () async {
      final d1 = doc('01', 'Alpha', sha256: 'abc123');
      await repo.save(d1);
      final found = await repo.findBySha256('abc123');
      expect(found.valueOrNull?.id, '01');
      final notFound = await repo.findBySha256('nope');
      expect(notFound.valueOrNull, isNull);
    });

    test('getById returns null when missing', () async {
      final res = await repo.getById('missing');
      expect(res.isOk, isTrue);
      expect(res.valueOrNull, isNull);
    });

    test('delete removes doc and sha mapping', () async {
      final d1 = doc('01', 'Alpha', sha256: 'abc');
      await repo.save(d1);
      await repo.delete('01');
      expect((await repo.getAll()).valueOrNull, isEmpty);
      expect((await repo.findBySha256('abc')).valueOrNull, isNull);
    });

    test('search query filters title case-insensitive', () async {
      await repo.save(doc('01', 'Hello World'));
      await repo.save(doc('02', 'Goodbye'));
      final res = await repo.getAll(query: 'hello');
      expect(res.valueOrNull!.map((e) => e.title), ['Hello World']);
    });

    test('updateLastPosition updates index and lastOpenedAt', () async {
      final d1 = doc('01', 'Alpha', at: DateTime(2026, 1, 1, 10));
      await repo.save(d1);
      await repo.updateLastPosition('01', 5);
      final updated = (await repo.getById('01')).valueOrNull!;
      expect(updated.lastSentenceIndex, 5);
      expect(updated.lastOpenedAt.isAfter(d1.lastOpenedAt), isTrue);
    });

    test('updateLastPosition fails when missing', () async {
      final res = await repo.updateLastPosition('nope', 1);
      expect(res.isErr, isTrue);
    });

    test('watchAll emits on save', () async {
      final stream = repo.watchAll();
      final first = await stream.first;
      expect(first, isEmpty);

      // Next emission after save
      final future = stream.skip(1).first;
      await repo.save(doc('01', 'Alpha'));
      final second = await future;
      expect(second.map((e) => e.id), ['01']);
    });
  });
}
