import 'package:meta/meta.dart';

import 'package:voicereader/core/error/app_failure.dart';

/// Typed result used across every layer instead of exceptions.
///
/// `switch` exhaustively matches [Ok] and [Err] — the compiler forces every
/// call site to handle failure paths explicitly.
@immutable
sealed class Result<T> {
  const Result();

  const factory Result.ok(T value) = Ok<T>;

  const factory Result.err(AppFailure failure) = Err<T>;

  bool get isOk => this is Ok<T>;

  bool get isErr => this is Err<T>;

  T? get valueOrNull => switch (this) {
    Ok(:final value) => value,
    Err() => null,
  };

  AppFailure? get failureOrNull => switch (this) {
    Ok() => null,
    Err(:final failure) => failure,
  };

  R fold<R>(R Function(T value) onOk, R Function(AppFailure failure) onErr) =>
      switch (this) {
        Ok(:final value) => onOk(value),
        Err(:final failure) => onErr(failure),
      };

  /// Convenience for exhaustive pattern matching in UI.
  R when<R>({
    required R Function(T value) ok,
    required R Function(AppFailure failure) err,
  }) => fold(ok, err);

  /// Maps the success value, preserving failures.
  Result<R> map<R>(R Function(T value) transform) => switch (this) {
    Ok(:final value) => Result<R>.ok(transform(value)),
    Err(:final failure) => Result<R>.err(failure),
  };

  /// Chains a fallible operation — the core of use-case pipelines.
  Result<R> flatMap<R>(Result<R> Function(T value) transform) => switch (this) {
    Ok(:final value) => transform(value),
    Err(:final failure) => Result<R>.err(failure),
  };

  /// Alias for [flatMap] — more familiar in some codebases.
  Result<R> andThen<R>(Result<R> Function(T value) next) => flatMap(next);

  /// Maps the failure side (e.g. enrich with context).
  Result<T> mapErr(AppFailure Function(AppFailure failure) transform) =>
      switch (this) {
        Ok(:final value) => Result<T>.ok(value),
        Err(:final failure) => Result<T>.err(transform(failure)),
      };
}

@immutable
final class Ok<T> extends Result<T> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok<T>, value);

  @override
  String toString() => 'Ok($value)';
}

@immutable
final class Err<T> extends Result<T> {
  const Err(this.failure);

  final AppFailure failure;

  @override
  bool operator ==(Object other) => other is Err<T> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err<T>, failure);

  @override
  String toString() => 'Err($failure)';
}
