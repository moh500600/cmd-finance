/// Domain-level error carrying a localisation key (+ optional args) so the UI
/// shows a translated, honest message instead of a raw exception.
class AppException implements Exception {
  final String code;
  final Map<String, String> args;
  final Object? cause;
  const AppException(this.code, {this.args = const {}, this.cause});

  @override
  String toString() => 'AppException($code${args.isEmpty ? '' : ' $args'}${cause != null ? ', $cause' : ''})';
}

/// Thrown when a conversion needs a manual exchange rate the user has not
/// entered. The UI must ask the user for it — never guess.
class MissingRateException extends AppException {
  final String from, to;
  final DateTime date;
  MissingRateException(this.from, this.to, this.date)
      : super('err_missing_rate', args: {'from': from, 'to': to});
}
