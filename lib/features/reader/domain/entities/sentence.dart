/// A sentence entity with its span inside the (normalized) document text.
///
/// The reader highlights sentences during speech; [startChar]/[endChar] index
/// into the normalized text produced by `splitDocumentIntoSentences`.
final class Sentence {
  const Sentence({
    required this.index,
    required this.text,
    required this.startChar,
    required this.endChar,
  });

  final int index;
  final String text;
  final int startChar;
  final int endChar;

  @override
  bool operator ==(Object other) =>
      other is Sentence &&
      other.index == index &&
      other.text == text &&
      other.startChar == startChar &&
      other.endChar == endChar;

  @override
  int get hashCode => Object.hash(index, text, startChar, endChar);

  @override
  String toString() => 'Sentence($index): $text';
}
