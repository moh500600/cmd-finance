/// Date helpers. All timestamps are stored as ISO-8601 strings (local time for
/// txn dates as the user entered them, UTC for created/updated/audit).
DateTime dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String nowUtc() => DateTime.now().toUtc().toIso8601String();
DateTime parseDt(Object v) => DateTime.parse(v as String);
DateTime? parseDtN(Object? v) => v == null || (v is String && v.isEmpty) ? null : DateTime.parse(v as String);

DateTime startOfWeek(DateTime d, {int firstDay = DateTime.saturday}) {
  final day = dayOnly(d);
  final diff = (day.weekday - firstDay + 7) % 7;
  return day.subtract(Duration(days: diff));
}

DateTime addMonths(DateTime d, int n) {
  final y = d.year + ((d.month - 1 + n) ~/ 12);
  final m = (d.month - 1 + n) % 12 + 1;
  final lastDay = DateTime(y, m + 1, 0).day;
  return DateTime(y, m, d.day > lastDay ? lastDay : d.day, d.hour, d.minute);
}

enum Frequency { once, daily, weekly, monthly, quarterly, yearly }

DateTime nextOccurrence(DateTime d, Frequency f) => switch (f) {
      Frequency.once => d,
      Frequency.daily => d.add(const Duration(days: 1)),
      Frequency.weekly => d.add(const Duration(days: 7)),
      Frequency.monthly => addMonths(d, 1),
      Frequency.quarterly => addMonths(d, 3),
      Frequency.yearly => addMonths(d, 12),
    };

/// Report / budget periods.
enum PeriodKind { daily, weekly, monthly, quarterly, yearly, custom }

class DateRange {
  final DateTime start; // inclusive
  final DateTime end; // exclusive
  const DateRange(this.start, this.end);
  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  static DateRange of(PeriodKind k, DateTime ref, {DateRange? custom}) {
    final d = dayOnly(ref);
    switch (k) {
      case PeriodKind.daily:
        return DateRange(d, d.add(const Duration(days: 1)));
      case PeriodKind.weekly:
        final s = startOfWeek(d);
        return DateRange(s, s.add(const Duration(days: 7)));
      case PeriodKind.monthly:
        return DateRange(DateTime(d.year, d.month), DateTime(d.year, d.month + 1));
      case PeriodKind.quarterly:
        final q = (d.month - 1) ~/ 3;
        return DateRange(DateTime(d.year, q * 3 + 1), DateTime(d.year, q * 3 + 4));
      case PeriodKind.yearly:
        return DateRange(DateTime(d.year), DateTime(d.year + 1));
      case PeriodKind.custom:
        return custom ?? DateRange(d, d.add(const Duration(days: 1)));
    }
  }

  /// The period immediately before this one (same length / same calendar unit).
  DateRange previous(PeriodKind k) => switch (k) {
        PeriodKind.monthly => DateRange(DateTime(start.year, start.month - 1), start),
        PeriodKind.quarterly => DateRange(DateTime(start.year, start.month - 3), start),
        PeriodKind.yearly => DateRange(DateTime(start.year - 1), start),
        _ => DateRange(start.subtract(end.difference(start)), start),
      };
}
