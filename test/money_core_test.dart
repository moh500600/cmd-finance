import 'package:decimal/decimal.dart';
import 'package:finance_pro/core/errors/app_exception.dart';
import 'package:finance_pro/core/money/money.dart';
import 'package:finance_pro/core/utils/dates.dart';
import 'package:finance_pro/domain/entities/holdings.dart';
import 'package:finance_pro/domain/entities/planning.dart';
import 'package:finance_pro/domain/entities/transaction.dart';
import 'package:finance_pro/domain/repositories/repositories.dart';
import 'package:finance_pro/domain/services/finance_math.dart';
import 'package:finance_pro/domain/services/snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('Money (Decimal only)', () {
    test('parses Arabic digits and separators exactly', () {
      expect(Money.parse('١٢٣٤٫٥٦'), d('1234.56'));
      expect(Money.parse('5,000'), d('5000'));
      expect(Money.tryParse('abc'), isNull);
      expect(Money.tryParse('1e5'), isNull);
    });
    test('0.1 + 0.2 == 0.3 (no binary floating point)', () {
      expect(d('0.1') + d('0.2'), d('0.3'));
      expect(Money.sum([d('0.1'), d('0.1'), d('0.1')]), d('0.3'));
    });
    test('format groups digits and respects currency decimals', () {
      expect(Money.format(d('1234567.891'), currency: 'USD'), '1,234,567.89 USD');
      expect(Money.format(d('1500.6'), currency: 'YER'), '1,501 YER');
      expect(Money.format(d('-42'), decimals: 2), '-42.00');
    });
    test('percent and division round deterministically', () {
      expect(Money.percent(d('1'), d('3')), d('33.33'));
      expect(Money.div(d('10'), d('4'), scale: 4), d('2.5'));
    });
    test('MoneyAmount refuses to add mixed currencies', () {
      expect(() => MoneyAmount(Decimal.zero, 'USD') + MoneyAmount(Decimal.one, 'YER'), throwsA(isA<MixedCurrencyException>()));
    });
  });

  group('Exchange rates (manual only)', () {
    test('missing rate throws, never assumes', () async {
      final e = await Env.create();
      expect(() => e.fx.convert(e.uid, d('10'), 'USD', 'YER', DateTime.now()), throwsA(isA<MissingRateException>()));
    });
    test('uses latest rate on/before the date, and exact inverse', () async {
      final e = await Env.create();
      await e.fx.addRate(e.uid, from: 'USD', to: 'YER', rate: d('530'), source: 'Bank A', date: DateTime(2026, 1, 1));
      await e.fx.addRate(e.uid, from: 'USD', to: 'YER', rate: d('540'), source: 'Bank A', date: DateTime(2026, 3, 1));
      expect((await e.fx.convert(e.uid, d('2'), 'USD', 'YER', DateTime(2026, 2, 15))).amount, d('1060'));
      expect((await e.fx.convert(e.uid, d('2'), 'USD', 'YER', DateTime(2026, 3, 2))).amount, d('1080'));
      final inv = await e.fx.convert(e.uid, d('5400'), 'YER', 'USD', DateTime(2026, 3, 2));
      expect(inv.inverted, isTrue);
      expect(inv.amount, d('10'));
      expect(() => e.fx.convert(e.uid, d('1'), 'USD', 'YER', DateTime(2025, 12, 31)), throwsA(isA<MissingRateException>()));
    });
    test('rate requires a source and a positive value', () async {
      final e = await Env.create();
      expect(() => e.fx.addRate(e.uid, from: 'USD', to: 'YER', rate: d('0'), source: 'x', date: DateTime.now()), throwsA(isA<AppException>()));
      expect(() => e.fx.addRate(e.uid, from: 'USD', to: 'YER', rate: d('1'), source: ' ', date: DateTime.now()), throwsA(isA<AppException>()));
    });
  });

  group('Ledger', () {
    test('expense in another currency stores original, account and base amounts + rate ids', () async {
      final e = await Env.create(base: 'YER');
      final rate = await e.fx.addRate(e.uid, from: 'USD', to: 'YER', rate: d('535.5'), source: 'CBY', date: DateTime(2026, 1, 1));
      final usd = await e.acc('Wallet', 'USD', '100');
      final t = await e.txns.record(e.uid, TxnDraft(type: TxnType.expense, accountId: usd.id, amount: d('12.40'), currency: 'USD',
          categoryId: await e.cat('food'), txnDate: DateTime(2026, 2, 1), idempotencyKey: 'k1'));
      expect(t.amount, d('12.4'));
      expect(t.accountAmount, d('12.4'));
      expect(t.baseAmount, d('6640.2'));
      expect(t.baseRateId, rate.id);
      expect(t.createdAt, isNotNull);
      expect(await e.balance(usd.id), d('87.6'));
    });

    test('same idempotency key twice records once', () async {
      final e = await Env.create();
      final a = await e.acc('Cash', 'YER', '10000');
      final draft = TxnDraft(type: TxnType.expense, accountId: a.id, amount: d('5000'), currency: 'YER', categoryId: await e.cat('food'),
          txnDate: DateTime.now(), idempotencyKey: 'tap-1');
      final t1 = await e.txns.record(e.uid, draft);
      final t2 = await e.txns.record(e.uid, draft);
      expect(t2.id, t1.id);
      expect(await e.balance(a.id), d('5000'));
      expect((await e.txns.query(e.uid, const TxnQuery())).length, 1);
    });

    test('missing rate aborts atomically: no row, no balance change, no audit', () async {
      final e = await Env.create(base: 'YER');
      final usd = await e.acc('Wallet', 'USD', '100');
      final auditBefore = (await e.txns.audit(e.uid)).length;
      await expectLater(
          e.txns.record(e.uid, TxnDraft(type: TxnType.expense, accountId: usd.id, amount: d('10'), currency: 'USD', categoryId: await e.cat('food'),
              txnDate: DateTime.now(), idempotencyKey: 'k')),
          throwsA(isA<MissingRateException>()));
      expect(await e.balance(usd.id), d('100'));
      expect((await e.txns.query(e.uid, const TxnQuery())), isEmpty);
      expect((await e.txns.audit(e.uid)).length, auditBefore);
    });

    test('transfers move money, are excluded from income/expense totals; fee is a linked expense', () async {
      final e = await Env.create(base: 'YER');
      await e.fx.addRate(e.uid, from: 'SAR', to: 'YER', rate: d('140'), source: 'exchange shop', date: DateTime(2026, 1, 1));
      final sar = await e.acc('Al-Rajhi', 'SAR', '1000');
      final yer = await e.acc('Cash YER', 'YER', '0');
      final t = await e.txns.transfer(e.uid, TransferDraft(fromAccountId: sar.id, toAccountId: yer.id, amount: d('500'), toAmount: d('69500'),
          fee: d('5'), txnDate: DateTime(2026, 2, 1), idempotencyKey: 'tr1'));
      expect(t.fxRate, d('139'));
      expect(t.toAmount, d('69500'));
      expect(await e.balance(sar.id), d('495'));
      expect(await e.balance(yer.id), d('69500'));
      final all = await e.txns.query(e.uid, const TxnQuery());
      expect(FinanceMath.sumBase(all, TxnType.income), Decimal.zero);
      expect(FinanceMath.sumBase(all, TxnType.expense), d('700')); // only the 5 SAR fee
      final s = await e.loader.load(e.uid, now: DateTime(2026, 2, 2));
      final st = DashboardStats.compute(s, DateRange.of(PeriodKind.monthly, DateTime(2026, 2, 2)));
      expect(st.income.total, Decimal.zero);
      expect(st.expense.total, d('700'));
    });

    test('voiding reverses balance (incl. transfer fee) and writes audit rows', () async {
      final e = await Env.create();
      final a = await e.acc('A', 'YER', '1000');
      final b = await e.acc('B', 'YER', '0');
      final t = await e.txns.transfer(e.uid, TransferDraft(fromAccountId: a.id, toAccountId: b.id, amount: d('300'), fee: d('10'), txnDate: DateTime.now(), idempotencyKey: 'x'));
      expect(await e.balance(a.id), d('690'));
      await e.txns.voidTxn(e.uid, t.id, reason: 'mistake');
      expect(await e.balance(a.id), d('1000'));
      expect(await e.balance(b.id), d('0'));
      final audit = await e.txns.audit(e.uid, entity: 'transactions');
      expect(audit.where((x) => x.action == 'void').length, 2);
      final voided = await e.txns.get(e.uid, t.id);
      expect(voided!.isVoid, isTrue);
      expect(await e.txns.query(e.uid, const TxnQuery()), isEmpty);
      expect((await e.txns.query(e.uid, const TxnQuery(includeVoided: true))).length, 2);
    });

    test('editing reverses old effect and applies the new one', () async {
      final e = await Env.create();
      final a = await e.acc('A', 'YER', '1000');
      final b = await e.acc('B', 'YER', '1000');
      final cat = await e.cat('food');
      final t = await e.txns.record(e.uid, TxnDraft(type: TxnType.expense, accountId: a.id, amount: d('100'), currency: 'YER', categoryId: cat, txnDate: DateTime.now(), idempotencyKey: 'e'));
      await e.txns.updateTxn(e.uid, t.id, TxnDraft(type: TxnType.expense, accountId: b.id, amount: d('250'), currency: 'YER', categoryId: cat, txnDate: DateTime.now(), idempotencyKey: 'e'));
      expect(await e.balance(a.id), d('1000'));
      expect(await e.balance(b.id), d('750'));
      final audit = await e.txns.audit(e.uid, entityId: t.id);
      expect(audit.first.action, 'update');
      expect(audit.first.before, contains('"amount":"100"'));
    });

    test('ledger balance == opening + sum of effects after many ops', () async {
      final e = await Env.create();
      final a = await e.acc('A', 'YER', '0');
      final inc = await e.cat('salary'), food = await e.cat('food');
      for (var i = 0; i < 20; i++) {
        await e.txns.record(e.uid, TxnDraft(type: i.isEven ? TxnType.income : TxnType.expense, accountId: a.id, amount: d('${i + 1}.25'),
            currency: 'YER', categoryId: i.isEven ? inc : food, txnDate: DateTime.now(), idempotencyKey: 'k$i'));
      }
      final all = await e.txns.query(e.uid, const TxnQuery());
      final ledger = Money.sum(all.map((t) => t.effectiveAccountAmount * Decimal.fromInt(t.type.sign)));
      expect(await e.balance(a.id), ledger);
      expect(ledger, d('-10'));
    });

    test('category kind must match type; amount must be positive', () async {
      final e = await Env.create();
      final a = await e.acc('A', 'YER', '0');
      expect(() => e.txns.record(e.uid, TxnDraft(type: TxnType.income, accountId: a.id, amount: d('1'), currency: 'YER', categoryId: null, txnDate: DateTime.now(), idempotencyKey: 'z')),
          throwsA(isA<AppException>()));
      final food = await e.cat('food');
      expect(() => e.txns.record(e.uid, TxnDraft(type: TxnType.income, accountId: a.id, amount: d('1'), currency: 'YER', categoryId: food, txnDate: DateTime.now(), idempotencyKey: 'z')),
          throwsA(isA<AppException>()));
      expect(() => e.txns.record(e.uid, TxnDraft(type: TxnType.expense, accountId: a.id, amount: d('-1'), currency: 'YER', categoryId: food, txnDate: DateTime.now(), idempotencyKey: 'z')),
          throwsA(isA<AppException>()));
    });

    test('disabled account rejects new transactions', () async {
      final e = await Env.create();
      final a = await e.acc('A', 'YER', '0');
      await e.accounts.setActive(e.uid, a.id, false);
      expect(() => e.txns.record(e.uid, TxnDraft(type: TxnType.income, accountId: a.id, amount: d('1'), currency: 'YER', categoryId: null, txnDate: DateTime.now(), idempotencyKey: 'z')),
          throwsA(isA<AppException>()));
    });

    test('base currency change re-bases every txn, refuses atomically when a rate is missing', () async {
      final e = await Env.create(base: 'YER');
      final a = await e.acc('A', 'YER', '0');
      await e.txns.record(e.uid, TxnDraft(type: TxnType.income, accountId: a.id, amount: d('5300'), currency: 'YER', categoryId: await e.cat('salary'), txnDate: DateTime(2026, 2, 1), idempotencyKey: 'i'));
      await expectLater(e.fx.changeBaseCurrency(e.uid, 'USD'), throwsA(isA<MissingRateException>()));
      expect((await e.auth.getUser(e.uid))!.baseCurrency, 'YER');
      await e.fx.addRate(e.uid, from: 'USD', to: 'YER', rate: d('530'), source: 'x', date: DateTime(2026, 1, 1));
      await e.fx.changeBaseCurrency(e.uid, 'USD');
      final t = (await e.txns.query(e.uid, const TxnQuery())).single;
      expect(t.baseCurrency, 'USD');
      expect(t.baseAmount, d('10'));
    });
  });

  group('Budgets', () {
    test('percent used, remaining, near/exceeded flags', () async {
      final e = await Env.create();
      final a = await e.acc('A', 'YER', '100000');
      final food = await e.cat('food');
      await e.budgets.saveBudget(e.uid, name: 'Food', categoryId: food, period: BudgetPeriod.monthly, limit: d('10000'));
      Future<void> spend(String amt, String k) => e.txns.record(e.uid, TxnDraft(type: TxnType.expense, accountId: a.id, amount: d(amt), currency: 'YER', categoryId: food, txnDate: DateTime.now(), idempotencyKey: k));
      await spend('8500', '1');
      var s = (await e.budgets.statuses(e.uid, DateTime.now())).single;
      expect(s.percent, d('85'));
      expect(s.remaining, d('1500'));
      expect(s.nearLimit, isTrue);
      await spend('2000', '2');
      s = (await e.budgets.statuses(e.uid, DateTime.now())).single;
      expect(s.exceeded, isTrue);
      expect(s.remaining, d('-500'));
    });
  });

  group('Debts', () {
    test('interest, schedule, payments, settle, void reopens', () async {
      final e = await Env.create();
      final a = await e.acc('A', 'YER', '0');
      final debt = await e.debts.createDebt(e.uid, direction: DebtDirection.iOwe, party: 'Ali', principal: d('120000'), currency: 'YER',
          interestRate: d('10'), startDate: DateTime(2026, 1, 1), dueDate: DateTime(2027, 1, 1), installments: 12, accountId: a.id, moveMoney: true, idempotencyKey: 'debt1');
      expect(await e.balance(a.id), d('120000')); // borrowed money arrived
      var s = (await e.debts.debt(e.uid, debt.id))!;
      expect(s.interest, d('12000'));
      expect(s.totalPayable, d('132000'));
      expect(s.schedule.length, 12);
      expect(Money.sum(s.schedule.map((i) => i.amount)), d('132000'));
      final p = await e.debts.addPayment(e.uid, debt.id, accountId: a.id, amount: d('11000'), date: DateTime(2026, 2, 1), idempotencyKey: 'p1');
      s = (await e.debts.debt(e.uid, debt.id))!;
      expect(s.remaining, d('121000'));
      expect(s.schedule.first.paid, isTrue);
      expect(() => e.debts.addPayment(e.uid, debt.id, accountId: a.id, amount: d('999999'), date: DateTime.now(), idempotencyKey: 'p2'), throwsA(isA<AppException>()));
      await e.debts.addPayment(e.uid, debt.id, accountId: a.id, amount: d('121000'), date: DateTime(2026, 3, 1), idempotencyKey: 'p3');
      expect((await e.debts.debt(e.uid, debt.id))!.debt.status, DebtStatus.settled);
      // loans and repayments are not income/expense
      final all = await e.txns.query(e.uid, const TxnQuery());
      expect(FinanceMath.sumBase(all, TxnType.expense), Decimal.zero);
      await e.txns.voidTxn(e.uid, p.id);
      final after = (await e.debts.debt(e.uid, debt.id))!;
      expect(after.debt.status, DebtStatus.open);
      expect(after.remaining, d('11000'));
    });
  });

  group('Savings goals', () {
    test('deposit from account, withdraw back, reached flag', () async {
      final e = await Env.create();
      final a = await e.acc('A', 'YER', '50000');
      final g = await e.goals.saveGoal(e.uid, name: 'Car', target: d('30000'), currency: 'YER', deadline: DateTime.now().add(const Duration(days: 300)));
      expect(await e.goals.move(e.uid, g.id, deposit: true, accountId: a.id, amount: d('20000'), date: DateTime.now(), idempotencyKey: 'g1'), isFalse);
      expect(await e.goals.move(e.uid, g.id, deposit: true, accountId: a.id, amount: d('10000'), date: DateTime.now(), idempotencyKey: 'g2'), isTrue);
      expect(await e.balance(a.id), d('20000'));
      var s = (await e.goals.goal(e.uid, g.id))!;
      expect(s.percent, d('100'));
      expect(() => e.goals.move(e.uid, g.id, deposit: false, accountId: a.id, amount: d('40000'), date: DateTime.now(), idempotencyKey: 'g3'), throwsA(isA<AppException>()));
      await e.goals.move(e.uid, g.id, deposit: false, accountId: a.id, amount: d('5000'), date: DateTime.now(), idempotencyKey: 'g4');
      s = (await e.goals.goal(e.uid, g.id))!;
      expect(s.current, d('25000'));
      expect(await e.balance(a.id), d('25000'));
    });
  });

  group('Bills', () {
    test('paying advances the due date; voiding the payment re-opens the cycle', () async {
      final e = await Env.create();
      final a = await e.acc('A', 'YER', '50000');
      final b = await e.bills.saveBill(e.uid, name: 'Electricity', kind: BillKind.electricity, amount: d('7000'), currency: 'YER', dueDate: DateTime(2026, 3, 10));
      final t = await e.bills.payBill(e.uid, b.id, accountId: a.id, date: DateTime(2026, 3, 9), idempotencyKey: 'b1');
      var bill = (await e.bills.bills(e.uid)).single;
      expect(bill.dueDate, DateTime(2026, 4, 10));
      expect(await e.balance(a.id), d('43000'));
      expect((await e.bills.payments(e.uid, b.id)).single.txnId, t.id);
      await e.txns.voidTxn(e.uid, t.id);
      bill = (await e.bills.bills(e.uid)).single;
      expect(bill.dueDate, DateTime(2026, 3, 10));
      expect(await e.balance(a.id), d('50000'));
    });
  });

  group('Recurring', () {
    test('posts each due occurrence once, even when processed twice', () async {
      final e = await Env.create();
      final a = await e.acc('A', 'YER', '0');
      final now = DateTime.now();
      await e.txns.saveRecurring(e.uid,
          template: TxnDraft(type: TxnType.income, accountId: a.id, amount: d('100'), currency: 'YER', categoryId: await e.cat('salary'), txnDate: now, idempotencyKey: 'tpl'),
          frequency: Frequency.monthly, firstDate: addMonths(now, -2));
      final r1 = await e.txns.processDue(e.uid, now);
      final r2 = await e.txns.processDue(e.uid, now);
      expect(r1.created, 3);
      expect(r2.created, 0);
      expect(await e.balance(a.id), d('300'));
    });
  });

  group('Holdings', () {
    test('asset value history and investment ROI', () async {
      final e = await Env.create();
      final asset = await e.assets.saveAsset(e.uid, name: 'Gold', type: AssetType.gold, purchaseValue: d('1000'), currentValue: d('1000'), currency: 'USD');
      await e.assets.addValue(e.uid, asset.id, d('1250'), DateTime.now());
      expect((await e.assets.history(e.uid, asset.id)).length, 2);
      expect((await e.assets.assets(e.uid)).single.changePercent, d('25'));
      final inv = await e.investments.saveInvestment(e.uid, name: 'Fund', type: InvestmentType.funds, currency: 'USD', startDate: DateTime(2026, 1, 1), capital: d('2000'));
      await e.investments.addEntry(e.uid, inv.id, InvestmentEntryKind.valuation, d('2300'), DateTime.now());
      await e.investments.addEntry(e.uid, inv.id, InvestmentEntryKind.dividend, d('100'), DateTime.now());
      final p = (await e.investments.investments(e.uid)).single;
      expect(p.profitLoss, d('400'));
      expect(p.roi, d('20'));
    });
  });

  group('Backup', () {
    test('export -> restore round-trips into a different user', () async {
      final e = await Env.create();
      final a = await e.acc('A', 'YER', '1000');
      await e.txns.record(e.uid, TxnDraft(type: TxnType.expense, accountId: a.id, amount: d('250'), currency: 'YER', categoryId: await e.cat('food'), txnDate: DateTime.now(), idempotencyKey: 'x'));
      final json = await e.backup.export(e.uid);
      final other = await e.auth.signUp(name: 'Other', email: 'o@b.co', password: 'secret1', baseCurrency: 'YER');
      await e.backup.restore(other.user.id, json);
      final accs = await e.accounts.accounts(other.user.id);
      expect(accs.single.balance, d('750'));
      expect((await e.txns.query(other.user.id, const TxnQuery())).length, 1);
    });
  });

  group('Analytics', () {
    test('unusual = above mean + 2σ within its category', () {
      final now = DateTime.now();
      FinTransaction t(String amt, int i) => FinTransaction(id: '$i', userId: 'u', type: TxnType.expense, categoryId: 'food', amount: d(amt), currency: 'YER',
          fee: Decimal.zero, baseAmount: d(amt), baseCurrency: 'YER', txnDate: now, createdAt: now, updatedAt: now, idempotencyKey: '$i');
      final list = [for (var i = 0; i < 10; i++) t('1000', i), t('9000', 99)];
      final u = FinanceMath.unusualExpenses(list);
      expect(u.single.id, '99');
      expect(FinanceMath.sqrt(d('16')), d('4'));
    });
    test('budget suggestion = average of the last 3 full months', () {
      final now = DateTime(2026, 5, 15);
      FinTransaction t(String amt, DateTime when, String id) => FinTransaction(id: id, userId: 'u', type: TxnType.expense, categoryId: 'food', amount: d(amt), currency: 'YER',
          fee: Decimal.zero, baseAmount: d(amt), baseCurrency: 'YER', txnDate: when, createdAt: when, updatedAt: when, idempotencyKey: id);
      final s = FinanceMath.budgetSuggestions([t('3000', DateTime(2026, 2, 3), 'a'), t('6000', DateTime(2026, 4, 3), 'b'), t('100', DateTime(2026, 5, 3), 'c'), t('900', DateTime(2026, 1, 3), 'd')], now);
      expect(s['food'], d('3000'));
    });
  });
}
