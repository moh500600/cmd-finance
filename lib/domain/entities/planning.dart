import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../../core/utils/dates.dart';

enum BudgetPeriod { weekly, monthly, yearly }

class Budget {
  final String id;
  final String userId;
  final String name;
  final String? categoryId; // null = all expenses
  final BudgetPeriod period;
  final Decimal limit; // in base currency
  final String currency;
  final int alertPercent;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Budget({required this.id, required this.userId, required this.name, this.categoryId, required this.period, required this.limit,
      required this.currency, this.alertPercent = 80, this.active = true, required this.createdAt, required this.updatedAt});

  PeriodKind get periodKind => switch (period) { BudgetPeriod.weekly => PeriodKind.weekly, BudgetPeriod.monthly => PeriodKind.monthly, BudgetPeriod.yearly => PeriodKind.yearly };

  factory Budget.fromMap(Map<String, Object?> m) => Budget(
      id: m['id'] as String, userId: m['user_id'] as String, name: m['name'] as String, categoryId: m['category_id'] as String?,
      period: BudgetPeriod.values.byName(m['period'] as String), limit: Money.fromDb(m['limit_amount']), currency: m['currency'] as String,
      alertPercent: m['alert_percent'] as int, active: (m['active'] as int) == 1,
      createdAt: DateTime.parse(m['created_at'] as String), updatedAt: DateTime.parse(m['updated_at'] as String));
  Map<String, Object?> toMap() => {'id': id, 'user_id': userId, 'name': name, 'category_id': categoryId, 'period': period.name,
        'limit_amount': Money.toDb(limit), 'currency': currency, 'alert_percent': alertPercent, 'active': active ? 1 : 0,
        'created_at': createdAt.toIso8601String(), 'updated_at': updatedAt.toIso8601String()};
}

class BudgetStatus {
  final Budget budget;
  final DateRange range;
  final Decimal spent;
  final Set<String> missingRates;
  const BudgetStatus(this.budget, this.range, this.spent, [this.missingRates = const {}]);
  Decimal get remaining => budget.limit - spent;
  Decimal get percent => Money.percent(spent, budget.limit);
  bool get exceeded => spent > budget.limit;
  bool get nearLimit => !exceeded && percent >= Decimal.fromInt(budget.alertPercent);
}

enum DebtDirection { iOwe, owedToMe }

enum DebtStatus { open, settled }

class Debt {
  final String id;
  final String userId;
  final DebtDirection direction;
  final String party;
  final Decimal principal;
  final String currency;
  final Decimal interestRate; // simple annual %
  final DateTime startDate;
  final DateTime? dueDate;
  final int installments; // >= 1
  final Frequency installmentFrequency;
  final String notes;
  final DebtStatus status;
  final String? accountId; // account the principal moved through (optional)
  final DateTime createdAt;
  final DateTime updatedAt;
  const Debt({required this.id, required this.userId, required this.direction, required this.party, required this.principal, required this.currency,
      required this.interestRate, required this.startDate, this.dueDate, this.installments = 1, this.installmentFrequency = Frequency.monthly,
      this.notes = '', this.status = DebtStatus.open, this.accountId, required this.createdAt, required this.updatedAt});

  factory Debt.fromMap(Map<String, Object?> m) => Debt(
      id: m['id'] as String, userId: m['user_id'] as String, direction: DebtDirection.values.byName(m['direction'] as String),
      party: m['party'] as String, principal: Money.fromDb(m['principal']), currency: m['currency'] as String,
      interestRate: Money.fromDb(m['interest_rate']), startDate: DateTime.parse(m['start_date'] as String), dueDate: parseDtN(m['due_date']),
      installments: m['installments'] as int, installmentFrequency: Frequency.values.byName(m['installment_frequency'] as String),
      notes: (m['notes'] as String?) ?? '', status: DebtStatus.values.byName(m['status'] as String), accountId: m['account_id'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String), updatedAt: DateTime.parse(m['updated_at'] as String));
  Map<String, Object?> toMap() => {'id': id, 'user_id': userId, 'direction': direction.name, 'party': party, 'principal': Money.toDb(principal),
        'currency': currency, 'interest_rate': interestRate.toString(), 'start_date': startDate.toIso8601String(), 'due_date': dueDate?.toIso8601String(),
        'installments': installments, 'installment_frequency': installmentFrequency.name, 'notes': notes, 'status': status.name,
        'account_id': accountId, 'created_at': createdAt.toIso8601String(), 'updated_at': updatedAt.toIso8601String()};
}

class Installment {
  final int index;
  final DateTime dueDate;
  final Decimal amount;
  final bool paid;
  const Installment(this.index, this.dueDate, this.amount, this.paid);
}

class DebtSummary {
  final Debt debt;
  final Decimal interest;
  final Decimal paid;
  final List<Installment> schedule;
  const DebtSummary(this.debt, this.interest, this.paid, this.schedule);
  Decimal get totalPayable => debt.principal + interest;
  Decimal get remaining {
    final r = totalPayable - paid;
    return r.sign < 0 ? Decimal.zero : r;
  }

  Decimal get percentPaid => Money.percent(paid, totalPayable);
  Installment? get nextInstallment => schedule.where((i) => !i.paid).firstOrNull;
  bool get overdue => remaining.sign > 0 && (nextInstallment?.dueDate.isBefore(dayOnly(DateTime.now())) ?? false);
}

class SavingsGoal {
  final String id;
  final String userId;
  final String name;
  final Decimal target;
  final String currency;
  final Decimal initialAmount;
  final DateTime? deadline;
  final int color;
  final String notes;
  final DateTime? achievedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SavingsGoal({required this.id, required this.userId, required this.name, required this.target, required this.currency, required this.initialAmount,
      this.deadline, this.color = 0xFF0EA5E9, this.notes = '', this.achievedAt, required this.createdAt, required this.updatedAt});
  factory SavingsGoal.fromMap(Map<String, Object?> m) => SavingsGoal(
      id: m['id'] as String, userId: m['user_id'] as String, name: m['name'] as String, target: Money.fromDb(m['target']),
      currency: m['currency'] as String, initialAmount: Money.fromDb(m['initial_amount']), deadline: parseDtN(m['deadline']),
      color: m['color'] as int, notes: (m['notes'] as String?) ?? '', achievedAt: parseDtN(m['achieved_at']),
      createdAt: DateTime.parse(m['created_at'] as String), updatedAt: DateTime.parse(m['updated_at'] as String));
  Map<String, Object?> toMap() => {'id': id, 'user_id': userId, 'name': name, 'target': Money.toDb(target), 'currency': currency,
        'initial_amount': Money.toDb(initialAmount), 'deadline': deadline?.toIso8601String(), 'color': color, 'notes': notes,
        'achieved_at': achievedAt?.toIso8601String(), 'created_at': createdAt.toIso8601String(), 'updated_at': updatedAt.toIso8601String()};
}

class GoalStatus {
  final SavingsGoal goal;
  final Decimal current;
  final List<(DateTime, Decimal)> history; // running balance points
  const GoalStatus(this.goal, this.current, this.history);
  Decimal get remaining => (goal.target - current).sign < 0 ? Decimal.zero : goal.target - current;
  Decimal get percent => Money.percent(current, goal.target);
  bool get reached => current >= goal.target;

  /// Amount to save per month to reach the target by the deadline (null if no deadline).
  Decimal? monthlyNeeded(DateTime now) {
    final d = goal.deadline;
    if (d == null || reached) return reached ? Decimal.zero : null;
    var months = (d.year - now.year) * 12 + d.month - now.month;
    if (d.day > now.day) months += 0;
    if (months < 1) months = 1;
    return Money.div(remaining, Decimal.fromInt(months), scale: 2);
  }
}

enum BillKind { electricity, water, internet, rent, subscription, installment, other }

class Bill {
  final String id;
  final String userId;
  final String name;
  final BillKind kind;
  final Decimal amount;
  final String currency;
  final DateTime dueDate; // next unpaid due date
  final Frequency recurrence; // once = not recurring
  final int remindDaysBefore;
  final String? accountId;
  final String? categoryId;
  final bool active; // false = finished (once bill paid) or disabled
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Bill({required this.id, required this.userId, required this.name, required this.kind, required this.amount, required this.currency,
      required this.dueDate, this.recurrence = Frequency.monthly, this.remindDaysBefore = 3, this.accountId, this.categoryId, this.active = true,
      this.notes = '', required this.createdAt, required this.updatedAt});
  bool isOverdue(DateTime now) => active && dueDate.isBefore(dayOnly(now));
  bool isDueSoon(DateTime now) => active && !isOverdue(now) && dueDate.difference(dayOnly(now)).inDays <= remindDaysBefore;
  factory Bill.fromMap(Map<String, Object?> m) => Bill(
      id: m['id'] as String, userId: m['user_id'] as String, name: m['name'] as String, kind: BillKind.values.byName(m['kind'] as String),
      amount: Money.fromDb(m['amount']), currency: m['currency'] as String, dueDate: DateTime.parse(m['due_date'] as String),
      recurrence: Frequency.values.byName(m['recurrence'] as String), remindDaysBefore: m['remind_days_before'] as int,
      accountId: m['account_id'] as String?, categoryId: m['category_id'] as String?, active: (m['active'] as int) == 1,
      notes: (m['notes'] as String?) ?? '', createdAt: DateTime.parse(m['created_at'] as String), updatedAt: DateTime.parse(m['updated_at'] as String));
  Map<String, Object?> toMap() => {'id': id, 'user_id': userId, 'name': name, 'kind': kind.name, 'amount': Money.toDb(amount), 'currency': currency,
        'due_date': dueDate.toIso8601String(), 'recurrence': recurrence.name, 'remind_days_before': remindDaysBefore, 'account_id': accountId,
        'category_id': categoryId, 'active': active ? 1 : 0, 'notes': notes, 'created_at': createdAt.toIso8601String(), 'updated_at': updatedAt.toIso8601String()};
}

class BillPayment {
  final String id;
  final String billId;
  final DateTime dueDate;
  final DateTime paidAt;
  final Decimal amount;
  final String currency;
  final String txnId;
  final bool voided;
  const BillPayment({required this.id, required this.billId, required this.dueDate, required this.paidAt, required this.amount, required this.currency, required this.txnId, this.voided = false});
  factory BillPayment.fromMap(Map<String, Object?> m) => BillPayment(
      id: m['id'] as String, billId: m['bill_id'] as String, dueDate: DateTime.parse(m['due_date'] as String), paidAt: DateTime.parse(m['paid_at'] as String),
      amount: Money.fromDb(m['amount']), currency: m['currency'] as String, txnId: m['txn_id'] as String, voided: (m['voided'] as int) == 1);
}
