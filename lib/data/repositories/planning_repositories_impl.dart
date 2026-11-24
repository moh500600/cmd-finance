import 'package:decimal/decimal.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/planning.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/finance_math.dart';
import 'ledger_engine.dart';

// =============================================================== budgets
class BudgetRepositoryImpl implements BudgetRepository {
  final LedgerEngine engine;
  BudgetRepositoryImpl(this.engine);
  Database get db => engine.db;

  @override
  Future<List<Budget>> budgets(String uid) async =>
      (await db.query('budgets', where: 'user_id = ?', whereArgs: [uid], orderBy: 'created_at')).map(Budget.fromMap).toList();

  @override
  Future<Budget> saveBudget(String uid, {String? id, required String name, String? categoryId, required BudgetPeriod period, required Decimal limit, int alertPercent = 80}) async {
    if (name.trim().isEmpty) throw const AppException('err_name_required');
    if (limit.sign <= 0) throw const AppException('err_amount_positive');
    if (alertPercent < 1 || alertPercent > 100) throw const AppException('err_alert_percent');
    return engine.atomic((t) async {
      final base = await engine.baseCurrency(t, uid);
      final before = id == null ? null : (await t.query('budgets', where: 'id = ? AND user_id = ?', whereArgs: [id, uid])).firstOrNull;
      final now = DateTime.now().toUtc();
      final b = Budget(id: id ?? newId(), userId: uid, name: name.trim(), categoryId: categoryId, period: period, limit: limit, currency: base,
          alertPercent: alertPercent, createdAt: before == null ? now : DateTime.parse(before['created_at'] as String), updatedAt: now);
      await t.insert('budgets', b.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      await engine.track(t, uid, 'budgets', b.id, before == null ? 'create' : 'update', before: before, after: b.toMap());
      return b;
    });
  }

  @override
  Future<void> deleteBudget(String uid, String id) => engine.atomic((t) async {
        final before = (await t.query('budgets', where: 'id = ? AND user_id = ?', whereArgs: [id, uid])).firstOrNull;
        await t.delete('budgets', where: 'id = ? AND user_id = ?', whereArgs: [id, uid]);
        await engine.track(t, uid, 'budgets', id, 'delete', before: before);
      });

  /// Spent = sum of posted EXPENSE base amounts in the current period (transfers never count).
  @override
  Future<List<BudgetStatus>> statuses(String uid, DateTime now) async {
    final list = await budgets(uid);
    final out = <BudgetStatus>[];
    for (final b in list.where((b) => b.active)) {
      final range = DateRange.of(b.periodKind, now);
      final rows = await db.query('transactions',
          columns: ['base_amount', 'base_currency', 'category_id'],
          where: "user_id = ? AND status = 'posted' AND type = 'expense' AND txn_date >= ? AND txn_date < ?${b.categoryId == null ? '' : ' AND category_id = ?'}",
          whereArgs: [uid, range.start.toIso8601String(), range.end.toIso8601String(), if (b.categoryId != null) b.categoryId]);
      final spent = Money.sum(rows.where((r) => r['base_currency'] == b.currency).map((r) => Money.fromDb(r['base_amount'])));
      out.add(BudgetStatus(b, range, spent));
    }
    return out;
  }
}

// =============================================================== debts
class DebtRepositoryImpl implements DebtRepository {
  final LedgerEngine engine;
  DebtRepositoryImpl(this.engine);
  Database get db => engine.db;

  Future<DebtSummary> _summary(DatabaseExecutor t, Debt d) async {
    final pays = await t.query('transactions',
        columns: ['amount'], where: "ref_type = 'debt' AND ref_id = ? AND status = 'posted' AND type IN ('debtPayment','debtCollection')", whereArgs: [d.id]);
    final paid = Money.sum(pays.map((r) => Money.fromDb(r['amount'])));
    return FinanceMath.debtSummary(d, paid);
  }

  @override
  Future<List<DebtSummary>> debts(String uid) async {
    final rows = await db.query('debts', where: 'user_id = ?', whereArgs: [uid], orderBy: "status, COALESCE(due_date, '9999')");
    return [for (final r in rows) await _summary(db, Debt.fromMap(r))];
  }

  @override
  Future<DebtSummary?> debt(String uid, String id) async {
    final r = await db.query('debts', where: 'id = ? AND user_id = ?', whereArgs: [id, uid]);
    return r.isEmpty ? null : _summary(db, Debt.fromMap(r.first));
  }

  @override
  Future<Debt> createDebt(String uid, {required DebtDirection direction, required String party, required Decimal principal, required String currency,
      Decimal? interestRate, required DateTime startDate, DateTime? dueDate, int installments = 1, Frequency frequency = Frequency.monthly,
      String notes = '', String? accountId, bool moveMoney = false, required String idempotencyKey}) async {
    if (party.trim().isEmpty) throw const AppException('err_name_required');
    if (principal.sign <= 0) throw const AppException('err_amount_positive');
    if ((interestRate ?? Decimal.zero).sign < 0) throw const AppException('err_interest');
    if (installments < 1 || installments > 600) throw const AppException('err_installments');
    if (dueDate != null && dueDate.isBefore(startDate)) throw const AppException('err_due_before_start');
    if (moveMoney && accountId == null) throw const AppException('err_account_required');
    return engine.atomic((t) async {
      final dupe = await t.query('audit_log', where: "user_id = ? AND entity = 'debts' AND action = ?", whereArgs: [uid, 'create:$idempotencyKey']);
      if (dupe.isNotEmpty) return Debt.fromMap((await t.query('debts', where: 'id = ?', whereArgs: [dupe.first['entity_id']])).first);
      final now = DateTime.now().toUtc();
      final d = Debt(id: newId(), userId: uid, direction: direction, party: party.trim(), principal: principal, currency: currency,
          interestRate: interestRate ?? Decimal.zero, startDate: startDate, dueDate: dueDate, installments: installments,
          installmentFrequency: frequency, notes: notes.trim(), accountId: accountId, createdAt: now, updatedAt: now);
      await t.insert('debts', d.toMap());
      await engine.audit(t, uid, 'debts', d.id, 'create:$idempotencyKey', after: d.toMap());
      await engine.enqueue(t, uid, 'debts', d.id, 'upsert', d.toMap());
      if (moveMoney) {
        // borrowing puts money in your account; lending takes it out — not income/expense.
        await engine.recordIn(t, uid, TxnDraft(
            type: direction == DebtDirection.iOwe ? TxnType.loanReceived : TxnType.loanGiven, accountId: accountId, amount: principal,
            currency: currency, title: party.trim(), txnDate: startDate, idempotencyKey: '$idempotencyKey:principal', refType: 'debt', refId: d.id));
      }
      return d;
    });
  }

  @override
  Future<Debt> updateDebt(String uid, Debt d) => engine.atomic((t) async {
        final before = (await t.query('debts', where: 'id = ? AND user_id = ?', whereArgs: [d.id, uid])).firstOrNull;
        if (before == null) throw const AppException('err_not_found');
        final row = {...d.toMap(), 'updated_at': nowUtc()};
        await t.update('debts', row, where: 'id = ?', whereArgs: [d.id]);
        await engine.track(t, uid, 'debts', d.id, 'update', before: before, after: row);
        return Debt.fromMap(row);
      });

  @override
  Future<FinTransaction> addPayment(String uid, String debtId, {required String accountId, required Decimal amount, required DateTime date, String notes = '', required String idempotencyKey}) =>
      engine.atomic((t) async {
        final r = await t.query('debts', where: 'id = ? AND user_id = ?', whereArgs: [debtId, uid]);
        if (r.isEmpty) throw const AppException('err_not_found');
        final d = Debt.fromMap(r.first);
        final s = await _summary(t, d);
        final existing = await engine.byKey(t, uid, idempotencyKey);
        if (existing != null) return existing;
        if (amount > s.remaining) throw AppException('err_payment_exceeds', args: {'remaining': Money.format(s.remaining, currency: d.currency)});
        final txn = await engine.recordIn(t, uid, TxnDraft(
            type: d.direction == DebtDirection.iOwe ? TxnType.debtPayment : TxnType.debtCollection, accountId: accountId, amount: amount,
            currency: d.currency, title: d.party, notes: notes, txnDate: date, idempotencyKey: idempotencyKey, refType: 'debt', refId: d.id));
        if (s.paid + amount >= s.totalPayable) {
          await t.update('debts', {'status': DebtStatus.settled.name, 'updated_at': nowUtc()}, where: 'id = ?', whereArgs: [d.id]);
          await engine.track(t, uid, 'debts', d.id, 'settled', before: d.toMap(), after: {...d.toMap(), 'status': 'settled'});
        }
        return txn;
      });

  @override
  Future<List<FinTransaction>> payments(String uid, String debtId) async => (await db.query('transactions',
          where: "user_id = ? AND ref_type = 'debt' AND ref_id = ?", whereArgs: [uid, debtId], orderBy: 'txn_date DESC'))
      .map(FinTransaction.fromMap)
      .toList();

  /// Deleting a debt voids every money movement linked to it first (reversing balances).
  @override
  Future<void> deleteDebt(String uid, String id) => engine.atomic((t) async {
        final before = (await t.query('debts', where: 'id = ? AND user_id = ?', whereArgs: [id, uid])).firstOrNull;
        if (before == null) return;
        final linked = await t.query('transactions', columns: ['id'], where: "ref_type = 'debt' AND ref_id = ? AND status = 'posted'", whereArgs: [id]);
        for (final l in linked) {
          await engine.voidIn(t, uid, l['id'] as String, 'debt_deleted');
        }
        await t.update('transactions', {'ref_id': null}, where: "ref_type = 'debt' AND ref_id = ?", whereArgs: [id]);
        await t.delete('debts', where: 'id = ?', whereArgs: [id]);
        await engine.track(t, uid, 'debts', id, 'delete', before: before);
      });
}

// =============================================================== savings goals
class GoalRepositoryImpl implements GoalRepository {
  final LedgerEngine engine;
  GoalRepositoryImpl(this.engine);
  Database get db => engine.db;

  Future<GoalStatus> _status(DatabaseExecutor t, SavingsGoal g) async {
    final rows = await t.query('transactions',
        where: "ref_type = 'goal' AND ref_id = ? AND status = 'posted'", whereArgs: [g.id], orderBy: 'txn_date');
    var current = g.initialAmount;
    final history = <(DateTime, Decimal)>[(g.createdAt.toLocal(), current)];
    for (final r in rows.map(FinTransaction.fromMap)) {
      current = r.type == TxnType.savingsDeposit ? current + r.amount : current - r.amount;
      history.add((r.txnDate, current));
    }
    return GoalStatus(g, current, history);
  }

  @override
  Future<List<GoalStatus>> goals(String uid) async {
    final rows = await db.query('savings_goals', where: 'user_id = ?', whereArgs: [uid], orderBy: 'created_at');
    return [for (final r in rows) await _status(db, SavingsGoal.fromMap(r))];
  }

  @override
  Future<GoalStatus?> goal(String uid, String id) async {
    final r = await db.query('savings_goals', where: 'id = ? AND user_id = ?', whereArgs: [id, uid]);
    return r.isEmpty ? null : _status(db, SavingsGoal.fromMap(r.first));
  }

  @override
  Future<SavingsGoal> saveGoal(String uid, {String? id, required String name, required Decimal target, required String currency, Decimal? initialAmount,
      DateTime? deadline, int color = 0xFF0EA5E9, String notes = ''}) {
    if (name.trim().isEmpty) throw const AppException('err_name_required');
    if (target.sign <= 0) throw const AppException('err_amount_positive');
    if ((initialAmount ?? Decimal.zero).sign < 0) throw const AppException('err_amount_positive');
    return engine.atomic((t) async {
      final before = id == null ? null : (await t.query('savings_goals', where: 'id = ? AND user_id = ?', whereArgs: [id, uid])).firstOrNull;
      final now = DateTime.now().toUtc();
      final g = SavingsGoal(id: id ?? newId(), userId: uid, name: name.trim(), target: target, currency: before?['currency'] as String? ?? currency,
          initialAmount: initialAmount ?? Decimal.zero, deadline: deadline, color: color, notes: notes.trim(),
          achievedAt: before == null ? null : DateTime.tryParse('${before['achieved_at']}'),
          createdAt: before == null ? now : DateTime.parse(before['created_at'] as String), updatedAt: now);
      await t.insert('savings_goals', g.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      await engine.track(t, uid, 'savings_goals', g.id, before == null ? 'create' : 'update', before: before, after: g.toMap());
      return g;
    });
  }

  @override
  Future<bool> move(String uid, String goalId, {required bool deposit, String? accountId, required Decimal amount, required DateTime date, String notes = '', required String idempotencyKey}) =>
      engine.atomic((t) async {
        final r = await t.query('savings_goals', where: 'id = ? AND user_id = ?', whereArgs: [goalId, uid]);
        if (r.isEmpty) throw const AppException('err_not_found');
        final g = SavingsGoal.fromMap(r.first);
        final before = await _status(t, g);
        if (await engine.byKey(t, uid, idempotencyKey) != null) return false;
        if (!deposit && amount > before.current) throw const AppException('err_withdraw_exceeds');
        await engine.recordIn(t, uid, TxnDraft(
            type: deposit ? TxnType.savingsDeposit : TxnType.savingsWithdraw, accountId: accountId, amount: amount, currency: g.currency,
            title: g.name, notes: notes, txnDate: date, idempotencyKey: idempotencyKey, refType: 'goal', refId: g.id));
        final after = await _status(t, g);
        final reachedNow = !before.reached && after.reached;
        if (reachedNow) {
          await t.update('savings_goals', {'achieved_at': nowUtc(), 'updated_at': nowUtc()}, where: 'id = ?', whereArgs: [g.id]);
          await engine.audit(t, uid, 'savings_goals', g.id, 'achieved');
        }
        return reachedNow;
      });

  @override
  Future<List<FinTransaction>> movements(String uid, String goalId) async => (await db.query('transactions',
          where: "user_id = ? AND ref_type = 'goal' AND ref_id = ?", whereArgs: [uid, goalId], orderBy: 'txn_date DESC'))
      .map(FinTransaction.fromMap)
      .toList();

  @override
  Future<void> deleteGoal(String uid, String id) => engine.atomic((t) async {
        final before = (await t.query('savings_goals', where: 'id = ? AND user_id = ?', whereArgs: [id, uid])).firstOrNull;
        if (before == null) return;
        final linked = await t.query('transactions', columns: ['id'], where: "ref_type = 'goal' AND ref_id = ? AND status = 'posted'", whereArgs: [id]);
        for (final l in linked) {
          await engine.voidIn(t, uid, l['id'] as String, 'goal_deleted'); // money returns to its accounts
        }
        await t.delete('savings_goals', where: 'id = ?', whereArgs: [id]);
        await engine.track(t, uid, 'savings_goals', id, 'delete', before: before);
      });
}

// =============================================================== bills
class BillRepositoryImpl implements BillRepository {
  final LedgerEngine engine;
  BillRepositoryImpl(this.engine);
  Database get db => engine.db;

  @override
  Future<List<Bill>> bills(String uid, {bool includeInactive = true}) async => (await db.query('bills',
          where: includeInactive ? 'user_id = ?' : 'user_id = ? AND active = 1', whereArgs: [uid], orderBy: 'active DESC, due_date'))
      .map(Bill.fromMap)
      .toList();

  @override
  Future<Bill> saveBill(String uid, {String? id, required String name, required BillKind kind, required Decimal amount, required String currency,
      required DateTime dueDate, Frequency recurrence = Frequency.monthly, int remindDaysBefore = 3, String? accountId, String? categoryId, String notes = ''}) {
    if (name.trim().isEmpty) throw const AppException('err_name_required');
    if (amount.sign <= 0) throw const AppException('err_amount_positive');
    return engine.atomic((t) async {
      final before = id == null ? null : (await t.query('bills', where: 'id = ? AND user_id = ?', whereArgs: [id, uid])).firstOrNull;
      final now = DateTime.now().toUtc();
      final b = Bill(id: id ?? newId(), userId: uid, name: name.trim(), kind: kind, amount: amount, currency: currency, dueDate: dayOnly(dueDate),
          recurrence: recurrence, remindDaysBefore: remindDaysBefore, accountId: accountId, categoryId: categoryId, notes: notes.trim(),
          active: true, createdAt: before == null ? now : DateTime.parse(before['created_at'] as String), updatedAt: now);
      await t.insert('bills', b.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      await engine.track(t, uid, 'bills', b.id, before == null ? 'create' : 'update', before: before, after: b.toMap());
      return b;
    });
  }

  /// Pays the current cycle: posts the expense, logs the payment and advances
  /// the due date (or closes a one-off bill) — all in one transaction.
  @override
  Future<FinTransaction> payBill(String uid, String billId, {required String accountId, Decimal? amount, required DateTime date, required String idempotencyKey}) =>
      engine.atomic((t) async {
        final r = await t.query('bills', where: 'id = ? AND user_id = ?', whereArgs: [billId, uid]);
        if (r.isEmpty) throw const AppException('err_not_found');
        final b = Bill.fromMap(r.first);
        final existing = await engine.byKey(t, uid, idempotencyKey);
        if (existing != null) return existing;
        if (!b.active) throw const AppException('err_bill_inactive');
        final cat = b.categoryId ?? await engine.builtinCategoryId(t, uid, 'bills');
        final txn = await engine.recordIn(t, uid, TxnDraft(
            type: TxnType.expense, accountId: accountId, amount: amount ?? b.amount, currency: b.currency, categoryId: cat, title: b.name,
            txnDate: date, idempotencyKey: idempotencyKey, refType: 'bill', refId: b.id));
        final pid = newId();
        final pay = {'id': pid, 'user_id': uid, 'bill_id': b.id, 'due_date': b.dueDate.toIso8601String(), 'paid_at': date.toIso8601String(),
          'amount': Money.toDb(amount ?? b.amount), 'currency': b.currency, 'txn_id': txn.id, 'voided': 0};
        await t.insert('bill_payments', pay);
        await engine.track(t, uid, 'bill_payments', pid, 'create', after: pay);
        final once = b.recurrence == Frequency.once;
        final next = once ? b.dueDate : nextOccurrence(b.dueDate, b.recurrence);
        await t.update('bills', {'due_date': next.toIso8601String(), 'active': once ? 0 : 1, 'updated_at': nowUtc()}, where: 'id = ?', whereArgs: [b.id]);
        await engine.track(t, uid, 'bills', b.id, 'paid', before: b.toMap(), after: {...b.toMap(), 'due_date': next.toIso8601String(), 'active': once ? 0 : 1});
        return txn;
      });

  @override
  Future<List<BillPayment>> payments(String uid, String billId) async =>
      (await db.query('bill_payments', where: 'user_id = ? AND bill_id = ?', whereArgs: [uid, billId], orderBy: 'paid_at DESC')).map(BillPayment.fromMap).toList();

  /// Payments stay in the ledger (they really happened); the bill is removed.
  @override
  Future<void> deleteBill(String uid, String id) => engine.atomic((t) async {
        final before = (await t.query('bills', where: 'id = ? AND user_id = ?', whereArgs: [id, uid])).firstOrNull;
        if (before == null) return;
        await t.delete('bill_payments', where: 'bill_id = ?', whereArgs: [id]);
        await t.delete('bills', where: 'id = ?', whereArgs: [id]);
        await engine.track(t, uid, 'bills', id, 'delete', before: before);
      });
}
