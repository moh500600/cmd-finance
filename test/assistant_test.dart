import 'package:decimal/decimal.dart';
import 'package:finance_pro/domain/assistant/assistant_engine.dart';
import 'package:finance_pro/domain/assistant/quick_add_parser.dart';
import 'package:finance_pro/domain/assistant/rule_based_assistant.dart';
import 'package:finance_pro/domain/entities/planning.dart';
import 'package:finance_pro/domain/entities/transaction.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  group('QuickAddParser', () {
    final now = DateTime(2026, 11, 2, 13);
    test('«صرفت 5000 ريال يمني غداء» -> YER food expense draft', () {
      final q = QuickAddParser.parse('صرفت 5000 ريال يمني غداء', now: now)!;
      expect(q.type, TxnType.expense);
      expect(q.amount, d('5000'));
      expect(q.currency, 'YER');
      expect(q.categoryKey, 'food');
      expect(q.title, 'غداء');
    });
    test('Arabic digits, thousands word, yesterday', () {
      final q = QuickAddParser.parse('دفعت ٣ الف ريال سعودي بنزين امس', now: now)!;
      expect(q.amount, d('3000'));
      expect(q.currency, 'SAR');
      expect(q.categoryKey, 'transport');
      expect(q.date.day, 1);
    });
    test('English income', () {
      final q = QuickAddParser.parse('received 1200 usd salary', now: now)!;
      expect(q.type, TxnType.income);
      expect(q.currency, 'USD');
      expect(q.categoryKey, 'salary');
    });
    test('questions are not drafts', () {
      expect(QuickAddParser.parse('كم صرفت هذا الشهر؟', now: now), isNull);
    });
  });

  group('RuleBasedAssistant over real data', () {
    late Env e;
    late AssistantContext ctx;
    final a = RuleBasedAssistant();
    setUp(() async {
      e = await Env.create(base: 'YER');
      final cash = await e.acc('نقدي', 'YER', '200000');
      final usd = await e.acc('USD wallet', 'USD', '100');
      final food = await e.cat('food'), transport = await e.cat('transport');
      final now = DateTime.now();
      await e.txns.record(e.uid, TxnDraft(type: TxnType.expense, accountId: cash.id, amount: d('30000'), currency: 'YER', categoryId: food, txnDate: now, idempotencyKey: '1'));
      await e.txns.record(e.uid, TxnDraft(type: TxnType.expense, accountId: cash.id, amount: d('12000'), currency: 'YER', categoryId: transport, txnDate: now, idempotencyKey: '2'));
      final b = await e.acc('Bank', 'YER', '0');
      await e.txns.transfer(e.uid, TransferDraft(fromAccountId: cash.id, toAccountId: b.id, amount: d('50000'), txnDate: now, idempotencyKey: '3'));
      await e.goals.saveGoal(e.uid, name: 'سيارة', target: d('1200000'), currency: 'YER', deadline: DateTime(now.year + 1, now.month, now.day));
      await e.debts.createDebt(e.uid, direction: DebtDirection.iOwe, party: 'أحمد', principal: d('90000'), currency: 'YER', startDate: now, dueDate: now.add(const Duration(days: 10)), idempotencyKey: 'd');
      expect(usd.currency, 'USD');
      final snap = await e.loader.load(e.uid);
      ctx = AssistantContext(snapshot: snap, ar: true, categoryName: (c) => c?.key ?? '?');
    });

    test('كم صرفت هذا الشهر؟ excludes transfers', () async {
      final r = await a.respond('كم صرفت هذا الشهر؟', ctx);
      expect(r.text, contains('42,000 YER'));
    });
    test('كم أملك في جميع حساباتي؟ flags the currency without a rate', () async {
      final r = await a.respond('كم أملك في جميع حساباتي؟', ctx);
      expect(r.text, contains('158,000 YER'));
      expect(r.text, contains('USD'));
      expect(r.text, contains('⚠️'));
    });
    test('ما أكثر تصنيف أنفق عليه؟', () async {
      final r = await a.respond('ما أكثر تصنيف أنفق عليه؟', ctx);
      expect(r.text, contains('food'));
    });
    test('كم أحتاج للادخار لتحقيق هدفي؟', () async {
      final r = await a.respond('كم أحتاج للادخار لتحقيق هدفي؟', ctx);
      expect(r.text, contains('سيارة'));
      expect(r.text, contains('100,000 YER')); // 1.2M over 12 months
    });
    test('ما الديون التي يجب سدادها قريباً؟', () async {
      final r = await a.respond('ما الديون التي يجب سدادها قريباً؟', ctx);
      expect(r.text, contains('أحمد'));
      expect(r.text, contains('90,000 YER'));
    });
    test('quick add returns a draft to confirm (nothing saved yet)', () async {
      final r = await a.respond('صرفت 5000 ريال يمني غداء', ctx);
      expect(r.draft, isNotNull);
      expect(r.draft!.amount, Decimal.fromInt(5000));
    });
    test('English + summaries + unknown -> suggestions', () async {
      final en = AssistantContext(snapshot: ctx.snapshot, ar: false, categoryName: ctx.categoryName);
      expect((await a.respond('How much did I spend this month?', en)).text, contains('42,000 YER'));
      expect((await a.respond('monthly report', en)).text, contains('Expenses: 42,000 YER'));
      expect((await a.respond('daily summary', en)).text, contains('Daily summary'));
      expect((await a.respond('hello', en)).suggestions, isNotEmpty);
    });
  });
}
