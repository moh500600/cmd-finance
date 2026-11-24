import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/currency.dart';
import '../../domain/entities/transaction.dart';

/// The single place where money moves. Every method takes the open SQLite
/// [Transaction] so callers compose several steps into ONE atomic unit:
/// balance update + ledger row + audit_log row + outbox row all commit or
/// none do.
class LedgerEngine {
  final Database db;
  LedgerEngine(this.db);

  Future<T> atomic<T>(Future<T> Function(Transaction t) body) => db.transaction(body);

  // ------------------------------------------------------------ audit/outbox
  Future<void> audit(DatabaseExecutor t, String uid, String entity, String entityId, String action,
      {Map<String, Object?>? before, Map<String, Object?>? after}) async {
    await t.insert('audit_log', {
      'id': newId(), 'user_id': uid, 'entity': entity, 'entity_id': entityId, 'action': action,
      'before_json': before == null ? null : jsonEncode(before), 'after_json': after == null ? null : jsonEncode(after), 'at': nowUtc(),
    });
  }

  /// Kept as a no-op so repositories stay unchanged (this app has no cloud sync).
  Future<void> enqueue(DatabaseExecutor t, String uid, String entity, String entityId, String op, Map<String, Object?> payload) async {}

  /// audit + outbox for a plain entity write.
  Future<void> track(DatabaseExecutor t, String uid, String table, String id, String action,
      {Map<String, Object?>? before, Map<String, Object?>? after}) async {
    await audit(t, uid, table, id, action, before: before, after: after);
    await enqueue(t, uid, table, id, action == 'delete' ? 'delete' : 'upsert', after ?? {'id': id});
  }

  // ------------------------------------------------------------ fx
  Future<String> baseCurrency(DatabaseExecutor t, String uid) async {
    final r = await t.query('users', columns: ['base_currency'], where: 'id = ?', whereArgs: [uid]);
    if (r.isEmpty) throw const AppException('err_no_user');
    return r.first['base_currency'] as String;
  }

  /// Latest manual rate on/before [date]: direct row, or the exact inverse of
  /// the reverse row. Never a built-in or assumed rate.
  Future<Conversion> convert(DatabaseExecutor t, String uid, Decimal amount, String from, String to, DateTime date) async {
    if (from == to) return Conversion(amount, Decimal.one, null);
    final day = isoDay(date);
    Future<Map<String, Object?>?> find(String a, String b) async {
      final r = await t.query('exchange_rates',
          where: 'user_id = ? AND from_ccy = ? AND to_ccy = ? AND rate_date <= ?', whereArgs: [uid, a, b, day],
          orderBy: 'rate_date DESC, created_at DESC', limit: 1);
      return r.isEmpty ? null : r.first;
    }

    final direct = await find(from, to);
    final inverse = await find(to, from);
    if (direct == null && inverse == null) throw MissingRateException(from, to, date);
    final useDirect = direct != null && (inverse == null || (direct['rate_date'] as String).compareTo(inverse['rate_date'] as String) >= 0);
    final row = useDirect ? direct : inverse!;
    final stored = Money.fromDb(row['rate']);
    final rate = useDirect ? stored : Money.div(Decimal.one, stored, scale: 10);
    return Conversion(Money.round(amount * rate), rate, row['id'] as String,
        inverted: !useDirect, rateDate: DateTime.parse(row['rate_date'] as String), source: row['source'] as String);
  }

  // ------------------------------------------------------------ accounts
  Future<Account> loadAccount(DatabaseExecutor t, String uid, String id) async {
    final r = await t.query('accounts', where: 'id = ? AND user_id = ?', whereArgs: [id, uid]);
    if (r.isEmpty) throw const AppException('err_account_not_found');
    return Account.fromMap(r.first);
  }

  Future<void> applyToAccount(DatabaseExecutor t, String uid, String accountId, Decimal delta) async {
    final a = await loadAccount(t, uid, accountId);
    final now = DateTime.now().toUtc().toIso8601String();
    await t.update('accounts', {'balance': Money.toDb(a.balance + delta), 'updated_at': now}, where: 'id = ?', whereArgs: [accountId]);
  }

  // ------------------------------------------------------------ transactions
  Future<FinTransaction?> byKey(DatabaseExecutor t, String uid, String key) async {
    final r = await t.query('transactions', where: 'user_id = ? AND idempotency_key = ?', whereArgs: [uid, key]);
    return r.isEmpty ? null : FinTransaction.fromMap(r.first);
  }

  Future<FinTransaction> load(DatabaseExecutor t, String uid, String id) async {
    final r = await t.query('transactions', where: 'id = ? AND user_id = ?', whereArgs: [id, uid]);
    if (r.isEmpty) throw const AppException('err_txn_not_found');
    return FinTransaction.fromMap(r.first);
  }

  void _validate(TxnDraft d) {
    if (d.amount.sign <= 0) throw const AppException('err_amount_positive');
    if (d.amount.scale > Money.storageScale) throw const AppException('err_amount_scale');
    if (d.type == TxnType.transfer) throw const AppException('err_use_transfer');
  }

  Future<void> _checkCategory(DatabaseExecutor t, String uid, TxnDraft d) async {
    if (d.type != TxnType.income && d.type != TxnType.expense) return;
    if (d.categoryId == null) throw const AppException('err_category_required');
    final c = await t.query('categories', where: 'id = ? AND user_id = ?', whereArgs: [d.categoryId, uid]);
    if (c.isEmpty) throw const AppException('err_category_required');
    final kind = c.first['kind'] as String;
    if ((d.type == TxnType.income) != (kind == CategoryKind.income.name)) throw const AppException('err_category_kind');
  }

  /// Posts an income/expense/debt/goal movement. Idempotent on draft.idempotencyKey.
  Future<FinTransaction> recordIn(Transaction t, String uid, TxnDraft d, {String? parentId}) async {
    _validate(d);
    final existing = await byKey(t, uid, d.idempotencyKey);
    if (existing != null) return existing; // duplicate submit -> no second posting
    await _checkCategory(t, uid, d);
    final base = await baseCurrency(t, uid);
    Account? acc;
    Conversion? accConv;
    if (d.accountId != null) {
      acc = await loadAccount(t, uid, d.accountId!);
      if (!acc.isActive) throw const AppException('err_account_inactive');
      accConv = await convert(t, uid, d.amount, d.currency, acc.currency, d.txnDate);
    } else if (d.type != TxnType.savingsDeposit && d.type != TxnType.savingsWithdraw) {
      throw const AppException('err_account_required');
    }
    final baseConv = await convert(t, uid, d.amount, d.currency, base, d.txnDate);
    final now = DateTime.now().toUtc();
    final txn = FinTransaction(
      id: newId(), userId: uid, type: d.type, accountId: d.accountId, categoryId: d.categoryId, amount: Money.round(d.amount), currency: d.currency,
      accountAmount: accConv?.amount, accountRateId: accConv?.rateId, fee: Decimal.zero, parentId: parentId,
      baseAmount: baseConv.amount, baseCurrency: base, baseRateId: baseConv.rateId, baseRate: baseConv.rate,
      title: d.title.trim(), notes: d.notes.trim(), txnDate: d.txnDate, createdAt: now, updatedAt: now, idempotencyKey: d.idempotencyKey,
      recurringId: d.recurringId, refType: d.refType, refId: d.refId, attachments: d.attachments,
    );
    await t.insert('transactions', txn.toMap());
    if (acc != null) await applyToAccount(t, uid, acc.id, accConv!.amount * Decimal.fromInt(d.type.sign));
    await audit(t, uid, 'transactions', txn.id, 'create', after: txn.toMap());
    await enqueue(t, uid, 'transactions', txn.id, 'post_txn', txn.toMap());
    return txn;
  }

  Future<FinTransaction> transferIn(Transaction t, String uid, TransferDraft d, {required String feeCategoryId}) async {
    if (d.amount.sign <= 0) throw const AppException('err_amount_positive');
    if (d.fee.sign < 0) throw const AppException('err_fee_negative');
    if (d.fromAccountId == d.toAccountId) throw const AppException('err_same_account');
    final existing = await byKey(t, uid, d.idempotencyKey);
    if (existing != null) return existing;
    final from = await loadAccount(t, uid, d.fromAccountId);
    final to = await loadAccount(t, uid, d.toAccountId);
    if (!from.isActive || !to.isActive) throw const AppException('err_account_inactive');
    final base = await baseCurrency(t, uid);
    Decimal toAmount;
    Decimal rate;
    String? refRateId;
    if (from.currency == to.currency) {
      toAmount = d.amount;
      rate = Decimal.one;
    } else if (d.toAmount != null) {
      if (d.toAmount!.sign <= 0) throw const AppException('err_amount_positive');
      toAmount = d.toAmount!; // what actually arrived; effective rate derived from it
      rate = Money.div(toAmount, d.amount, scale: 10);
      try {
        refRateId = (await convert(t, uid, d.amount, from.currency, to.currency, d.txnDate)).rateId;
      } on MissingRateException {
        refRateId = null;
      }
    } else {
      final c = await convert(t, uid, d.amount, from.currency, to.currency, d.txnDate);
      toAmount = c.amount;
      rate = c.rate;
      refRateId = c.rateId;
    }
    final baseConv = await convert(t, uid, d.amount, from.currency, base, d.txnDate);
    final now = DateTime.now().toUtc();
    final txn = FinTransaction(
      id: newId(), userId: uid, type: TxnType.transfer, accountId: from.id, toAccountId: to.id, amount: Money.round(d.amount), currency: from.currency,
      accountAmount: Money.round(d.amount), accountRateId: refRateId, toAmount: Money.round(toAmount), toCurrency: to.currency, fxRate: rate,
      fee: Money.round(d.fee), baseAmount: baseConv.amount, baseCurrency: base, baseRateId: baseConv.rateId, baseRate: baseConv.rate,
      title: '${from.name} → ${to.name}', notes: d.notes.trim(), txnDate: d.txnDate, createdAt: now, updatedAt: now, idempotencyKey: d.idempotencyKey,
    );
    await t.insert('transactions', txn.toMap());
    await applyToAccount(t, uid, from.id, -txn.amount);
    await applyToAccount(t, uid, to.id, txn.toAmount!);
    await audit(t, uid, 'transactions', txn.id, 'create', after: txn.toMap());
    await enqueue(t, uid, 'transactions', txn.id, 'post_txn', txn.toMap());
    if (d.fee.sign > 0) {
      // The fee is a real cost: posted as a linked expense (voided with the transfer).
      await recordIn(
          t,
          uid,
          TxnDraft(type: TxnType.expense, accountId: from.id, amount: d.fee, currency: from.currency, categoryId: feeCategoryId,
              title: 'fee:${txn.id}', txnDate: d.txnDate, idempotencyKey: '${d.idempotencyKey}:fee'),
          parentId: txn.id);
    }
    return txn;
  }

  /// Applies the balance effect of an already-inserted [txn] (used when a
  /// transaction arrives from the cloud).
  Future<void> applyEffect(Transaction t, String uid, FinTransaction txn) async {
    if (txn.type == TxnType.transfer) {
      await applyToAccount(t, uid, txn.accountId!, -txn.amount);
      await applyToAccount(t, uid, txn.toAccountId!, txn.toAmount!);
    } else if (txn.accountId != null) {
      await applyToAccount(t, uid, txn.accountId!, txn.effectiveAccountAmount * Decimal.fromInt(txn.type.sign));
    }
  }

  /// Reverses the balance effect of [txn] (no row change).
  Future<void> reverseEffect(Transaction t, String uid, FinTransaction txn) async {
    if (txn.type == TxnType.transfer) {
      await applyToAccount(t, uid, txn.accountId!, txn.amount);
      await applyToAccount(t, uid, txn.toAccountId!, -txn.toAmount!);
    } else if (txn.accountId != null) {
      await applyToAccount(t, uid, txn.accountId!, -(txn.effectiveAccountAmount * Decimal.fromInt(txn.type.sign)));
    }
  }

  /// Soft-delete: marks the row voided and reverses its balance effect (and its
  /// fee child / bill payment) inside the caller's transaction. Audited.
  Future<FinTransaction> voidIn(Transaction t, String uid, String id, String reason) async {
    final txn = await load(t, uid, id);
    if (txn.isVoid) return txn;
    await reverseEffect(t, uid, txn);
    final now = DateTime.now().toUtc();
    final after = {...txn.toMap(), 'status': TxnStatus.voided.name, 'voided_at': now.toIso8601String(), 'void_reason': reason, 'updated_at': now.toIso8601String()};
    await t.update('transactions', {'status': TxnStatus.voided.name, 'voided_at': now.toIso8601String(), 'void_reason': reason, 'updated_at': now.toIso8601String()},
        where: 'id = ?', whereArgs: [id]);
    await audit(t, uid, 'transactions', id, 'void', before: txn.toMap(), after: after);
    await enqueue(t, uid, 'transactions', id, 'void_txn', {'id': id, 'reason': reason, 'voided_at': now.toIso8601String()});
    // children (transfer fee)
    final kids = await t.query('transactions', columns: ['id'], where: 'parent_id = ? AND status = ?', whereArgs: [id, 'posted']);
    for (final k in kids) {
      await voidIn(t, uid, k['id'] as String, reason);
    }
    // bill payment linked to this txn: mark voided and re-open that cycle
    final bp = await t.query('bill_payments', where: 'txn_id = ? AND voided = 0', whereArgs: [id]);
    for (final p in bp) {
      await t.update('bill_payments', {'voided': 1}, where: 'id = ?', whereArgs: [p['id']]);
      await t.update('bills', {'due_date': p['due_date'], 'active': 1, 'updated_at': now.toIso8601String()}, where: 'id = ?', whereArgs: [p['bill_id']]);
      await audit(t, uid, 'bill_payments', p['id'] as String, 'void', before: p);
    }
    // a voided debt payment can re-open a settled debt
    if (txn.refType == 'debt' && txn.refId != null) {
      await t.update('debts', {'status': 'open', 'updated_at': now.toIso8601String()}, where: 'id = ? AND user_id = ?', whereArgs: [txn.refId, uid]);
    }
    return FinTransaction.fromMap({...after});
  }

  /// Edits an income/expense in place: reverse old effect, apply new, audit before/after.
  Future<FinTransaction> updateIn(Transaction t, String uid, String id, TxnDraft d) async {
    final old = await load(t, uid, id);
    if (old.isVoid) throw const AppException('err_txn_voided');
    if (old.type != TxnType.income && old.type != TxnType.expense) throw const AppException('err_edit_type');
    if (d.type != old.type) throw const AppException('err_edit_type');
    _validate(d);
    await _checkCategory(t, uid, d);
    await reverseEffect(t, uid, old);
    final acc = await loadAccount(t, uid, d.accountId!);
    if (!acc.isActive) throw const AppException('err_account_inactive');
    final accConv = await convert(t, uid, d.amount, d.currency, acc.currency, d.txnDate);
    final base = await baseCurrency(t, uid);
    final baseConv = await convert(t, uid, d.amount, d.currency, base, d.txnDate);
    final now = DateTime.now().toUtc();
    final updated = FinTransaction(
      id: old.id, userId: uid, type: old.type, accountId: acc.id, categoryId: d.categoryId, amount: Money.round(d.amount), currency: d.currency,
      accountAmount: accConv.amount, accountRateId: accConv.rateId, fee: Decimal.zero, parentId: old.parentId,
      baseAmount: baseConv.amount, baseCurrency: base, baseRateId: baseConv.rateId, baseRate: baseConv.rate,
      title: d.title.trim(), notes: d.notes.trim(), txnDate: d.txnDate, createdAt: old.createdAt, updatedAt: now,
      idempotencyKey: old.idempotencyKey, recurringId: old.recurringId, refType: old.refType, refId: old.refId, attachments: d.attachments,
    );
    await t.update('transactions', updated.toMap(), where: 'id = ?', whereArgs: [id]);
    await applyToAccount(t, uid, acc.id, accConv.amount * Decimal.fromInt(d.type.sign));
    await audit(t, uid, 'transactions', id, 'update', before: old.toMap(), after: updated.toMap());
    await enqueue(t, uid, 'transactions', id, 'update_txn', updated.toMap());
    return updated;
  }

  Future<String> builtinCategoryId(DatabaseExecutor t, String uid, String key) async {
    final r = await t.query('categories', columns: ['id'], where: 'user_id = ? AND key = ?', whereArgs: [uid, key]);
    if (r.isEmpty) throw const AppException('err_category_required');
    return r.first['id'] as String;
  }
}
