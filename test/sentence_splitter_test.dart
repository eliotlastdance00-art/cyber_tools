import 'package:flutter_test/flutter_test.dart';
import 'package:voicereader/core/error/app_failure.dart';
import 'package:voicereader/core/result/result.dart';
import 'package:voicereader/core/text/sentence_splitter.dart';
import 'package:voicereader/features/reader/domain/usecases/split_into_sentences_usecase.dart';

void main() {
  group('normalizeDocumentText', () {
    test('collapses CRLF, CR and form feeds into paragraph breaks', () {
      expect(
        normalizeDocumentText('One.\r\n\r\nTwo.\fThree.'),
        'One.\n\nTwo.\n\nThree.',
      );
    });

    test('joins wrapped lines with a single space', () {
      expect(
        normalizeDocumentText('Hello    world\nagain'),
        'Hello world again',
      );
    });

    test('drops empty paragraphs and trims edges', () {
      expect(
        normalizeDocumentText('\n\n  Alpha.  \n\n\nBeta.\n'),
        'Alpha.\n\nBeta.',
      );
    });

    test('returns empty string for blank input', () {
      expect(normalizeDocumentText('   \n\n  '), '');
    });
  });

  group('splitDocumentIntoSentences', () {
    List<String> texts(String raw) => splitDocumentIntoSentences(
      raw,
    ).map((s) => s.text).toList(growable: false);

    test('splits a simple pair of sentences', () {
      expect(texts('Hello world. How are you?'), [
        'Hello world.',
        'How are you?',
      ]);
    });

    test('empty input yields no sentences', () {
      expect(texts(''), isEmpty);
      expect(texts('   '), isEmpty);
    });

    test('text without terminal punctuation is one sentence', () {
      expect(texts('no ending punctuation here'), [
        'no ending punctuation here',
      ]);
    });

    test('decimals do not split', () {
      expect(texts('It costs 19.99 today. Cheap.'), [
        'It costs 19.99 today.',
        'Cheap.',
      ]);
      expect(texts('The value is 3.5. Done.'), ['The value is 3.5.', 'Done.']);
    });

    test('abbreviations do not terminate sentences', () {
      expect(texts('Dr. Smith went home. He slept.'), [
        'Dr. Smith went home.',
        'He slept.',
      ]);
      expect(texts('Mr. and Mrs. Smith visited. They stayed.'), [
        'Mr. and Mrs. Smith visited.',
        'They stayed.',
      ]);
    });

    test('e.g. and i.e. survive mid-sentence', () {
      expect(texts('Use a plant, e.g. basil. It likes sun.'), [
        'Use a plant, e.g. basil.',
        'It likes sun.',
      ]);
      expect(texts('Read the manual, i.e. all of it. Twice.'), [
        'Read the manual, i.e. all of it.',
        'Twice.',
      ]);
    });

    test('dotted acronyms do not split', () {
      expect(texts('U.S.A. won. They celebrated.'), [
        'U.S.A. won.',
        'They celebrated.',
      ]);
    });

    test('single capital initial does not split mid-sentence', () {
      expect(texts('A. Smith left. She drove.'), [
        'A. Smith left.',
        'She drove.',
      ]);
    });

    test('inc. at end of text ends the sentence, not splits it', () {
      expect(texts('He works at google inc.'), ['He works at google inc.']);
    });

    test('multiple terminal punctuation stays together', () {
      expect(texts('Wow!!! Great?! Yes.'), ['Wow!!!', 'Great?!', 'Yes.']);
    });

    test('ellipsis acts as a sentence ender', () {
      expect(texts('Wait… Really? Yes.'), ['Wait…', 'Really?', 'Yes.']);
    });

    test('closing quotes and brackets are consumed into the sentence', () {
      expect(texts('He said "stop." She left.'), [
        'He said "stop."',
        'She left.',
      ]);
      expect(texts('It broke (finally). Next step.'), [
        'It broke (finally).',
        'Next step.',
      ]);
    });

    test('paragraph breaks force sentence boundaries without punctuation', () {
      expect(texts('Line one\n\nLine two'), ['Line one', 'Line two']);
    });

    test('a.m. and p.m. are not sentence enders', () {
      expect(texts('Meet at 7 a.m. sharp. Do not be late.'), [
        'Meet at 7 a.m. sharp.',
        'Do not be late.',
      ]);
    });

    test('mixed newlines and spaces normalize before splitting', () {
      expect(texts('Hello   \n   world. Next\n sentence.'), [
        'Hello world.',
        'Next sentence.',
      ]);
    });

    test('question and exclamation marks end sentences', () {
      expect(texts('Really? Yes! Done.'), ['Really?', 'Yes!', 'Done.']);
    });

    test('Cyrillic/Turkmen text round-trips offset slicing', () {
      const raw = 'Привет. Это тест. Sagboluň.';
      final normalized = normalizeDocumentText(raw);
      final spans = splitDocumentIntoSentences(raw);
      expect(spans, hasLength(3));
      expect(normalized, 'Привет. Это тест. Sagboluň.');
      for (final span in spans) {
        expect(normalized.substring(span.startChar, span.endChar), span.text);
      }
    });

    test('offsets index into normalized text across paragraphs', () {
      const raw = 'First one.\n\nSecond one. Third one.';
      final normalized = normalizeDocumentText(raw);
      final spans = splitDocumentIntoSentences(raw);
      expect(spans.map((s) => s.text), [
        'First one.',
        'Second one.',
        'Third one.',
      ]);
      for (final span in spans) {
        expect(normalized.substring(span.startChar, span.endChar), span.text);
      }
    });

    test('trailing newlines do not attach to sentence text', () {
      expect(texts('One.\n\nTwo.').map((t) => t).toList(), ['One.', 'Two.']);
    });
  });

  group('SplitIntoSentencesUseCase', () {
    const useCase = SplitIntoSentencesUseCase();

    test('blank input maps to ValidationFailure', () {
      final result = useCase.call('   ');
      expect(result.isErr, isTrue);
      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(result.failureOrNull?.message, 'Text is empty.');
    });

    test('valid input yields indexed sentences', () {
      final result = useCase.call('Hello world. Bye now.');
      expect(result.isOk, isTrue);
      final sentences = result.valueOrNull!;
      expect(sentences.map((s) => s.index), [0, 1]);
      expect(sentences.map((s) => s.text), ['Hello world.', 'Bye now.']);
      for (final s in sentences) {
        expect(s.endChar, greaterThan(s.startChar));
      }
    });

    test('result equality and fold behave', () {
      const failure = ValidationFailure('nope');
      const err = Result<int>.err(failure);
      const ok = Result<int>.ok(7);
      expect(err, const Err<int>(failure));
      expect(ok, const Ok<int>(7));
      expect(ok.fold((v) => v * 2, (_) => -1), 14);
      expect(err.fold((v) => v * 2, (_) => -1), -1);
      expect(ok.map((v) => v + 1), const Ok<int>(8));
      expect(err.map((v) => v + 1), const Err<int>(failure));
    });
  });
}
