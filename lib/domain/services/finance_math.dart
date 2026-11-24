import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../entities/planning.dart';
import '../entities/transaction.dart';

/// Pure money math (all Decimal). Unit-tested in test/money_math_test.dart.
class FinanceMath {
  FinanceMath._();

  /// Simple interest: principal × rate% × days/365 over start→due.
  static Decimal simpleInterest(Decimal principal, Decimal annualRatePct, DateTime start, DateTime? due) {
    if (annualRatePct.sign == 0 || due == null) return Decimal.zero;
    final days = dayOnly(due).difference(dayOnly(start)).inDays;
    if (days <= 0) return Decimal.zero;
    return Money.round(Money.div(principal * annualRatePct * Decimal.fromInt(days), Decimal.fromInt(36500), scale: 8));
  }

  static DebtSummary debtSummary(Debt d, Decimal paid) {
    final interest = simpleInterest(d.principal, d.interestRate, d.startDate, d.dueDate);
    final total = d.principal + interest;
    final n = d.installments < 1 ? 1 : d.installments;
    final each = Money.round(Money.div(total, Decimal.fromInt(n), scale: 8));
    final schedule = <Installment>[];
    var cumulative = Decimal.zero;
    var date = d.startDate;
    for (var i = 1; i <= n; i++) {
      date = (n == 1 && d.dueDate != null) ? d.dueDate! : nextOccurrence(date, d.installmentFrequency);
      if (i == n && d.dueDate != null) date = d.dueDate!.isAfter(date) ? date : d.dueDate!;
      final amt = i == n ? total - each * Decimal.fromInt(n - 1) : each; // last absorbs rounding
      cumulative += amt;
      schedule.add(Installment(i, date, amt, paid >= cumulative));
    }
    return DebtSummary(d, interest, paid, schedule);
  }

  /// Sum of base amounts for posted transactions of [type] (income/expense only make sense here).
  static Decimal sumBase(Iterable<FinTransaction> txns, TxnType type, {DateRange? range}) => Money.sum(txns
      .where((t) => !t.isVoid && t.type == type && (range == null || range.contains(t.txnDate)))
      .map((t) => t.baseAmount));

  static Decimal mean(List<Decimal> xs) => xs.isEmpty ? Decimal.zero : Money.div(Money.sum(xs), Decimal.fromInt(xs.length), scale: 6);

  /// Population standard deviation via Newton's method on Decimal.
  static Decimal stdDev(List<Decimal> xs) {
    if (xs.length < 2) return Decimal.zero;
    final m = mean(xs);
    final variance = Money.div(Money.sum(xs.map((x) => (x - m) * (x - m))), Decimal.fromInt(xs.length), scale: 8);
    return sqrt(variance);
  }

  static Decimal sqrt(Decimal v) {
    if (v.sign <= 0) return Decimal.zero;
    var x = v > Decimal.one ? Money.div(v, Decimal.fromInt(2), scale: 8) : Decimal.one;
    for (var i = 0; i < 60; i++) {
      final nx = Money.div(x + Money.div(v, x, scale: 12), Decimal.fromInt(2), scale: 12);
      if ((nx - x).abs() < Decimal.parse('0.000001')) return nx.round(scale: 6);
      x = nx;
    }
    return x.round(scale: 6);
  }

  /// Expenses above mean + 2σ of their own category (needs ≥ 5 samples in the category).
  static List<FinTransaction> unusualExpenses(List<FinTransaction> txns, {int minSamples = 5}) {
    final byCat = <String?, List<FinTransaction>>{};
    for (final t in txns.where((t) => !t.isVoid && t.type == TxnType.expense)) {
      byCat.putIfAbsent(t.categoryId, () => []).add(t);
    }
    final out = <FinTransaction>[];
    for (final list in byCat.values) {
      if (list.length < minSamples) continue;
      final xs = list.map((t) => t.baseAmount).toList();
      final threshold = mean(xs) + stdDev(xs) * Decimal.fromInt(2);
      out.addAll(list.where((t) => t.baseAmount > threshold));
    }
    out.sort((a, b) => b.baseAmount.compareTo(a.baseAmount));
    return out;
  }

  /// Budget suggestion per category = average monthly spend over the last 3
  /// FULL months (months with no spend count as zero), rounded up to a whole unit.
  static Map<String?, Decimal> budgetSuggestions(List<FinTransaction> txns, DateTime now) {
    final end = DateTime(now.year, now.month);
    final start = DateTime(now.year, now.month - 3);
    final totals = <String?, Decimal>{};
    for (final t in txns.where((t) => !t.isVoid && t.type == TxnType.expense && !t.txnDate.isBefore(start) && t.txnDate.isBefore(end))) {
      totals[t.categoryId] = (totals[t.categoryId] ?? Decimal.zero) + t.baseAmount;
    }
    return totals.map((k, v) => MapEntry(k, Money.div(v, Decimal.fromInt(3), scale: 4).ceil()));
  }

  /// Totals per category key for expenses in [range] (base currency), sorted desc.
  static List<MapEntry<String?, Decimal>> byCategory(Iterable<FinTransaction> txns, DateRange range, {TxnType type = TxnType.expense}) {
    final m = <String?, Decimal>{};
    for (final t in txns.where((t) => !t.isVoid && t.type == type && range.contains(t.txnDate))) {
      m[t.categoryId] = (m[t.categoryId] ?? Decimal.zero) + t.baseAmount;
    }
    return m.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  }

  /// Savings rate % = (income − expense) / income.
  static Decimal savingsRate(Decimal income, Decimal expense) => Money.percent(income - expense, income);
}
