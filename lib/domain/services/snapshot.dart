import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../entities/account.dart';
import '../entities/holdings.dart';
import '../entities/planning.dart';
import '../entities/transaction.dart';
import 'finance_math.dart';

/// A value in its own currency plus its base-currency value (null = no rate).
class Valued<T> {
  final T item;
  final Decimal amount;
  final String currency;
  final Decimal? base;
  const Valued(this.item, this.amount, this.currency, this.base);
}

BaseTotal sumValued(Iterable<Valued> xs, String base) {
  var total = Decimal.zero;
  final missing = <String>{};
  for (final x in xs) {
    if (x.base == null) {
      missing.add(x.currency);
    } else {
      total += x.base!;
    }
  }
  return BaseTotal(total, base, missing);
}

/// Everything the dashboard, reports and assistant need, already converted to
/// the base currency with TODAY's latest manual rate (missing ones flagged).
class FinanceSnapshot {
  final String base;
  final DateTime now;
  final List<Valued<Account>> accounts;
  final List<Valued<GoalStatus>> goals;
  final List<Valued<DebtSummary>> debts; // remaining
  final List<Valued<Asset>> assets;
  final List<Valued<InvestmentPerformance>> investments;
  final List<FinTransaction> txns; // posted, all time
  final List<BudgetStatus> budgets;
  final List<Bill> bills;
  final Map<String, Category> categories;
  final List<RecurringRule> recurring;
  const FinanceSnapshot({required this.base, required this.now, required this.accounts, required this.goals, required this.debts, required this.assets,
      required this.investments, required this.txns, required this.budgets, required this.bills, required this.categories, this.recurring = const []});

  Iterable<Valued<Account>> get activeAccounts => accounts.where((a) => a.item.isActive);
  BaseTotal accountsTotal({Set<AccountType>? types}) => sumValued(activeAccounts.where((a) => types == null || types.contains(a.item.type)), base);
  BaseTotal get goalsTotal => sumValued(goals, base);
  BaseTotal get assetsTotal => sumValued(assets, base);
  BaseTotal get investmentsTotal => sumValued(investments, base);
  BaseTotal debtsTotal(DebtDirection dir) => sumValued(debts.where((d) => d.item.debt.direction == dir && d.item.remaining.sign > 0), base);
}

class DashboardStats {
  final BaseTotal totalAssets, cash, bank, income, expense, netCashFlow, iOwe, owedToMe, netWorth;
  final Decimal savingsRate;
  const DashboardStats({required this.totalAssets, required this.cash, required this.bank, required this.income, required this.expense,
      required this.netCashFlow, required this.iOwe, required this.owedToMe, required this.netWorth, required this.savingsRate});

  /// Income/expense/cash flow/savings rate are for [period]; balances are current.
  /// Transfers, loans and savings moves never count as income or expense.
  static DashboardStats compute(FinanceSnapshot s, DateRange period) {
    final income = BaseTotal(FinanceMath.sumBase(s.txns, TxnType.income, range: period), s.base);
    final expense = BaseTotal(FinanceMath.sumBase(s.txns, TxnType.expense, range: period), s.base);
    final totalAssets = s.accountsTotal() + s.goalsTotal + s.investmentsTotal + s.assetsTotal;
    final iOwe = s.debtsTotal(DebtDirection.iOwe), owed = s.debtsTotal(DebtDirection.owedToMe);
    return DashboardStats(
      totalAssets: totalAssets,
      cash: s.accountsTotal(types: {AccountType.cash}),
      bank: s.accountsTotal(types: {AccountType.bank, AccountType.savings}),
      income: income,
      expense: expense,
      netCashFlow: income - expense,
      iOwe: iOwe,
      owedToMe: owed,
      netWorth: totalAssets + owed - iOwe,
      savingsRate: FinanceMath.savingsRate(income.total, expense.total),
    );
  }
}

class MonthPoint {
  final DateTime month;
  final Decimal income, expense;
  final Decimal? balance;
  const MonthPoint(this.month, this.income, this.expense, this.balance);
  Decimal get net => income - expense;
}

class Charts {
  /// Last [n] months of income/expense and end-of-month account balance (base).
  /// Balance is reconstructed backwards from today's converted total using
  /// each transaction's recorded base amount.
  static List<MonthPoint> months(FinanceSnapshot s, {int n = 6}) {
    final now = s.now;
    final current = s.accountsTotal().total;
    final out = <MonthPoint>[];
    for (var i = n - 1; i >= 0; i--) {
      final r = DateRange(DateTime(now.year, now.month - i), DateTime(now.year, now.month - i + 1));
      final inc = FinanceMath.sumBase(s.txns, TxnType.income, range: r);
      final exp = FinanceMath.sumBase(s.txns, TxnType.expense, range: r);
      final end = r.end.isAfter(now) ? now : r.end;
      var after = Decimal.zero;
      for (final t in s.txns.where((t) => !t.isVoid && !t.txnDate.isBefore(end) && t.type != TxnType.transfer && t.accountId != null)) {
        after += t.baseAmount * Decimal.fromInt(t.type.sign);
      }
      out.add(MonthPoint(r.start, inc, exp, current - after));
    }
    return out;
  }
}
