import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../entities/planning.dart';
import '../entities/transaction.dart';
import '../services/finance_math.dart';
import '../services/snapshot.dart';
import 'assistant_engine.dart';
import 'quick_add_parser.dart';
import 'text_norm.dart';

/// Arabic/English rule-based financial assistant over the user's REAL data.
/// Every number it says comes from the snapshot (base currency, manual rates).
class RuleBasedAssistant implements AssistantEngine {
  @override
  Future<AssistantReply> respond(String message, AssistantContext ctx) async {
    final n = TextNorm.normalize(message);
    final s = ctx.snapshot;
    final ar = ctx.ar;
    String t(String a, String e) => ar ? a : e;
    String money(Decimal d) => Money.format(d, currency: s.base);
    bool has(List<String> ws) => ws.any((w) => n.contains(w));

    // 1) quick add has priority: «صرفت 5000 ريال يمني غداء»
    if (!has(['كم', 'how much', 'how many'])) {
      final draft = QuickAddParser.parse(message, now: s.now);
      if (draft != null) {
        final kind = draft.type == TxnType.expense ? t('مصروف', 'expense') : t('دخل', 'income');
        return AssistantReply(
            t('فهمت: $kind بقيمة ${Money.format(draft.amount, currency: draft.currency)}${draft.title.isEmpty ? '' : ' — ${draft.title}'}. راجعها واضغط تأكيد للحفظ.',
                'Got it: $kind of ${Money.format(draft.amount, currency: draft.currency)}${draft.title.isEmpty ? '' : ' — ${draft.title}'}. Review and tap confirm to save.'),
            draft: draft);
      }
    }

    final month = DateRange.of(PeriodKind.monthly, s.now);
    DateRange period = month;
    var periodLabel = t('هذا الشهر', 'this month');
    if (has(['اليوم', 'today'])) {
      period = DateRange.of(PeriodKind.daily, s.now);
      periodLabel = t('اليوم', 'today');
    } else if (has(['الاسبوع', 'week'])) {
      period = DateRange.of(PeriodKind.weekly, s.now);
      periodLabel = t('هذا الأسبوع', 'this week');
    } else if (has(['الشهر الماضي', 'last month', 'الشهر السابق'])) {
      period = month.previous(PeriodKind.monthly);
      periodLabel = t('الشهر الماضي', 'last month');
    } else if (has(['السنه', 'هذا العام', 'this year', 'year'])) {
      period = DateRange.of(PeriodKind.yearly, s.now);
      periodLabel = t('هذه السنة', 'this year');
    }

    String missingNote(BaseTotal b) => b.complete ? '' : t('\n⚠️ لم أحتسب أرصدة بعملات بدون سعر صرف: ${b.missing.join('، ')}. أضف السعر من «العملات».',
        '\n⚠️ Not counted (no exchange rate entered): ${b.missing.join(', ')}. Add a rate in Currencies.');

    // 2) top category
    if (has(['اكثر تصنيف', 'اكثر شي', 'اكثر بند', 'top category', 'most on', 'spend most', 'biggest category'])) {
      final cats = FinanceMath.byCategory(s.txns, period);
      if (cats.isEmpty) return AssistantReply(t('لا توجد مصروفات $periodLabel بعد.', 'No expenses $periodLabel yet.'));
      final total = Money.sum(cats.map((e) => e.value));
      final lines = cats.take(3).map((e) => '• ${ctx.categoryName(s.categories[e.key])}: ${money(e.value)} (${Money.percent(e.value, total)}%)').join('\n');
      return AssistantReply(t('أكثر تصنيف تنفق عليه $periodLabel هو «${ctx.categoryName(s.categories[cats.first.key])}».\n$lines',
          'Your top spending category $periodLabel is "${ctx.categoryName(s.categories[cats.first.key])}".\n$lines'));
    }

    // 3) spending
    if (has(['كم صرفت', 'مصروفاتي', 'مصاريفي', 'how much did i spend', 'my spending', 'spent this', 'expenses this'])) {
      final exp = FinanceMath.sumBase(s.txns, TxnType.expense, range: period);
      final prev = FinanceMath.sumBase(s.txns, TxnType.expense, range: period.previous(PeriodKind.monthly));
      final cmp = prev.sign == 0 ? '' : t('\nالشهر الماضي: ${money(prev)} (${Money.percent(exp - prev, prev)}%).', '\nLast month: ${money(prev)} (${Money.percent(exp - prev, prev)}%).');
      return AssistantReply(t('صرفت $periodLabel ${money(exp)} (التحويلات بين حساباتك غير محسوبة).${period == month ? cmp : ''}',
          'You spent ${money(exp)} $periodLabel (transfers between your accounts excluded).${period == month ? cmp : ''}'));
    }

    if (has(['كم دخلي', 'كم كسبت', 'دخلي', 'my income', 'how much did i earn', 'income this'])) {
      final inc = FinanceMath.sumBase(s.txns, TxnType.income, range: period);
      return AssistantReply(t('دخلك $periodLabel: ${money(inc)}.', 'Your income $periodLabel: ${money(inc)}.'));
    }

    // 4) holdings
    if (has(['كم املك', 'كم عندي', 'جميع حساباتي', 'كل حساباتي', 'رصيدي', 'how much do i have', 'total balance', 'all my accounts', 'my balance'])) {
      final total = s.accountsTotal();
      final lines = s.activeAccounts.map((a) => '• ${a.item.name}: ${Money.format(a.amount, currency: a.currency)}').join('\n');
      return AssistantReply(t('مجموع أرصدة حساباتك النشطة: ${money(total.total)}\n$lines${missingNote(total)}',
          'Total across your active accounts: ${money(total.total)}\n$lines${missingNote(total)}'));
    }

    if (has(['صافي الثروه', 'صافي ثروتي', 'net worth'])) {
      final st = DashboardStats.compute(s, month);
      return AssistantReply(t('صافي ثروتك: ${money(st.netWorth.total)} = الأصول ${money(st.totalAssets.total)} + المستحق لك ${money(st.owedToMe.total)} − ديونك ${money(st.iOwe.total)}.${missingNote(st.netWorth)}',
          'Net worth: ${money(st.netWorth.total)} = assets ${money(st.totalAssets.total)} + owed to you ${money(st.owedToMe.total)} − your debts ${money(st.iOwe.total)}.${missingNote(st.netWorth)}'));
    }

    // 5) savings goal
    if (has(['ادخار', 'هدفي', 'اهدافي', 'احتاج', 'goal', 'save for', 'saving'])) {
      final open = s.goals.where((g) => !g.item.reached).toList();
      if (open.isEmpty) return AssistantReply(t('لا توجد أهداف ادخار مفتوحة. أضف هدفاً من «المدخرات».', 'No open savings goals. Add one under Savings.'));
      final lines = open.map((g) {
        final st = g.item;
        final monthly = st.monthlyNeeded(s.now);
        final per = monthly == null ? t('بدون موعد نهائي', 'no deadline') : t('ادخر ${Money.format(monthly, currency: st.goal.currency)} شهرياً', 'save ${Money.format(monthly, currency: st.goal.currency)} / month');
        return '• ${st.goal.name}: ${t('متبقي', 'remaining')} ${Money.format(st.remaining, currency: st.goal.currency)} (${st.percent}%) — $per';
      }).join('\n');
      return AssistantReply(t('لتحقيق أهدافك:\n$lines', 'To reach your goals:\n$lines'));
    }

    // 6) debts due soon
    if (has(['دين', 'ديون', 'ديوني', 'قرض', 'سداد', 'debt', 'loan', 'owe'])) {
      final soon = s.debts.where((d) => d.item.debt.direction == DebtDirection.iOwe && d.item.remaining.sign > 0).toList()
        ..sort((a, b) => (a.item.nextInstallment?.dueDate ?? DateTime(9999)).compareTo(b.item.nextInstallment?.dueDate ?? DateTime(9999)));
      if (soon.isEmpty) return AssistantReply(t('ليس عليك ديون مفتوحة 👍', 'You have no open debts 👍'));
      final lines = soon.take(5).map((d) {
        final next = d.item.nextInstallment;
        final when = next == null ? '' : ' — ${t('القسط القادم', 'next')} ${Money.format(next.amount, currency: d.currency)} ${t('في', 'on')} ${isoDay(next.dueDate)}${d.item.overdue ? t(' (متأخر!)', ' (overdue!)') : ''}';
        return '• ${d.item.debt.party}: ${t('متبقي', 'remaining')} ${Money.format(d.amount, currency: d.currency)}$when';
      }).join('\n');
      return AssistantReply(t('الديون التي يجب سدادها قريباً:\n$lines', 'Debts to pay soon:\n$lines'));
    }

    if (has(['فاتوره', 'فواتير', 'bill'])) {
      final due = s.bills.where((b) => b.active && (b.isOverdue(s.now) || b.dueDate.difference(dayOnly(s.now)).inDays <= 14)).toList();
      if (due.isEmpty) return AssistantReply(t('لا توجد فواتير مستحقة خلال أسبوعين.', 'No bills due in the next two weeks.'));
      return AssistantReply(due.map((b) => '• ${b.name}: ${Money.format(b.amount, currency: b.currency)} — ${isoDay(b.dueDate)}${b.isOverdue(s.now) ? t(' (متأخرة)', ' (overdue)') : ''}').join('\n'));
    }

    // 7) unusual / high spending
    if (has(['غير معتاد', 'غريب', 'مرتفع', 'كبيره', 'unusual', 'high spending', 'anomal', 'large'])) return AssistantReply(_unusual(ctx));

    // 8) budget suggestions
    if (has(['اقترح ميزانيه', 'ميزانيه مناسبه', 'ميزانيات', 'suggest budget', 'budget suggestion', 'budget'])) return AssistantReply(_budgets(ctx));

    // 9) reduce spending
    if (has(['قلل', 'اوفر', 'وفر', 'تقليل', 'reduce', 'cut', 'save money'])) return AssistantReply(_reduce(ctx));

    // 10) summaries
    if (has(['ملخص', 'summary', 'تقرير شهري', 'monthly report', 'تقرير'])) {
      final daily = has(['يومي', 'اليوم', 'daily', 'today']);
      return AssistantReply(summary(ctx, daily ? DateRange.of(PeriodKind.daily, s.now) : month, daily: daily));
    }

    // 11) analysis
    if (has(['حلل', 'تحليل', 'وضعي', 'analy', 'situation', 'overview'])) {
      return AssistantReply('${summary(ctx, month)}\n\n${_unusual(ctx)}\n\n${_reduce(ctx)}');
    }

    return AssistantReply(
        t('أقدر أجاوبك من بياناتك الفعلية. جرّب:', 'I answer from your real data. Try:'),
        suggestions: ar
            ? const ['كم صرفت هذا الشهر؟', 'كم أملك في جميع حساباتي؟', 'ما أكثر تصنيف أنفق عليه؟', 'كم أحتاج للادخار لتحقيق هدفي؟', 'ما الديون التي يجب سدادها قريباً؟', 'حلل وضعي المالي', 'اقترح ميزانيات', 'صرفت 5000 ريال يمني غداء']
            : const ['How much did I spend this month?', 'How much do I have in all my accounts?', 'What is my top category?', 'How much do I need to save for my goal?', 'Which debts are due soon?', 'Analyze my situation', 'Suggest budgets', 'spent 20 USD taxi']);
  }

  String summary(AssistantContext ctx, DateRange r, {bool daily = false}) {
    final s = ctx.snapshot;
    String t(String a, String e) => ctx.ar ? a : e;
    final inc = FinanceMath.sumBase(s.txns, TxnType.income, range: r);
    final exp = FinanceMath.sumBase(s.txns, TxnType.expense, range: r);
    final count = s.txns.where((x) => r.contains(x.txnDate)).length;
    final cats = FinanceMath.byCategory(s.txns, r);
    final top = cats.isEmpty ? '' : t('\nأعلى تصنيف: ${ctx.categoryName(s.categories[cats.first.key])} (${Money.format(cats.first.value, currency: s.base)})',
        '\nTop category: ${ctx.categoryName(s.categories[cats.first.key])} (${Money.format(cats.first.value, currency: s.base)})');
    final over = s.budgets.where((b) => b.exceeded).map((b) => b.budget.name).toList();
    final budgets = over.isEmpty ? '' : t('\nميزانيات متجاوزة: ${over.join('، ')}', '\nBudgets exceeded: ${over.join(', ')}');
    final title = daily ? t('📅 ملخص اليوم', '📅 Daily summary') : t('📊 التقرير الشهري', '📊 Monthly report');
    return t('$title\nالعمليات: $count\nالدخل: ${Money.format(inc, currency: s.base)}\nالمصروفات: ${Money.format(exp, currency: s.base)}\nالصافي: ${Money.format(inc - exp, currency: s.base)}\nنسبة الادخار: ${FinanceMath.savingsRate(inc, exp)}%$top$budgets',
        '$title\nTransactions: $count\nIncome: ${Money.format(inc, currency: s.base)}\nExpenses: ${Money.format(exp, currency: s.base)}\nNet: ${Money.format(inc - exp, currency: s.base)}\nSavings rate: ${FinanceMath.savingsRate(inc, exp)}%$top$budgets');
  }

  String _unusual(AssistantContext ctx) {
    final s = ctx.snapshot;
    String t(String a, String e) => ctx.ar ? a : e;
    final recent = s.txns.where((x) => x.txnDate.isAfter(s.now.subtract(const Duration(days: 180)))).toList();
    final u = FinanceMath.unusualExpenses(recent);
    if (u.isEmpty) {
      return t('لم أجد مصروفات غير معتادة (أعلى من المتوسط + انحرافين معياريين لنفس التصنيف) خلال آخر ٦ أشهر.',
          'No unusual expenses (above mean + 2σ of their category) in the last 6 months.');
    }
    final lines = u.take(5).map((x) => '• ${x.title.isEmpty ? ctx.categoryName(s.categories[x.categoryId]) : x.title}: ${Money.format(x.baseAmount, currency: s.base)} (${isoDay(x.txnDate)})').join('\n');
    return t('⚠️ مصروفات غير معتادة (أعلى من المتوسط + 2σ لتصنيفها):\n$lines', '⚠️ Unusual expenses (above mean + 2σ of their category):\n$lines');
  }

  String _budgets(AssistantContext ctx) {
    final s = ctx.snapshot;
    String t(String a, String e) => ctx.ar ? a : e;
    final sug = FinanceMath.budgetSuggestions(s.txns, s.now);
    if (sug.isEmpty) return t('أحتاج بيانات مصروفات لآخر ٣ أشهر كاملة لاقتراح ميزانيات.', 'I need expenses from the last 3 full months to suggest budgets.');
    final sorted = sug.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final lines = sorted.map((e) => '• ${ctx.categoryName(s.categories[e.key])}: ${Money.format(e.value, currency: s.base)} ${t('شهرياً', '/ month')}').join('\n');
    return t('ميزانيات مقترحة (متوسط آخر ٣ أشهر كاملة):\n$lines', 'Suggested monthly budgets (average of the last 3 full months):\n$lines');
  }

  String _reduce(AssistantContext ctx) {
    final s = ctx.snapshot;
    String t(String a, String e) => ctx.ar ? a : e;
    final month = DateRange.of(PeriodKind.monthly, s.now);
    final cur = FinanceMath.byCategory(s.txns, month);
    final prevMap = {for (final e in FinanceMath.byCategory(s.txns, month.previous(PeriodKind.monthly))) e.key: e.value};
    final tips = <String>[];
    for (final e in cur.take(5)) {
      final p = prevMap[e.key];
      if (p != null && p.sign > 0 && e.value > p) {
        tips.add(t('• ${ctx.categoryName(s.categories[e.key])} زاد ${Money.percent(e.value - p, p)}% عن الشهر الماضي — حاول تثبيته عند ${Money.format(p, currency: s.base)}.',
            '• ${ctx.categoryName(s.categories[e.key])} is up ${Money.percent(e.value - p, p)}% vs last month — try capping it at ${Money.format(p, currency: s.base)}.'));
      }
    }
    if (cur.isNotEmpty) {
      final top = cur.first;
      final tenPct = Money.round(top.value * Decimal.parse('0.1'), 0);
      tips.add(t('• تقليل «${ctx.categoryName(s.categories[top.key])}» بنسبة ١٠٪ يوفر ${Money.format(tenPct, currency: s.base)} شهرياً.',
          '• Cutting "${ctx.categoryName(s.categories[top.key])}" by 10% saves ${Money.format(tenPct, currency: s.base)} a month.'));
    }
    for (final b in s.budgets.where((b) => b.exceeded || b.nearLimit)) {
      tips.add(t('• ميزانية «${b.budget.name}» عند ${b.percent}%.', '• Budget "${b.budget.name}" is at ${b.percent}%.'));
    }
    if (tips.isEmpty) return t('لا توجد بيانات كافية هذا الشهر لاقتراحات التوفير.', 'Not enough data this month for saving tips.');
    return t('💡 اقتراحات لتقليل الإنفاق:\n${tips.join('\n')}', '💡 Ways to spend less:\n${tips.join('\n')}');
  }
}
