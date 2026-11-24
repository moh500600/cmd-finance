import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/repositories.dart';
import 'ledger_engine.dart';

class TransactionRepositoryImpl implements TransactionRepository {
  final LedgerEngine engine;
  TransactionRepositoryImpl(this.engine);
  Database get db => engine.db;

  @override
  Future<FinTransaction> record(String uid, TxnDraft draft) => engine.atomic((t) => engine.recordIn(t, uid, draft));

  @override
  Future<FinTransaction> transfer(String uid, TransferDraft draft) => engine.atomic((t) async {
        final feeCat = await engine.builtinCategoryId(t, uid, 'fees');
        return engine.transferIn(t, uid, draft, feeCategoryId: feeCat);
      });

  @override
  Future<FinTransaction> updateTxn(String uid, String id, TxnDraft draft) => engine.atomic((t) => engine.updateIn(t, uid, id, draft));

  @override
  Future<FinTransaction> voidTxn(String uid, String id, {String reason = ''}) => engine.atomic((t) async {
        final txn = await engine.load(t, uid, id);
        if (txn.parentId != null) throw const AppException('err_void_parent'); // void the transfer instead
        return engine.voidIn(t, uid, id, reason);
      });

  @override
  Future<FinTransaction?> get(String uid, String id) async {
    final r = await db.query('transactions', where: 'id = ? AND user_id = ?', whereArgs: [id, uid]);
    return r.isEmpty ? null : FinTransaction.fromMap(r.first);
  }

  @override
  Future<List<FinTransaction>> query(String uid, TxnQuery q) async {
    final w = StringBuffer('t.user_id = ?');
    final a = <Object?>[uid];
    if (!q.includeVoided) w.write(" AND t.status = 'posted'");
    if (q.types != null && q.types!.isNotEmpty) {
      w.write(' AND t.type IN (${List.filled(q.types!.length, '?').join(',')})');
      a.addAll(q.types!.map((e) => e.name));
    }
    if (q.accountId != null) {
      w.write(' AND (t.account_id = ? OR t.to_account_id = ?)');
      a.addAll([q.accountId, q.accountId]);
    }
    if (q.categoryId != null) {
      w.write(' AND t.category_id = ?');
      a.add(q.categoryId);
    }
    if (q.currency != null) {
      w.write(' AND (t.currency = ? OR t.to_currency = ?)');
      a.addAll([q.currency, q.currency]);
    }
    if (q.from != null) {
      w.write(' AND t.txn_date >= ?');
      a.add(q.from!.toIso8601String());
    }
    if (q.to != null) {
      w.write(' AND t.txn_date < ?');
      a.add(q.to!.toIso8601String());
    }
    final text = q.text?.trim();
    if (text != null && text.isNotEmpty) {
      final like = '%${Money.normalizeDigits(text)}%';
      w.write(' AND (t.title LIKE ? OR t.notes LIKE ? OR t.amount LIKE ? OR c.name LIKE ? OR c.key LIKE ? OR ac.name LIKE ? OR t.currency LIKE ? OR t.type LIKE ?)');
      a.addAll([like, like, like, like, like, like, like, like]);
    }
    final rows = await db.rawQuery(
        'SELECT t.* FROM transactions t LEFT JOIN categories c ON c.id = t.category_id LEFT JOIN accounts ac ON ac.id = t.account_id '
        'WHERE $w ORDER BY t.txn_date DESC, t.created_at DESC',
        a);
    var list = rows.map(FinTransaction.fromMap).toList();
    // amount filters/sorts are Decimal comparisons (TEXT columns can't be compared numerically in SQL)
    if (q.minAmount != null) list = list.where((x) => x.amount >= q.minAmount!).toList();
    if (q.maxAmount != null) list = list.where((x) => x.amount <= q.maxAmount!).toList();
    switch (q.sort) {
      case 'date_asc':
        list = list.reversed.toList();
      case 'amount_desc':
        list.sort((x, y) => y.baseAmount.compareTo(x.baseAmount));
      case 'amount_asc':
        list.sort((x, y) => x.baseAmount.compareTo(y.baseAmount));
    }
    if (q.limit != null && list.length > q.limit!) list = list.sublist(0, q.limit!);
    return list;
  }

  // ------------------------------------------------------------ recurring
  @override
  Future<List<RecurringRule>> recurringRules(String uid) async =>
      (await db.query('recurring_rules', where: 'user_id = ?', whereArgs: [uid], orderBy: 'next_date')).map(RecurringRule.fromMap).toList();

  @override
  Future<RecurringRule> saveRecurring(String uid, {required TxnDraft template, required Frequency frequency, required DateTime firstDate, DateTime? endDate, bool scheduledOnce = false}) async {
    if (template.amount.sign <= 0) throw const AppException('err_amount_positive');
    final id = newId();
    final row = {
      'id': id, 'user_id': uid, 'scheduled_once': scheduledOnce ? 1 : 0, 'frequency': (scheduledOnce ? Frequency.once : frequency).name,
      'next_date': firstDate.toIso8601String(), 'end_date': endDate?.toIso8601String(), 'active': 1, 'template': jsonEncode(template.toJson()),
      'created_at': nowUtc(), 'updated_at': nowUtc(),
    };
    await engine.atomic((t) async {
      await t.insert('recurring_rules', row);
      await engine.track(t, uid, 'recurring_rules', id, 'create', after: row);
    });
    return RecurringRule.fromMap(row);
  }

  @override
  Future<void> setRecurringActive(String uid, String id, bool active) => engine.atomic((t) async {
        await t.update('recurring_rules', {'active': active ? 1 : 0, 'updated_at': nowUtc()}, where: 'id = ? AND user_id = ?', whereArgs: [id, uid]);
        await engine.track(t, uid, 'recurring_rules', id, active ? 'enable' : 'disable', after: {'id': id, 'active': active ? 1 : 0});
      });

  @override
  Future<void> deleteRecurring(String uid, String id) => engine.atomic((t) async {
        final before = (await t.query('recurring_rules', where: 'id = ? AND user_id = ?', whereArgs: [id, uid])).firstOrNull;
        await t.delete('recurring_rules', where: 'id = ? AND user_id = ?', whereArgs: [id, uid]);
        await engine.track(t, uid, 'recurring_rules', id, 'delete', before: before);
      });

  /// Posts every due occurrence. Each occurrence has the deterministic
  /// idempotency key `rec:<rule>:<day>`, so running this twice never doubles.
  @override
  Future<RecurringResult> processDue(String uid, DateTime now) async {
    var created = 0;
    final errors = <String>[];
    final rules = (await recurringRules(uid)).where((r) => r.active);
    for (final r in rules) {
      var next = r.nextDate;
      var active = true;
      String? error;
      while (!next.isAfter(now) && (r.endDate == null || !next.isAfter(r.endDate!))) {
        final draft = r.template.copyWith(txnDate: next, idempotencyKey: 'rec:${r.id}:${isoDay(next)}', recurringId: r.id);
        try {
          final before = await engine.byKey(db, uid, draft.idempotencyKey);
          await record(uid, draft);
          if (before == null) created++;
        } on AppException catch (e) {
          error = e.code == 'err_missing_rate' ? 'missing_rate:${e.args['from']}:${e.args['to']}' : e.code;
          errors.add(error);
          break;
        }
        if (r.scheduledOnce) {
          active = false;
          break;
        }
        next = nextOccurrence(next, r.frequency);
      }
      if (r.endDate != null && next.isAfter(r.endDate!)) active = false;
      await db.update('recurring_rules', {'next_date': next.toIso8601String(), 'active': active ? 1 : 0, 'last_error': error, 'updated_at': nowUtc()},
          where: 'id = ?', whereArgs: [r.id]);
    }
    return RecurringResult(created, errors);
  }

  @override
  Future<List<AuditEntry>> audit(String uid, {String? entity, String? entityId, int limit = 200}) async {
    final w = StringBuffer('user_id = ?');
    final a = <Object>[uid];
    if (entity != null) {
      w.write(' AND entity = ?');
      a.add(entity);
    }
    if (entityId != null) {
      w.write(' AND entity_id = ?');
      a.add(entityId);
    }
    return (await db.query('audit_log', where: w.toString(), whereArgs: a, orderBy: 'at DESC', limit: limit)).map(AuditEntry.fromMap).toList();
  }
}
