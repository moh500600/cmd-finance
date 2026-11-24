import 'package:decimal/decimal.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/currency.dart';
import '../../domain/repositories/repositories.dart';
import 'ledger_engine.dart';

class CurrencyRepositoryImpl implements CurrencyRepository {
  final LedgerEngine engine;
  CurrencyRepositoryImpl(this.engine);
  Database get db => engine.db;

  @override
  Future<List<Currency>> currencies() async => (await db.query('currencies', orderBy: 'builtin DESC, code')).map(Currency.fromMap).toList();

  @override
  Future<void> addCurrency(Currency c) async {
    final code = c.code.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(code)) throw const AppException('err_currency_code');
    if (c.decimals < 0 || c.decimals > 4) throw const AppException('err_currency_code');
    await db.insert('currencies', {...c.toMap(), 'code': code, 'builtin': 0}, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<List<ExchangeRate>> rates(String uid, {String? from, String? to}) async {
    final where = StringBuffer('user_id = ?');
    final args = <Object>[uid];
    if (from != null && to != null) {
      where.write(' AND ((from_ccy = ? AND to_ccy = ?) OR (from_ccy = ? AND to_ccy = ?))');
      args.addAll([from, to, to, from]);
    }
    return (await db.query('exchange_rates', where: where.toString(), whereArgs: args, orderBy: 'rate_date DESC, created_at DESC'))
        .map(ExchangeRate.fromMap)
        .toList();
  }

  @override
  Future<ExchangeRate> addRate(String uid, {required String from, required String to, required Decimal rate, required String source, required DateTime date}) async {
    if (from == to) throw const AppException('err_rate_same');
    if (rate.sign <= 0) throw const AppException('err_rate_positive');
    if (source.trim().isEmpty) throw const AppException('err_rate_source');
    final r = ExchangeRate(id: newId(), userId: uid, from: from, to: to, rate: rate, source: source.trim(), rateDate: dayOnly(date), createdAt: DateTime.now().toUtc());
    final row = {...r.toMap(), 'rate_date': isoDay(date)};
    await engine.atomic((t) async {
      await t.insert('exchange_rates', row);
      await engine.track(t, uid, 'exchange_rates', r.id, 'create', after: row);
    });
    return r;
  }

  @override
  Future<void> deleteRate(String uid, String id) async {
    await engine.atomic((t) async {
      final used = await t.rawQuery(
          'SELECT COUNT(*) c FROM transactions WHERE user_id = ? AND (base_rate_id = ? OR account_rate_id = ?)', [uid, id, id]);
      if ((used.first['c'] as int) > 0) throw const AppException('err_rate_in_use');
      final before = await t.query('exchange_rates', where: 'id = ? AND user_id = ?', whereArgs: [id, uid]);
      if (before.isEmpty) return;
      await t.delete('exchange_rates', where: 'id = ?', whereArgs: [id]);
      await engine.track(t, uid, 'exchange_rates', id, 'delete', before: before.first);
    });
  }

  @override
  Future<Conversion> convert(String uid, Decimal amount, String from, String to, DateTime date) => engine.convert(db, uid, amount, from, to, date);

  @override
  Future<Conversion?> tryConvert(String uid, Decimal amount, String from, String to, DateTime date) async {
    try {
      return await convert(uid, amount, from, to, date);
    } on MissingRateException {
      return null;
    }
  }

  @override
  Future<void> changeBaseCurrency(String uid, String newBase) async {
    await engine.atomic((t) async {
      final old = await engine.baseCurrency(t, uid);
      if (old == newBase) return;
      final rows = await t.query('transactions', where: 'user_id = ?', whereArgs: [uid]);
      for (final r in rows) {
        final amount = Money.fromDb(r['amount']);
        final c = await engine.convert(t, uid, amount, r['currency'] as String, newBase, DateTime.parse(r['txn_date'] as String));
        await t.update('transactions', {'base_amount': Money.toDb(c.amount), 'base_currency': newBase, 'base_rate_id': c.rateId, 'base_rate': c.rate.toString()},
            where: 'id = ?', whereArgs: [r['id']]);
      }
      // budgets are kept in base currency: convert limits at today's rate
      final budgets = await t.query('budgets', where: 'user_id = ?', whereArgs: [uid]);
      for (final b in budgets) {
        final c = await engine.convert(t, uid, Money.fromDb(b['limit_amount']), b['currency'] as String, newBase, DateTime.now());
        await t.update('budgets', {'limit_amount': Money.toDb(c.amount), 'currency': newBase}, where: 'id = ?', whereArgs: [b['id']]);
      }
      await t.update('users', {'base_currency': newBase, 'updated_at': nowUtc()}, where: 'id = ?', whereArgs: [uid]);
      await engine.audit(t, uid, 'users', uid, 'base_currency', before: {'base_currency': old}, after: {'base_currency': newBase, 'rebased_rows': rows.length});
    });
  }
}
