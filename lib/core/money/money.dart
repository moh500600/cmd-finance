import 'package:decimal/decimal.dart';

/// All money in the app is [Decimal]. Never double.
/// Persisted as canonical decimal strings (SQLite TEXT, Postgres NUMERIC(20,4)).
class Money {
  Money._();

  static const int storageScale = 4;
  static final Decimal zero = Decimal.zero;
  static final Decimal hundred = Decimal.fromInt(100);

  /// Parses user/db input. Accepts Arabic-Indic digits, Arabic decimal/thousand
  /// separators and plain ASCII. Returns null for anything not a finite number.
  static Decimal? tryParse(String? raw) {
    if (raw == null) return null;
    var s = normalizeDigits(raw.trim())
        .replaceAll('٬', '')
        .replaceAll(',', '')
        .replaceAll(' ', '')
        .replaceAll('٫', '.');
    if (s.isEmpty) return null;
    if (!RegExp(r'^-?\d+(\.\d+)?$').hasMatch(s)) return null;
    return Decimal.tryParse(s);
  }

  static Decimal parse(String raw) {
    final d = tryParse(raw);
    if (d == null) throw FormatException('Invalid amount: $raw');
    return d;
  }

  /// Reads a stored value (TEXT). Null/empty -> zero.
  static Decimal fromDb(Object? v) {
    if (v == null) return Decimal.zero;
    if (v is int) return Decimal.fromInt(v);
    final s = v.toString();
    if (s.isEmpty) return Decimal.zero;
    return Decimal.parse(s);
  }

  static Decimal? fromDbNullable(Object? v) => v == null ? null : fromDb(v);

  /// Canonical stored form: rounded half-up to 4 dp, no exponent.
  static String toDb(Decimal d) => round(d).toString();

  static Decimal round(Decimal d, [int scale = storageScale]) => d.round(scale: scale);

  /// Exact division rounded to [scale] decimals (default 10 for rates).
  static Decimal div(Decimal a, Decimal b, {int scale = 10}) {
    if (b == Decimal.zero) throw ArgumentError('division by zero');
    return (a / b).toDecimal(scaleOnInfinitePrecision: scale).round(scale: scale);
  }

  /// a / b * 100, rounded to 2 dp. Returns zero when b is zero.
  static Decimal percent(Decimal a, Decimal b) {
    if (b == Decimal.zero) return Decimal.zero;
    return div(a * hundred, b, scale: 2);
  }

  static Decimal sum(Iterable<Decimal> xs) => xs.fold(Decimal.zero, (a, b) => a + b);

  static int decimalsFor(String currency) => const {'YER': 0, 'JPY': 0, 'KWD': 3, 'BHD': 3, 'OMR': 3}[currency] ?? 2;

  /// Display formatting with grouping; pure string math on the Decimal (no double).
  static String format(Decimal d, {String? currency, int? decimals, bool showSign = false}) {
    final dp = decimals ?? (currency == null ? 2 : decimalsFor(currency));
    final fixed = d.round(scale: dp).abs().toStringAsFixed(dp);
    final parts = fixed.split('.');
    final digits = parts[0];
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
      b.write(digits[i]);
    }
    var s = parts.length > 1 && dp > 0 ? '$b.${parts[1]}' : b.toString();
    if (d.round(scale: dp).sign < 0) s = '-$s';
    if (showSign && d.sign > 0) s = '+$s';
    return currency == null ? s : '$s $currency';
  }

  /// Compact form for charts/cards: 1.2K, 3.4M (display only).
  static String compact(Decimal d) {
    final a = d.abs();
    String f(Decimal x, String suf) => '${d.sign < 0 ? '-' : ''}${x.round(scale: 1).toStringAsFixed(1).replaceAll('.0', '')}$suf';
    if (a >= Decimal.fromInt(1000000000)) return f(div(a, Decimal.fromInt(1000000000), scale: 2), 'B');
    if (a >= Decimal.fromInt(1000000)) return f(div(a, Decimal.fromInt(1000000), scale: 2), 'M');
    if (a >= Decimal.fromInt(1000)) return f(div(a, Decimal.fromInt(1000), scale: 2), 'K');
    return format(d, decimals: a.isInteger ? 0 : 2);
  }

  static String normalizeDigits(String s) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    const fa = '۰۱۲۳۴۵۶۷۸۹';
    final b = StringBuffer();
    for (final ch in s.runes) {
      final c = String.fromCharCode(ch);
      final i = ar.indexOf(c);
      final j = fa.indexOf(c);
      b.write(i >= 0 ? '$i' : j >= 0 ? '$j' : c);
    }
    return b.toString();
  }
}

/// Amount + ISO currency. Arithmetic only between equal currencies.
class MoneyAmount {
  final Decimal amount;
  final String currency;
  const MoneyAmount(this.amount, this.currency);

  MoneyAmount operator +(MoneyAmount o) {
    if (o.currency != currency) throw MixedCurrencyException(currency, o.currency);
    return MoneyAmount(amount + o.amount, currency);
  }

  MoneyAmount operator -(MoneyAmount o) {
    if (o.currency != currency) throw MixedCurrencyException(currency, o.currency);
    return MoneyAmount(amount - o.amount, currency);
  }

  @override
  String toString() => Money.format(amount, currency: currency);
}

class MixedCurrencyException implements Exception {
  final String a, b;
  MixedCurrencyException(this.a, this.b);
  @override
  String toString() => 'Cannot add $a and $b without conversion';
}

/// A total in the base currency plus the currencies that could not be converted
/// (missing rate). UI must show these instead of silently dropping them.
class BaseTotal {
  final Decimal total;
  final String currency;
  final Set<String> missing;
  const BaseTotal(this.total, this.currency, [this.missing = const {}]);
  bool get complete => missing.isEmpty;
  BaseTotal operator +(BaseTotal o) => BaseTotal(total + o.total, currency, {...missing, ...o.missing});
  BaseTotal operator -(BaseTotal o) => BaseTotal(total - o.total, currency, {...missing, ...o.missing});
  static BaseTotal zero(String ccy) => BaseTotal(Decimal.zero, ccy);
}
