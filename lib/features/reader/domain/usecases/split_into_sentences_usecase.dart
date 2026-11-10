import 'package:voicereader/core/error/app_failure.dart';
import 'package:voicereader/core/result/result.dart';
import 'package:voicereader/core/text/sentence_splitter.dart';
import 'package:voicereader/features/reader/domain/entities/sentence.dart';

/// Splits raw document text into indexed [Sentence] entities.
///
/// Returns [ValidationFailure] for empty/blank input so callers cannot
/// silently start playback on nothing.
final class SplitIntoSentencesUseCase {
  const SplitIntoSentencesUseCase();

  Result<List<Sentence>> call(String rawText) {
    if (rawText.trim().isEmpty) {
      return const Result.err(ValidationFailure('Text is empty.'));
    }
    final spans = splitDocumentIntoSentences(rawText);
    final sentences = <Sentence>[
      for (var i = 0; i < spans.length; i++)
        Sentence(
          index: i,
          text: spans[i].text,
          startChar: spans[i].startChar,
          endChar: spans[i].endChar,
        ),
    ];
    return Result.ok(sentences);
  }
}
