import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../entities/account.dart';
import '../entities/planning.dart';
import '../entities/transaction.dart';
import 'finance_math.dart';
import 'snapshot.dart';

enum ReportType { income, expenses, profitLoss, cashFlow, balances, debts, budgets, savings, assets, netWorth }

class ReportTable {
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  const ReportTable(this.title, this.headers, this.rows);
}

class ReportData {
  final ReportType type;
  final String title;
  final String period;
  final List<(String, String)> summary;
  final List<ReportTable> tables;
  final List<(String, Decimal)> chart;
  final List<String> warnings;
  const ReportData({required this.type, required this.title, required this.period, required this.summary, required this.tables, this.chart = const [], this.warnings = const []});
}

/// Builds the 10 financial reports from a snapshot. [tr] translates keys,
/// [cat] names categories. All amounts in the base currency unless stated.
class ReportBuilder {
  final FinanceSnapshot s;
  final String Function(String) tr;
  final String Function(Category?) cat;
  ReportBuilder(this.s, this.tr, this.cat);

  String m(Decimal d, [String? c]) => Money.format(d, currency: c ?? s.base);
  List<FinTransaction> _in(DateRange r, TxnType t) => s.txns.where((x) => x.type == t && r.contains(x.txnDate)).toList()..sort((a, b) => a.txnDate.compareTo(b.txnDate));
  String _acc(String? id) => s.accounts.where((a) => a.item.id == id).map((a) => a.item.name).firstOrNull ?? '—';
  List<String> _warn(BaseTotal b) => b.complete ? const [] : ['${tr('missing_rates_for')}: ${b.missing.join(', ')}'];

  ReportData build(ReportType type, DateRange r, String periodLabel) {
    final title = tr('report_${type.name}');
    switch (type) {
      case ReportType.income:
      case ReportType.expenses:
        final tt = type == ReportType.income ? TxnType.income : TxnType.expense;
        final list = _in(r, tt);
        final total = Money.sum(list.map((x) => x.baseAmount));
        final byCat = FinanceMath.byCategory(s.txns, r, type: tt);
        return ReportData(type: type, title: title, period: periodLabel,
            summary: [(tr('total'), m(total)), (tr('count'), '${list.length}'), (tr('average'), list.isEmpty ? '—' : m(Money.div(total, Decimal.fromInt(list.length), scale: 2)))],
            chart: [for (final e in byCat) (cat(s.categories[e.key]), e.value)],
            tables: [
              ReportTable(tr('by_category'), [tr('category'), tr('amount'), '%'], [for (final e in byCat) [cat(s.categories[e.key]), m(e.value), '${Money.percent(e.value, total)}']]),
              ReportTable(tr('details'), [tr('date'), tr('title'), tr('category'), tr('account'), tr('original_amount'), '${tr('amount')} (${s.base})'],
                  [for (final x in list) [isoDay(x.txnDate), x.title, cat(s.categories[x.categoryId]), _acc(x.accountId), m(x.amount, x.currency), m(x.baseAmount)]]),
            ]);
      case ReportType.profitLoss:
        final inc = FinanceMath.sumBase(s.txns, TxnType.income, range: r), exp = FinanceMath.sumBase(s.txns, TxnType.expense, range: r);
        final ic = FinanceMath.byCategory(s.txns, r, type: TxnType.income), ec = FinanceMath.byCategory(s.txns, r);
        return ReportData(type: type, title: title, period: periodLabel,
            summary: [(tr('income'), m(inc)), (tr('expenses'), m(exp)), (tr('net_profit'), m(inc - exp)), (tr('savings_rate'), '${FinanceMath.savingsRate(inc, exp)}%')],
            chart: [(tr('income'), inc), (tr('expenses'), exp)],
            tables: [
              ReportTable(tr('income'), [tr('category'), tr('amount')], [for (final e in ic) [cat(s.categories[e.key]), m(e.value)], [tr('total'), m(inc)]]),
              ReportTable(tr('expenses'), [tr('category'), tr('amount')], [for (final e in ec) [cat(s.categories[e.key]), m(e.value)], [tr('total'), m(exp)]]),
            ]);
      case ReportType.cashFlow:
        final rows = <List<String>>[];
        final chart = <(String, Decimal)>[];
        final byDay = r.end.difference(r.start).inDays <= 31;
        var cur = r.start;
        while (cur.isBefore(r.end)) {
          final next = byDay ? cur.add(const Duration(days: 1)) : DateTime(cur.year, cur.month + 1);
          final sub = DateRange(cur, next.isAfter(r.end) ? r.end : next);
          final inflow = Money.sum(s.txns.where((x) => sub.contains(x.txnDate) && x.type.sign > 0 && x.accountId != null).map((x) => x.baseAmount));
          final outflow = Money.sum(s.txns.where((x) => sub.contains(x.txnDate) && x.type.sign < 0 && x.accountId != null).map((x) => x.baseAmount));
          if (inflow.sign != 0 || outflow.sign != 0 || !byDay) {
            final label = byDay ? isoDay(cur) : '${cur.year}-${cur.month.toString().padLeft(2, '0')}';
            rows.add([label, m(inflow), m(outflow), m(inflow - outflow)]);
            chart.add((label, inflow - outflow));
          }
          cur = next;
        }
        final transfers = s.txns.where((x) => x.type == TxnType.transfer && r.contains(x.txnDate)).length;
        return ReportData(type: type, title: title, period: periodLabel,
            summary: [(tr('net_cash_flow'), m(FinanceMath.sumBase(s.txns, TxnType.income, range: r) - FinanceMath.sumBase(s.txns, TxnType.expense, range: r))), (tr('transfers_excluded'), '$transfers')],
            chart: chart, tables: [ReportTable(tr('cash_flow'), [tr('period'), tr('inflow'), tr('outflow'), tr('net')], rows)]);
      case ReportType.balances:
        final total = s.accountsTotal();
        return ReportData(type: type, title: title, period: periodLabel, warnings: _warn(total),
            summary: [(tr('total'), m(total.total)), (tr('accounts'), '${s.activeAccounts.length}')],
            chart: [for (final a in s.activeAccounts) if (a.base != null) (a.item.name, a.base!)],
            tables: [ReportTable(tr('accounts'), [tr('account'), tr('type'), tr('balance'), '${tr('balance')} (${s.base})', tr('status')],
                [for (final a in s.accounts) [a.item.name, tr('acct_${a.item.type.name}'), m(a.amount, a.currency), a.base == null ? tr('no_rate') : m(a.base!), a.item.isActive ? tr('active') : tr('disabled')]])]);
      case ReportType.debts:
        final owe = s.debtsTotal(DebtDirection.iOwe), owed = s.debtsTotal(DebtDirection.owedToMe);
        return ReportData(type: type, title: title, period: periodLabel, warnings: [..._warn(owe), ..._warn(owed)],
            summary: [(tr('i_owe'), m(owe.total)), (tr('owed_to_me'), m(owed.total))],
            chart: [(tr('i_owe'), owe.total), (tr('owed_to_me'), owed.total)],
            tables: [ReportTable(tr('debts'), [tr('party'), tr('direction'), tr('principal'), tr('interest'), tr('paid'), tr('remaining'), tr('next_due'), tr('status')], [
              for (final d in s.debts)
                [d.item.debt.party, tr(d.item.debt.direction.name), m(d.item.debt.principal, d.currency), m(d.item.interest, d.currency), m(d.item.paid, d.currency),
                  m(d.item.remaining, d.currency), d.item.nextInstallment == null ? '—' : isoDay(d.item.nextInstallment!.dueDate),
                  d.item.remaining.sign == 0 ? tr('settled') : d.item.overdue ? tr('overdue') : tr('open')]
            ])]);
      case ReportType.budgets:
        return ReportData(type: type, title: title, period: periodLabel,
            summary: [(tr('budgets'), '${s.budgets.length}'), (tr('exceeded'), '${s.budgets.where((b) => b.exceeded).length}')],
            chart: [for (final b in s.budgets) (b.budget.name, b.percent)],
            tables: [ReportTable(tr('budget_vs_actual'), [tr('name'), tr('period'), tr('limit'), tr('spent'), tr('remaining'), '%'],
                [for (final b in s.budgets) [b.budget.name, tr(b.budget.period.name), m(b.budget.limit), m(b.spent), m(b.remaining), '${b.percent}']])]);
      case ReportType.savings:
        final total = s.goalsTotal;
        return ReportData(type: type, title: title, period: periodLabel, warnings: _warn(total),
            summary: [(tr('total_saved'), m(total.total)), (tr('goals'), '${s.goals.length}')],
            chart: [for (final g in s.goals) (g.item.goal.name, g.item.percent)],
            tables: [ReportTable(tr('savings'), [tr('goal'), tr('target'), tr('current'), tr('remaining'), '%', tr('deadline')], [
              for (final g in s.goals)
                [g.item.goal.name, m(g.item.goal.target, g.currency), m(g.item.current, g.currency), m(g.item.remaining, g.currency), '${g.item.percent}',
                  g.item.goal.deadline == null ? '—' : isoDay(g.item.goal.deadline!)]
            ])]);
      case ReportType.assets:
        final total = s.assetsTotal + s.investmentsTotal;
        return ReportData(type: type, title: title, period: periodLabel, warnings: _warn(total),
            summary: [(tr('assets'), m(s.assetsTotal.total)), (tr('investments'), m(s.investmentsTotal.total)), (tr('total'), m(total.total))],
            chart: [for (final a in s.assets) if (a.base != null) (a.item.name, a.base!)],
            tables: [
              ReportTable(tr('assets'), [tr('name'), tr('type'), tr('purchase_value'), tr('current_value'), tr('change')],
                  [for (final a in s.assets) [a.item.name, tr('asset_${a.item.type.name}'), m(a.item.purchaseValue, a.currency), m(a.item.currentValue, a.currency), '${a.item.changePercent}%']]),
              ReportTable(tr('investments'), [tr('name'), tr('capital'), tr('current_value'), tr('profit_loss'), 'ROI'],
                  [for (final i in s.investments) [i.item.investment.name, m(i.item.capital, i.currency), m(i.item.investment.currentValue, i.currency), m(i.item.profitLoss, i.currency), '${i.item.roi}%']]),
            ]);
      case ReportType.netWorth:
        final st = DashboardStats.compute(s, r);
        final months = Charts.months(s, n: 12);
        return ReportData(type: type, title: title, period: periodLabel, warnings: _warn(st.netWorth),
            summary: [
              (tr('accounts'), m(s.accountsTotal().total)), (tr('savings'), m(s.goalsTotal.total)), (tr('investments'), m(s.investmentsTotal.total)),
              (tr('assets'), m(s.assetsTotal.total)), (tr('owed_to_me'), m(st.owedToMe.total)), (tr('i_owe'), '-${m(st.iOwe.total)}'), (tr('net_worth'), m(st.netWorth.total)),
            ],
            chart: [for (final p in months) ('${p.month.month}/${p.month.year % 100}', p.balance ?? Decimal.zero)],
            tables: [ReportTable(tr('balance_trend'), [tr('month'), tr('income'), tr('expenses'), tr('balance')],
                [for (final p in months) ['${p.month.year}-${p.month.month.toString().padLeft(2, '0')}', m(p.income), m(p.expense), m(p.balance ?? Decimal.zero)]])]);
    }
  }
}
