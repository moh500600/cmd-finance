import 'package:decimal/decimal.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/account.dart';
import '../../domain/repositories/repositories.dart';
import 'ledger_engine.dart';

class AccountRepositoryImpl implements AccountRepository {
  final LedgerEngine engine;
  AccountRepositoryImpl(this.engine);
  Database get db => engine.db;

  @override
  Future<List<Account>> accounts(String uid, {bool includeInactive = true}) async => (await db.query('accounts',
          where: includeInactive ? 'user_id = ?' : 'user_id = ? AND is_active = 1', whereArgs: [uid], orderBy: 'is_active DESC, created_at'))
      .map(Account.fromMap)
      .toList();

  @override
  Future<Account?> account(String uid, String id) async {
    final r = await db.query('accounts', where: 'id = ? AND user_id = ?', whereArgs: [id, uid]);
    return r.isEmpty ? null : Account.fromMap(r.first);
  }

  @override
  Future<Account> createAccount(String uid, {required String name, required AccountType type, required String currency, required Decimal openingBalance,
      String description = '', int color = 0xFF0F766E, Decimal? lowBalanceAlert}) async {
    if (name.trim().isEmpty) throw const AppException('err_name_required');
    if (openingBalance.scale > Money.storageScale) throw const AppException('err_amount_scale');
    final now = DateTime.now().toUtc();
    final a = Account(id: newId(), userId: uid, name: name.trim(), type: type, currency: currency, openingBalance: openingBalance, balance: openingBalance,
        description: description.trim(), color: color, lowBalanceAlert: lowBalanceAlert, createdAt: now, updatedAt: now);
    await engine.atomic((t) async {
      await t.insert('accounts', a.toMap());
      await engine.audit(t, uid, 'accounts', a.id, 'create', after: a.toMap());
      await engine.enqueue(t, uid, 'accounts', a.id, 'upsert_account', a.toMap());
    });
    return a;
  }

  /// Metadata edit. Changing the opening balance shifts the current balance by
  /// the same delta (atomic + audited). Currency cannot change once created.
  @override
  Future<Account> updateAccount(String uid, Account updated) async {
    if (updated.name.trim().isEmpty) throw const AppException('err_name_required');
    return engine.atomic((t) async {
      final old = await engine.loadAccount(t, uid, updated.id);
      final delta = updated.openingBalance - old.openingBalance;
      final next = updated.copyWith(balance: old.balance + delta, updatedAt: DateTime.now().toUtc());
      await t.update('accounts', next.toMap(), where: 'id = ?', whereArgs: [old.id]);
      await engine.audit(t, uid, 'accounts', old.id, 'update', before: old.toMap(), after: next.toMap());
      await engine.enqueue(t, uid, 'accounts', old.id, 'upsert_account', next.toMap());
      return next;
    });
  }

  @override
  Future<void> setActive(String uid, String id, bool active) async {
    await engine.atomic((t) async {
      final old = await engine.loadAccount(t, uid, id);
      final next = old.copyWith(isActive: active, updatedAt: DateTime.now().toUtc());
      await t.update('accounts', {'is_active': active ? 1 : 0, 'updated_at': nowUtc()}, where: 'id = ?', whereArgs: [id]);
      await engine.audit(t, uid, 'accounts', id, active ? 'enable' : 'disable', before: old.toMap(), after: next.toMap());
      await engine.enqueue(t, uid, 'accounts', id, 'upsert_account', next.toMap());
    });
  }

  @override
  Future<List<Category>> categories(String uid, {CategoryKind? kind, bool includeArchived = false}) async {
    final w = StringBuffer('user_id = ?');
    final a = <Object>[uid];
    if (kind != null) {
      w.write(' AND kind = ?');
      a.add(kind.name);
    }
    if (!includeArchived) w.write(' AND archived = 0');
    return (await db.query('categories', where: w.toString(), whereArgs: a, orderBy: 'key IS NULL, rowid')).map(Category.fromMap).toList();
  }

  @override
  Future<Category> saveCategory(String uid, {String? id, required CategoryKind kind, required String name, required int icon, required int color}) async {
    if (name.trim().isEmpty) throw const AppException('err_name_required');
    final c = Category(id: id ?? newId(), userId: uid, kind: kind, name: name.trim(), icon: icon, color: color);
    await engine.atomic((t) async {
      final before = id == null ? null : (await t.query('categories', where: 'id = ? AND user_id = ?', whereArgs: [id, uid])).firstOrNull;
      if (before != null && before['key'] != null) throw const AppException('err_builtin_category');
      final row = {...c.toMap(), 'updated_at': nowUtc()};
      await t.insert('categories', row, conflictAlgorithm: ConflictAlgorithm.replace);
      await engine.track(t, uid, 'categories', c.id, before == null ? 'create' : 'update', before: before, after: row);
    });
    return c;
  }

  @override
  Future<void> archiveCategory(String uid, String id) async {
    await engine.atomic((t) async {
      final before = (await t.query('categories', where: 'id = ? AND user_id = ?', whereArgs: [id, uid])).firstOrNull;
      if (before == null) return;
      await t.update('categories', {'archived': 1, 'updated_at': nowUtc()}, where: 'id = ?', whereArgs: [id]);
      await engine.track(t, uid, 'categories', id, 'archive', before: before, after: {...before, 'archived': 1});
    });
  }
}
