import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/holdings.dart';
import '../../domain/repositories/repositories.dart';
import '../db/app_database.dart';
import 'ledger_engine.dart';

class AssetRepositoryImpl implements AssetRepository {
  final LedgerEngine engine;
  AssetRepositoryImpl(this.engine);
  Database get db => engine.db;

  @override
  Future<List<Asset>> assets(String uid) async =>
      (await db.query('assets', where: 'user_id = ?', whereArgs: [uid], orderBy: 'created_at')).map(Asset.fromMap).toList();

  @override
  Future<Asset> saveAsset(String uid, {String? id, required String name, required AssetType type, required Decimal purchaseValue, required Decimal currentValue,
      required String currency, DateTime? purchaseDate, List<String> documents = const [], String notes = ''}) {
    if (name.trim().isEmpty) throw const AppException('err_name_required');
    if (purchaseValue.sign < 0 || currentValue.sign < 0) throw const AppException('err_amount_positive');
    return engine.atomic((t) async {
      final before = id == null ? null : (await t.query('assets', where: 'id = ? AND user_id = ?', whereArgs: [id, uid])).firstOrNull;
      final now = DateTime.now().toUtc();
      final a = Asset(id: id ?? newId(), userId: uid, name: name.trim(), type: type, purchaseValue: purchaseValue, currentValue: currentValue,
          currency: currency, purchaseDate: purchaseDate, documents: documents, notes: notes.trim(),
          createdAt: before == null ? now : DateTime.parse(before['created_at'] as String), updatedAt: now);
      await t.insert('assets', a.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      await engine.track(t, uid, 'assets', a.id, before == null ? 'create' : 'update', before: before, after: a.toMap());
      final changed = before == null || Money.fromDb(before['current_value']) != currentValue;
      if (changed) {
        final v = {'id': newId(), 'user_id': uid, 'asset_id': a.id, 'value': Money.toDb(currentValue), 'date': DateTime.now().toIso8601String(), 'note': before == null ? 'initial' : 'edit'};
        await t.insert('asset_values', v);
        await engine.enqueue(t, uid, 'asset_values', v['id'] as String, 'upsert', v);
      }
      return a;
    });
  }

  @override
  Future<void> addValue(String uid, String assetId, Decimal value, DateTime date, {String note = ''}) => engine.atomic((t) async {
        if (value.sign < 0) throw const AppException('err_amount_positive');
        final before = (await t.query('assets', where: 'id = ? AND user_id = ?', whereArgs: [assetId, uid])).firstOrNull;
        if (before == null) throw const AppException('err_not_found');
        final v = {'id': newId(), 'user_id': uid, 'asset_id': assetId, 'value': Money.toDb(value), 'date': date.toIso8601String(), 'note': note.trim()};
        await t.insert('asset_values', v);
        await t.update('assets', {'current_value': Money.toDb(value), 'updated_at': nowUtc()}, where: 'id = ?', whereArgs: [assetId]);
        await engine.track(t, uid, 'assets', assetId, 'revalue', before: before, after: {...before, 'current_value': Money.toDb(value)});
        await engine.enqueue(t, uid, 'asset_values', v['id'] as String, 'upsert', v);
      });

  @override
  Future<List<ValuePoint>> history(String uid, String assetId) async => (await db.query('asset_values',
          where: 'user_id = ? AND asset_id = ?', whereArgs: [uid, assetId], orderBy: 'date'))
      .map((m) => ValuePoint(id: m['id'] as String, parentId: assetId, value: Money.fromDb(m['value']), date: DateTime.parse(m['date'] as String), note: m['note'] as String))
      .toList();

  @override
  Future<void> deleteAsset(String uid, String id) => engine.atomic((t) async {
        final before = (await t.query('assets', where: 'id = ? AND user_id = ?', whereArgs: [id, uid])).firstOrNull;
        await t.delete('assets', where: 'id = ? AND user_id = ?', whereArgs: [id, uid]);
        await engine.track(t, uid, 'assets', id, 'delete', before: before);
      });
}

class InvestmentRepositoryImpl implements InvestmentRepository {
  final LedgerEngine engine;
  InvestmentRepositoryImpl(this.engine);
  Database get db => engine.db;

  @override
  Future<List<InvestmentPerformance>> investments(String uid) async {
    final rows = await db.query('investments', where: 'user_id = ?', whereArgs: [uid], orderBy: 'start_date');
    final out = <InvestmentPerformance>[];
    for (final r in rows) {
      final inv = Investment.fromMap(r);
      final e = (await db.query('investment_entries', where: 'investment_id = ?', whereArgs: [inv.id], orderBy: 'date')).map(InvestmentEntry.fromMap).toList();
      out.add(InvestmentPerformance(inv, e));
    }
    return out;
  }

  @override
  Future<Investment> saveInvestment(String uid, {String? id, required String name, required InvestmentType type, required String currency,
      required DateTime startDate, required Decimal capital, Decimal? currentValue, String notes = ''}) {
    if (name.trim().isEmpty) throw const AppException('err_name_required');
    if (capital.sign <= 0) throw const AppException('err_amount_positive');
    return engine.atomic((t) async {
      final before = id == null ? null : (await t.query('investments', where: 'id = ? AND user_id = ?', whereArgs: [id, uid])).firstOrNull;
      final now = DateTime.now().toUtc();
      final inv = Investment(id: id ?? newId(), userId: uid, name: name.trim(), type: type, currency: before?['currency'] as String? ?? currency,
          startDate: startDate, currentValue: currentValue ?? capital, notes: notes.trim(),
          createdAt: before == null ? now : DateTime.parse(before['created_at'] as String), updatedAt: now);
      await t.insert('investments', inv.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      await engine.track(t, uid, 'investments', inv.id, before == null ? 'create' : 'update', before: before, after: inv.toMap());
      if (before == null) {
        await _entry(t, uid, inv.id, InvestmentEntryKind.contribution, capital, startDate, 'initial');
      }
      return inv;
    });
  }

  Future<void> _entry(DatabaseExecutor t, String uid, String invId, InvestmentEntryKind kind, Decimal amount, DateTime date, String note) async {
    final row = {'id': newId(), 'user_id': uid, 'investment_id': invId, 'kind': kind.name, 'amount': Money.toDb(amount), 'date': date.toIso8601String(), 'note': note};
    await t.insert('investment_entries', row);
    await engine.track(t, uid, 'investment_entries', row['id'] as String, 'create', after: row);
  }

  @override
  Future<void> addEntry(String uid, String investmentId, InvestmentEntryKind kind, Decimal amount, DateTime date, {String note = ''}) => engine.atomic((t) async {
        if (amount.sign < 0 || (kind != InvestmentEntryKind.valuation && amount.sign == 0)) throw const AppException('err_amount_positive');
        final before = (await t.query('investments', where: 'id = ? AND user_id = ?', whereArgs: [investmentId, uid])).firstOrNull;
        if (before == null) throw const AppException('err_not_found');
        await _entry(t, uid, investmentId, kind, amount, date, note.trim());
        // tracking only: contributions/withdrawals move the tracked value, valuations set it
        final cur = Money.fromDb(before['current_value']);
        final next = switch (kind) {
          InvestmentEntryKind.valuation => amount,
          InvestmentEntryKind.contribution => cur + amount,
          InvestmentEntryKind.withdrawal => cur - amount,
          InvestmentEntryKind.dividend => cur,
        };
        if (next.sign < 0) throw const AppException('err_withdraw_exceeds');
        await t.update('investments', {'current_value': Money.toDb(next), 'updated_at': nowUtc()}, where: 'id = ?', whereArgs: [investmentId]);
        await engine.track(t, uid, 'investments', investmentId, 'entry_${kind.name}', before: before, after: {...before, 'current_value': Money.toDb(next)});
      });

  @override
  Future<void> deleteInvestment(String uid, String id) => engine.atomic((t) async {
        final before = (await t.query('investments', where: 'id = ? AND user_id = ?', whereArgs: [id, uid])).firstOrNull;
        await t.delete('investments', where: 'id = ? AND user_id = ?', whereArgs: [id, uid]);
        await engine.track(t, uid, 'investments', id, 'delete', before: before);
      });
}

/// JSON backup of every user-owned row (money stays as decimal strings).
class BackupRepositoryImpl implements BackupRepository {
  final LedgerEngine engine;
  BackupRepositoryImpl(this.engine);
  Database get db => engine.db;

  @override
  Future<Map<String, Object?>> export(String uid) async {
    final user = (await db.query('users', columns: ['name', 'email', 'base_currency'], where: 'id = ?', whereArgs: [uid])).first;
    final out = <String, Object?>{'app': 'finance_pro', 'format': 1, 'exported_at': nowUtc(), 'user': user,
      'currencies': await db.query('currencies', where: 'builtin = 0')};
    for (final table in AppDatabase.userTables) {
      out[table] = await db.query(table, where: 'user_id = ?', whereArgs: [uid]);
    }
    return out;
  }

  /// Replaces this user's data with the backup, atomically. Rows are re-owned
  /// by the current user; ids are kept so links stay intact.
  @override
  Future<void> restore(String uid, Map<String, Object?> data) async {
    if (data['app'] != 'finance_pro') throw const AppException('err_backup_invalid');
    await db.transaction((t) async {
      for (final c in (data['currencies'] as List? ?? const [])) {
        await t.insert('currencies', Map<String, Object?>.from(c as Map), conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      await t.update('transactions', {'parent_id': null}, where: 'user_id = ?', whereArgs: [uid]);
      for (final table in AppDatabase.userTables.reversed) {
        await t.delete(table, where: 'user_id = ?', whereArgs: [uid]);
      }
      final deferredParents = <String, Object?>{};
      for (final table in AppDatabase.userTables) {
        for (final row in (data[table] as List? ?? const [])) {
          final m = Map<String, Object?>.from(row as Map)..['user_id'] = uid;
          if (table == 'transactions' && m['parent_id'] != null) {
            deferredParents[m['id'] as String] = m['parent_id'];
            m['parent_id'] = null;
          }
          await t.insert(table, m, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
      for (final e in deferredParents.entries) {
        await t.update('transactions', {'parent_id': e.value}, where: 'id = ?', whereArgs: [e.key]);
      }
      final user = data['user'] as Map?;
      if (user?['base_currency'] != null) {
        await t.update('users', {'base_currency': user!['base_currency']}, where: 'id = ?', whereArgs: [uid]);
      }
      await engine.audit(t, uid, 'users', uid, 'restore_backup', after: {'exported_at': data['exported_at']});
    });
  }

  static String encode(Map<String, Object?> m) => const JsonEncoder.withIndent(' ').convert(m);
}
