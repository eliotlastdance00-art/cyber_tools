/// Sentence splitting utilities — a Dart port of the `split_sentences` /
/// `normalize_text` logic from the retired Python `tts_chunks.py`, extended
/// to also report character offsets (needed for TTS sentence highlighting).
///
/// Rules:
/// * Library-wide: paragraphs (blank lines) are hard sentence boundaries.
/// * Sentence enders: `.`, `!`, `?`, `…` followed by optional closing
///   quotes/brackets and whitespace or end of text.
/// * Known abbreviations (e.g., `dr.`, `e.g.`) and single initials (A. B. …)
///   do NOT terminate a sentence.
/// * Decimals (`19.99`) and dotted acronyms (`U.S.A.`) do NOT split.
library;

const _abbreviations = <String>{
  'mr.',
  'mrs.',
  'ms.',
  'dr.',
  'prof.',
  'sr.',
  'jr.',
  'st.',
  'vs.',
  'etc.',
  'e.g.',
  'i.e.',
  'fig.',
  'no.',
  'inc.',
  'a.m.',
  'p.m.',
  'jen.',
  'professor.',
};

final _sentenceEnd = RegExp(r'''[.!?…]+["'’”»\)\]]*(?=\s|$)''', unicode: true);
final _trailingWord = RegExp(
  r'(?:[\p{L}\p{N}_]\.){2,}$|[\p{L}\p{N}_]+\.$',
  unicode: true,
);
final _dottedAcronym = RegExp(r'^(?:[A-Za-z]\.){2,}$', unicode: true);
final _singleInitial = RegExp(r'^\p{Lu}\.$', unicode: true);
final _paragraphBreak = RegExp(r'\n\n+');
final _whitespaceRun = RegExp(r'\s+');

/// Joins wrapped lines while preserving paragraph boundaries.
///
/// Intentionally does not strip line-final hyphens: a trailing hyphen may be
/// part of a genuine compound word.
String normalizeDocumentText(String input) {
  if (input.trim().isEmpty) return '';
  final normalized = input
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll('\f', '\n\n');
  final buffer = StringBuffer();
  for (final rawParagraph in normalized.split(_paragraphBreak)) {
    final cleaned = rawParagraph.trim().replaceAll(_whitespaceRun, ' ');
    if (cleaned.isEmpty) continue;
    if (buffer.isNotEmpty) buffer.write('\n\n');
    buffer.write(cleaned);
  }
  return buffer.toString();
}

/// One sentence with its exact span inside the normalized document text.
final class TextSentence {
  const TextSentence({
    required this.text,
    required this.startChar,
    required this.endChar,
  });

  final String text;
  final int startChar;
  final int endChar;

  @override
  String toString() => 'TextSentence($startChar-$endChar): $text';
}

/// Splits a single normalized paragraph into sentences.
List<TextSentence> splitSentencesInParagraph(
  String paragraph, {
  int baseOffset = 0,
}) {
  final sentences = <TextSentence>[];
  var start = 0;
  for (final match in _sentenceEnd.allMatches(paragraph)) {
    final end = match.end;
    final punctuation = match.group(0)!;
    if (punctuation.startsWith('.')) {
      final before = paragraph.substring(start, match.start + 1);
      final word = _trailingWord.firstMatch(before);
      final tokenRaw = word == null ? '' : word.group(0)!;
      final token = tokenRaw.toLowerCase();
      if (_abbreviations.contains(token)) continue;
      if (_dottedAcronym.hasMatch(token)) continue;
      // Single initials (A. Smith) do not end a sentence. The original
      // Python lower-cased the token before testing case, which silently
      // disabled this guard; we test the raw token instead (and accept any
      // Unicode uppercase letter).
      final afterMatch = paragraph.substring(end).trim().isNotEmpty;
      if (_singleInitial.hasMatch(tokenRaw) && afterMatch) continue;
    }
    _addTrimmed(sentences, paragraph, start, end, baseOffset);
    start = end;
  }
  _addTrimmed(sentences, paragraph, start, paragraph.length, baseOffset);
  return sentences;
}

void _addTrimmed(
  List<TextSentence> out,
  String paragraph,
  int rawStart,
  int rawEnd,
  int baseOffset,
) {
  var start = rawStart;
  var end = rawEnd;
  while (start < end && _isSpace(paragraph.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isSpace(paragraph.codeUnitAt(end - 1))) {
    end--;
  }
  if (start >= end) return;
  out.add(
    TextSentence(
      text: paragraph.substring(start, end),
      startChar: baseOffset + start,
      endChar: baseOffset + end,
    ),
  );
}

bool _isSpace(int unit) {
  // Space, tab, LF, CR and friends (\s equivalents for ASCII whitespace).
  return unit == 0x20 ||
      unit == 0x09 ||
      unit == 0x0A ||
      unit == 0x0D ||
      unit == 0x0B ||
      unit == 0x0C ||
      unit == 0xA0;
}

/// Splits raw document text into sentences across paragraph boundaries.
///
/// Paragraphs always become sentence boundaries even without terminal
/// punctuation. Offsets index into the *normalized* text; call sites must
/// normalize with [normalizeDocumentText] (or use [splitDocumentIntoSentences]).
List<TextSentence> splitDocumentIntoSentences(String raw) {
  final normalized = normalizeDocumentText(raw);
  if (normalized.isEmpty) return const [];
  final out = <TextSentence>[];
  var start = 0;
  for (final match in _paragraphBreak.allMatches(normalized)) {
    out.addAll(
      splitSentencesInParagraph(
        normalized.substring(start, match.start),
        baseOffset: start,
      ),
    );
    start = match.end;
  }
  out.addAll(
    splitSentencesInParagraph(normalized.substring(start), baseOffset: start),
  );
  return out;
}
