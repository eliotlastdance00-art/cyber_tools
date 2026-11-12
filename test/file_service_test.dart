import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:voicereader/core/platform/file_service.dart';
import 'package:voicereader/core/utils/ulid.dart';

void main() {
  group('FakeFileService', () {
    test('importFile returns deterministic sha', () async {
      final svc = FakeFileService();
      final f = File('/tmp/fake.txt');
      final res = await svc.importFile(f, 'ULID1');
      expect(res.isOk, isTrue);
      final imp = res.valueOrNull!;
      expect(imp.relativePath, 'books/ULID1.pdf');
      expect(imp.sha256, 'fake-sha256-ULID1');
    });

    test('sha256Of returns fake hash', () async {
      final svc = FakeFileService();
      final res = await svc.sha256Of(File('/tmp/a.txt'));
      expect(res.isOk, isTrue);
      expect(res.valueOrNull, contains('fake-sha256'));
    });

    test('deleteIfExists clears file', () async {
      final svc = FakeFileService();
      final f = File('/tmp/fake.txt');
      await svc.importFile(f, 'ULID2');
      final del = await svc.deleteIfExists('/fake/books/ULID2.pdf');
      expect(del.isOk, isTrue);
      final read = await svc.readAsString('/fake/books/ULID2.pdf');
      expect(read.isErr, isTrue);
    });
  });

  group('Ulid generator', () {
    test('generates 26-char sortable ulid', () {
      final ulid1 = generateUlid();
      final ulid2 = generateUlid();
      expect(ulid1.length, 26);
      expect(ulid2.length, 26);
      expect(RegExp(r'^[0-9A-Z]{26}$').hasMatch(ulid1), isTrue);
      expect(ulid1 != ulid2, isTrue);
    });

    test('ulid with fixed time is deterministic timestamp prefix', () {
      final fixed = DateTime.fromMillisecondsSinceEpoch(0);
      final u = generateUlid(fixed);
      expect(u.length, 26);
      expect(u.startsWith('0000000000'), isTrue);
    });
  });
}
