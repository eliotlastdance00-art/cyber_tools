/// Base type for all typed failures in VoiceReader.
///
/// Layers never throw across boundaries; repositories and use cases return
/// [AppFailure] inside `Result<T>`. Keeps error paths explicit and testable.
sealed class AppFailure {
  const AppFailure();

  /// Human-readable summary (English; UI may map to localized copy).
  String get message;

  @override
  bool operator ==(Object other) =>
      runtimeType == other.runtimeType &&
      other is AppFailure &&
      other.message == message;

  @override
  int get hashCode => Object.hash(runtimeType, message);
}

final class StorageFailure extends AppFailure {
  const StorageFailure([this.detail = 'Storage operation failed']);

  final String detail;

  @override
  String get message => detail;
}

final class PdfFailure extends AppFailure {
  const PdfFailure([this.detail = 'Could not read the PDF']);

  final String detail;

  @override
  String get message => detail;
}

final class TtsFailure extends AppFailure {
  const TtsFailure([this.detail = 'Speech engine failed']);

  final String detail;

  @override
  String get message => detail;
}

final class PurchaseFailure extends AppFailure {
  const PurchaseFailure([this.detail = 'Purchase did not complete']);

  final String detail;

  @override
  String get message => detail;
}

final class ValidationFailure extends AppFailure {
  const ValidationFailure([this.detail = 'Invalid input']);

  final String detail;

  @override
  String get message => detail;
}

final class PermissionFailure extends AppFailure {
  const PermissionFailure([this.detail = 'Permission denied']);

  final String detail;

  @override
  String get message => detail;
}

final class UnknownFailure extends AppFailure {
  const UnknownFailure([this.detail = 'Something went wrong']);

  final String detail;

  @override
  String get message => detail;
}
