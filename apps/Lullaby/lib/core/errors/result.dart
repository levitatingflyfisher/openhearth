sealed class Result<T> {
  const Result();
}

final class Success<T> extends Result<T> {
  const Success(this.value);
  final T value;
}

final class Err<T> extends Result<T> {
  const Err(this.failure);
  final Failure failure;
}

extension ResultOrThrow<T> on Result<T> {
  /// The value of a read, or the read's failure thrown with its cause and
  /// stack. A failed read must reach the screen as an error with Try again,
  /// never as a day, a chart, a summary or an export with nothing in it.
  T orThrow() => switch (this) {
        Success(:final value) => value,
        Err(:final failure) => Error.throwWithStackTrace(
            failure.cause ?? failure,
            failure.stackTrace ?? StackTrace.current),
      };
}

abstract class Failure {
  const Failure(this.message, {this.cause, this.stackTrace});
  final String message;

  /// The exception behind this failure, kept whole so the screen can give
  /// the fleet's friendly sentence for it and show it behind Details.
  final Object? cause;
  final StackTrace? stackTrace;
}
