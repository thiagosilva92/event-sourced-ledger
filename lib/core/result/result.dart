import 'package:meta/meta.dart';

/// A total, allocation-light alternative to throwing for expected failures.
///
/// Use [Result] when a caller is expected to handle the failure (validation,
/// a rejected command, a conflict). Keep throwing for programmer errors and
/// truly exceptional conditions.
///
/// ```dart
/// final outcome = handler.handle(command);
/// switch (outcome) {
///   case Ok(:final value):   ...
///   case Err(:final failure): ...
/// }
/// ```
@immutable
sealed class Result<T, F> {
  const Result();

  /// Wraps a success value.
  const factory Result.ok(T value) = Ok<T, F>;

  /// Wraps a failure value.
  const factory Result.err(F failure) = Err<T, F>;

  bool get isOk => this is Ok<T, F>;
  bool get isErr => this is Err<T, F>;

  /// The success value, or `null` for a failure.
  T? get valueOrNull => switch (this) {
    Ok<T, F>(:final value) => value,
    Err<T, F>() => null,
  };

  /// The failure value, or `null` for a success.
  F? get failureOrNull => switch (this) {
    Ok<T, F>() => null,
    Err<T, F>(:final failure) => failure,
  };

  /// Transforms the success value, leaving a failure untouched.
  Result<R, F> map<R>(R Function(T value) transform) => switch (this) {
    Ok<T, F>(:final value) => Ok(transform(value)),
    Err<T, F>(:final failure) => Err(failure),
  };

  /// Chains another fallible step onto a success.
  Result<R, F> flatMap<R>(Result<R, F> Function(T value) next) =>
      switch (this) {
        Ok<T, F>(:final value) => next(value),
        Err<T, F>(:final failure) => Err(failure),
      };

  /// Transforms the failure value, leaving a success untouched.
  Result<T, G> mapErr<G>(G Function(F failure) transform) => switch (this) {
    Ok<T, F>(:final value) => Ok(value),
    Err<T, F>(:final failure) => Err(transform(failure)),
  };

  /// Collapses both branches to a single value.
  R fold<R>(R Function(T value) onOk, R Function(F failure) onErr) =>
      switch (this) {
        Ok<T, F>(:final value) => onOk(value),
        Err<T, F>(:final failure) => onErr(failure),
      };

  /// Returns the success value or [fallback] on failure.
  T getOrElse(T Function(F failure) fallback) => switch (this) {
    Ok<T, F>(:final value) => value,
    Err<T, F>(:final failure) => fallback(failure),
  };
}

final class Ok<T, F> extends Result<T, F> {
  const Ok(this.value);

  final T value;

  @override
  bool operator ==(Object other) => other is Ok<T, F> && other.value == value;

  @override
  int get hashCode => Object.hash(Ok, value);

  @override
  String toString() => 'Ok($value)';
}

final class Err<T, F> extends Result<T, F> {
  const Err(this.failure);

  final F failure;

  @override
  bool operator ==(Object other) =>
      other is Err<T, F> && other.failure == failure;

  @override
  int get hashCode => Object.hash(Err, failure);

  @override
  String toString() => 'Err($failure)';
}
