import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';

class Currency {
  final String code;
  final String nameAr;
  final String nameEn;
  final String symbol;
  final int decimals;
  final bool builtin;
  const Currency({required this.code, required this.nameAr, required this.nameEn, required this.symbol, required this.decimals, this.builtin = false});

  String name(bool ar) => ar ? nameAr : nameEn;

  factory Currency.fromMap(Map<String, Object?> m) => Currency(
      code: m['code'] as String, nameAr: m['name_ar'] as String, nameEn: m['name_en'] as String,
      symbol: m['symbol'] as String, decimals: m['decimals'] as int, builtin: (m['builtin'] as int? ?? 0) == 1);

  Map<String, Object?> toMap() => {'code': code, 'name_ar': nameAr, 'name_en': nameEn, 'symbol': symbol, 'decimals': decimals, 'builtin': builtin ? 1 : 0};
}

/// A manually entered rate: 1 [from] = [rate] [to], valid from [rateDate].
/// History is append-only; the latest rate on/before a date is used.
class ExchangeRate {
  final String id;
  final String userId;
  final String from;
  final String to;
  final Decimal rate;
  final String source;
  final DateTime rateDate;
  final DateTime createdAt;
  const ExchangeRate({required this.id, required this.userId, required this.from, required this.to, required this.rate, required this.source, required this.rateDate, required this.createdAt});

  factory ExchangeRate.fromMap(Map<String, Object?> m) => ExchangeRate(
      id: m['id'] as String, userId: m['user_id'] as String, from: m['from_ccy'] as String, to: m['to_ccy'] as String,
      rate: Money.fromDb(m['rate']), source: m['source'] as String, rateDate: DateTime.parse(m['rate_date'] as String),
      createdAt: DateTime.parse(m['created_at'] as String));

  Map<String, Object?> toMap() => {'id': id, 'user_id': userId, 'from_ccy': from, 'to_ccy': to, 'rate': rate.toString(), 'source': source,
        'rate_date': rateDate.toIso8601String(), 'created_at': createdAt.toIso8601String()};
}

/// Result of converting with a specific stored rate.
class Conversion {
  final Decimal amount; // converted, rounded to storage scale
  final Decimal rate; // effective multiplier used (from -> to)
  final String? rateId; // stored rate row used (null when same currency)
  final bool inverted; // true when the stored rate was to->from and we used 1/rate
  final DateTime? rateDate;
  final String? source;
  const Conversion(this.amount, this.rate, this.rateId, {this.inverted = false, this.rateDate, this.source});
}
