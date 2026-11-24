import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../entities/account.dart';
import '../entities/planning.dart';
import '../entities/transaction.dart';
import 'snapshot.dart';

enum AlertLevel { info, warning, danger, success }

class FinanceAlert {
  final AlertLevel level;
  final String kind; // budget|low_balance|bill|debt|goal|rate|recurring|large
  final String message;
  final String? route;
  const FinanceAlert(this.level, this.kind, this.message, {this.route});
}

/// Derives the dashboard alerts and the reminder schedule from real data.
class AlertsService {
  final String Function(String key, [Map<String, String> args]) tr;
  AlertsService(this.tr);

  List<FinanceAlert> current(FinanceSnapshot s) {
    final out = <FinanceAlert>[];
    final now = s.now;
    for (final b in s.budgets) {
      if (b.exceeded) {
        out.add(FinanceAlert(AlertLevel.danger, 'budget', tr('alert_budget_exceeded', {'name': b.budget.name, 'pct': '${b.percent}'}), route: 'budgets'));
      } else if (b.nearLimit) {
        out.add(FinanceAlert(AlertLevel.warning, 'budget', tr('alert_budget_near', {'name': b.budget.name, 'pct': '${b.percent}'}), route: 'budgets'));
      }
    }
    for (final a in s.activeAccounts) {
      final limit = a.item.lowBalanceAlert;
      if (limit != null && a.item.balance < limit) {
        out.add(FinanceAlert(AlertLevel.warning, 'low_balance', tr('alert_low_balance', {'name': a.item.name, 'amount': Money.format(a.item.balance, currency: a.currency)}), route: 'accounts'));
      }
    }
    for (final b in s.bills.where((b) => b.active)) {
      if (b.isOverdue(now)) {
        out.add(FinanceAlert(AlertLevel.danger, 'bill', tr('alert_bill_overdue', {'name': b.name, 'date': isoDay(b.dueDate)}), route: 'bills'));
      } else if (b.isDueSoon(now)) {
        out.add(FinanceAlert(AlertLevel.warning, 'bill', tr('alert_bill_due', {'name': b.name, 'date': isoDay(b.dueDate), 'amount': Money.format(b.amount, currency: b.currency)}), route: 'bills'));
      }
    }
    for (final d in s.debts.where((d) => d.item.remaining.sign > 0)) {
      final next = d.item.nextInstallment;
      if (next == null) continue;
      final days = dayOnly(next.dueDate).difference(dayOnly(now)).inDays;
      final mine = d.item.debt.direction == DebtDirection.iOwe;
      if (days < 0) {
        out.add(FinanceAlert(AlertLevel.danger, 'debt', tr(mine ? 'alert_debt_overdue' : 'alert_receivable_overdue', {'name': d.item.debt.party}), route: 'debts'));
      } else if (days <= 7) {
        out.add(FinanceAlert(AlertLevel.warning, 'debt', tr(mine ? 'alert_debt_due' : 'alert_receivable_due', {'name': d.item.debt.party, 'date': isoDay(next.dueDate), 'amount': Money.format(next.amount, currency: d.currency)}), route: 'debts'));
      }
    }
    for (final g in s.goals) {
      if (g.item.reached) {
        out.add(FinanceAlert(AlertLevel.success, 'goal', tr('alert_goal_reached', {'name': g.item.goal.name}), route: 'savings'));
      } else if (g.item.goal.deadline != null && g.item.goal.deadline!.difference(now).inDays <= 30 && g.item.goal.deadline!.isAfter(now)) {
        out.add(FinanceAlert(AlertLevel.info, 'goal', tr('alert_goal_deadline', {'name': g.item.goal.name, 'pct': '${g.item.percent}'}), route: 'savings'));
      }
    }
    final missing = <String>{
      ...s.accountsTotal().missing, ...s.goalsTotal.missing, ...s.assetsTotal.missing, ...s.investmentsTotal.missing,
      ...s.debtsTotal(DebtDirection.iOwe).missing, ...s.debtsTotal(DebtDirection.owedToMe).missing,
    };
    if (missing.isNotEmpty) {
      out.add(FinanceAlert(AlertLevel.warning, 'rate', tr('alert_missing_rate', {'ccy': missing.join(', '), 'base': s.base}), route: 'currencies'));
    }
    for (final r in s.recurring.where((r) => r.active && r.lastError != null)) {
      out.add(FinanceAlert(AlertLevel.warning, 'recurring', tr('alert_recurring_error', {'name': r.template.title.isEmpty ? '—' : r.template.title, 'err': r.lastError!}), route: 'recurring'));
    }
    return out;
  }

  /// Instant alerts right after a transaction is saved.
  List<FinanceAlert> afterTransaction(FinTransaction t, FinanceSnapshot s, {Decimal? largeThreshold}) {
    final out = <FinanceAlert>[];
    if (t.type == TxnType.expense && largeThreshold != null && largeThreshold.sign > 0 && t.baseAmount >= largeThreshold) {
      out.add(FinanceAlert(AlertLevel.warning, 'large', tr('alert_large_expense', {'amount': Money.format(t.baseAmount, currency: s.base)})));
    }
    for (final a in s.activeAccounts.where((a) => a.item.id == t.accountId)) {
      final limit = a.item.lowBalanceAlert;
      if (limit != null && a.item.balance < limit) {
        out.add(FinanceAlert(AlertLevel.warning, 'low_balance', tr('alert_low_balance', {'name': a.item.name, 'amount': Money.format(a.item.balance, currency: a.currency)})));
      }
    }
    if (t.type == TxnType.expense) {
      for (final b in s.budgets.where((b) => b.budget.categoryId == null || b.budget.categoryId == t.categoryId)) {
        if (b.exceeded) out.add(FinanceAlert(AlertLevel.danger, 'budget', tr('alert_budget_exceeded', {'name': b.budget.name, 'pct': '${b.percent}'})));
        if (b.nearLimit) out.add(FinanceAlert(AlertLevel.warning, 'budget', tr('alert_budget_near', {'name': b.budget.name, 'pct': '${b.percent}'})));
      }
    }
    return out;
  }
}

/// Reminder plan (pure): bills/debts N days before due at 09:00, goal deadlines.
class ReminderPlanner {
  static List<(int id, DateTime when, String kind, String name, String detail)> plan(FinanceSnapshot s) {
    final out = <(int, DateTime, String, String, String)>[];
    var id = 1000;
    DateTime at9(DateTime d) => DateTime(d.year, d.month, d.day, 9);
    for (final b in s.bills.where((b) => b.active)) {
      out.add((id++, at9(b.dueDate.subtract(Duration(days: b.remindDaysBefore))), 'bill', b.name, Money.format(b.amount, currency: b.currency)));
      out.add((id++, at9(b.dueDate), 'bill_today', b.name, Money.format(b.amount, currency: b.currency)));
    }
    for (final d in s.debts.where((d) => d.item.remaining.sign > 0)) {
      final next = d.item.nextInstallment;
      if (next == null) continue;
      out.add((id++, at9(next.dueDate.subtract(const Duration(days: 2))), d.item.debt.direction == DebtDirection.iOwe ? 'debt' : 'receivable', d.item.debt.party,
          Money.format(next.amount, currency: d.currency)));
    }
    for (final g in s.goals.where((g) => !g.item.reached && g.item.goal.deadline != null)) {
      out.add((id++, at9(g.item.goal.deadline!.subtract(const Duration(days: 14))), 'goal', g.item.goal.name, '${g.item.percent}%'));
    }
    return out;
  }
}

extension AccountTypeX on AccountType {
  bool get isBankLike => this == AccountType.bank || this == AccountType.savings;
}
