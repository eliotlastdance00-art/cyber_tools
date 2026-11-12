import 'package:flutter_test/flutter_test.dart';
import 'package:voicereader/core/error/app_failure.dart';
import 'package:voicereader/core/result/result.dart';

void main() {
  group('Result', () {
    test('ok holds value', () {
      const r = Result<int>.ok(42);
      expect(r.isOk, isTrue);
      expect(r.isErr, isFalse);
      expect(r.valueOrNull, 42);
      expect(r.failureOrNull, isNull);
    });

    test('err holds failure', () {
      const failure = ValidationFailure('bad');
      const r = Result<int>.err(failure);
      expect(r.isErr, isTrue);
      expect(r.isOk, isFalse);
      expect(r.failureOrNull, failure);
      expect(r.valueOrNull, isNull);
    });

    test('fold branches', () {
      const ok = Result<int>.ok(10);
      const err = Result<int>.err(ValidationFailure('x'));
      expect(ok.fold((v) => v * 2, (_) => -1), 20);
      expect(err.fold((v) => v * 2, (_) => -1), -1);
    });

    test('when branches', () {
      const ok = Result<int>.ok(5);
      expect(ok.when(ok: (v) => v + 1, err: (_) => 0), 6);
      const err = Result<int>.err(StorageFailure('fail'));
      expect(err.when(ok: (v) => v + 1, err: (e) => e.message.length), 4);
    });

    test('map transforms ok, preserves err', () {
      const ok = Result<int>.ok(7);
      const err = Result<int>.err(ValidationFailure('nope'));
      expect(ok.map((v) => v + 1), const Ok<int>(8));
      expect(err.map((v) => v + 1), const Err<int>(ValidationFailure('nope')));
    });

    test('flatMap chains success', () {
      const ok = Result<int>.ok(10);
      final res = ok.flatMap((v) => Result<String>.ok('v=$v'));
      expect(res, const Ok<String>('v=10'));
    });

    test('flatMap short-circuits on err', () {
      const err = Result<int>.err(ValidationFailure('bad'));
      final res = err.flatMap((v) => Result<String>.ok('v=$v'));
      expect(res.isErr, isTrue);
    });

    test('andThen alias works', () {
      const ok = Result<int>.ok(3);
      final res = ok.andThen((v) => Result<int>.ok(v * 3));
      expect(res.valueOrNull, 9);
    });

    test('mapErr transforms failure', () {
      const err = Result<int>.err(StorageFailure('disk'));
      final mapped = err.mapErr((_) => const UnknownFailure('wrapped'));
      expect(mapped.failureOrNull, isA<UnknownFailure>());
    });

    test('equality', () {
      expect(const Ok<int>(1), const Ok<int>(1));
      expect(const Ok<int>(1) == const Ok<int>(2), isFalse);
      expect(const Err<int>(ValidationFailure('a')), const Err<int>(ValidationFailure('a')));
    });

    test('AppFailure toString', () {
      const f = StorageFailure('disk full');
      expect(f.toString(), 'StorageFailure(disk full)');
      expect(f.code, 'StorageFailure');
    });
  });
}
