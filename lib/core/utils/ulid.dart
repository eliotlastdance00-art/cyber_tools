import 'dart:math';

/// Minimal ULID generator — no external dependency.
/// ULID = 48-bit timestamp (ms since epoch) + 80-bit randomness,
/// Crockford base32 encoded (26 chars), lexicographically sortable.
String generateUlid([DateTime? at]) {
  final time = (at ?? DateTime.now()).millisecondsSinceEpoch;
  final rand = Random.secure();

  const alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  final buf = StringBuffer();

  // 10 chars for timestamp (48 bits)
  var t = time;
  final timeChars = List.filled(10, '0');
  for (var i = 9; i >= 0; i--) {
    timeChars[i] = alphabet[t % 32];
    t ~/= 32;
  }
  buf.writeAll(timeChars);

  // 16 chars for randomness (80 bits)
  for (var i = 0; i < 16; i++) {
    buf.write(alphabet[rand.nextInt(32)]);
  }

  return buf.toString();
}
