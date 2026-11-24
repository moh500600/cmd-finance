import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/entities/account.dart';
import '../../../domain/entities/planning.dart';
import '../../../domain/services/finance_math.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/visuals.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final cats = {for (final c in ref.watch(categoriesProvider).value ?? const <Category>[]) c.id: c};
    final base = ref.watch(sessionProvider)?.baseCurrency ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('menu_budgets'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _form(context, ref), icon: const Icon(Icons.add), label: Text(l.tr('add_budget'))),
      body: AsyncBody(ref.watch(budgetStatusProvider), (list) {
        final snap = ref.watch(snapshotProvider).value;
        final sug = snap == null ? const <String?, dynamic>{} : FinanceMath.budgetSuggestions(snap.txns, DateTime.now());
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          if (list.isEmpty) EmptyState(Icons.pie_chart_rounded, l.tr('no_budgets')),
          for (final b in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => _form(context, ref, existing: b.budget),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        IconBadge(b.budget.categoryId == null ? Icons.all_inclusive_rounded : categoryIcon(cats[b.budget.categoryId]),
                            b.exceeded ? AppColors.expense : b.nearLimit ? AppColors.warning : AppColors.income),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(b.budget.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                            Text('${l.tr(b.budget.period.name)} · ${b.budget.categoryId == null ? l.tr('all_categories') : l.category(cats[b.budget.categoryId])}',
                                style: const TextStyle(fontSize: 12)),
                          ]),
                        ),
                        Text('${b.percent}%', style: TextStyle(fontWeight: FontWeight.w800, color: b.exceeded ? AppColors.expense : null), textDirection: TextDirection.ltr),
                      ]),
                      const SizedBox(height: 10),
                      PercentBar(b.percent),
                      const SizedBox(height: 8),
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(child: _cell(l.tr('spent'), MoneyText(b.spent, currency: b.budget.currency, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))),
                        Expanded(child: _cell(l.tr('limit'), MoneyText(b.budget.limit, currency: b.budget.currency, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))),
                        Expanded(
                            child: _cell(l.tr('remaining'),
                                MoneyText(b.remaining, currency: b.budget.currency, colored: true, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))),
                      ]),
                      const SizedBox(height: 4),
                      Text('${isoDay(b.range.start)} → ${isoDay(b.range.end.subtract(const Duration(days: 1)))}', style: const TextStyle(fontSize: 11), textDirection: TextDirection.ltr),
                      if (b.exceeded || b.nearLimit)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: InfoBanner(b.exceeded ? Icons.error_rounded : Icons.warning_rounded,
                              l.tr(b.exceeded ? 'alert_budget_exceeded' : 'alert_budget_near', {'name': b.budget.name, 'pct': '${b.percent}'}),
                              color: b.exceeded ? AppColors.expense : AppColors.warning),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
          if (sug.isNotEmpty) ...[
            SectionTitle(l.tr('suggested_budgets')),
            Card(
              child: Column(children: [
                for (final e in sug.entries)
                  ListTile(
                    dense: true,
                    leading: Icon(categoryIcon(cats[e.key])),
                    title: Text(l.category(cats[e.key])),
                    subtitle: Text(l.tr('avg_3_months')),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      MoneyText(e.value, currency: base, style: const TextStyle(fontWeight: FontWeight.w700)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: () => guard(context, () => ref.read(actionsProvider).run((u) => ref.read(budgetRepositoryProvider)
                            .saveBudget(u, name: l.category(cats[e.key]), categoryId: e.key, period: BudgetPeriod.monthly, limit: e.value)), success: l.tr('saved')),
                      ),
                    ]),
                  ),
              ]),
            ),
          ],
        ]);
      }),
    );
  }

  static Widget _cell(String k, Widget v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: const TextStyle(fontSize: 11)),
        FittedBox(fit: BoxFit.scaleDown, alignment: AlignmentDirectional.centerStart, child: v),
      ]);

  void _form(BuildContext context, WidgetRef ref, {Budget? existing}) {
    final l = context.l;
    final name = TextEditingController(text: existing?.name ?? '');
    final limit = TextEditingController(text: existing?.limit.toString() ?? '');
    final alert = TextEditingController(text: '${existing?.alertPercent ?? 80}');
    String? cat = existing?.categoryId;
    var period = existing?.period ?? BudgetPeriod.monthly;
    final formKey = GlobalKey<FormState>();
    final base = ref.read(sessionProvider)!.baseCurrency;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SheetFrame(
          title: l.tr(existing == null ? 'add_budget' : 'edit_budget'),
          child: Form(
            key: formKey,
            child: Column(children: [
              TextFormField(controller: name, decoration: InputDecoration(labelText: l.tr('name')), validator: (v) => (v ?? '').trim().isEmpty ? l.tr('required') : null),
              const SizedBox(height: 10),
              CategoryField(value: cat, allowNone: true, categories: (ref.read(categoriesProvider).value ?? const <Category>[]).where((x) => x.kind == CategoryKind.expense).toList(),
                  onChanged: (v) => set(() => cat = v)),
              const SizedBox(height: 10),
              SegmentedButton<BudgetPeriod>(
                segments: [for (final p in BudgetPeriod.values) ButtonSegment(value: p, label: Text(l.tr(p.name)))],
                selected: {period},
                onSelectionChanged: (s) => set(() => period = s.first),
              ),
              const SizedBox(height: 10),
              AmountField(controller: limit, label: l.tr('limit'), suffix: base),
              const SizedBox(height: 10),
              TextFormField(controller: alert, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.tr('alert_at_percent'), suffixText: '%'),
                  validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 || (int.tryParse(v ?? '') ?? 0) > 100 ? l.tr('err_alert_percent') : null),
              const SizedBox(height: 16),
              Row(children: [
                if (existing != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppColors.expense),
                    onPressed: () async {
                      Navigator.pop(c);
                      await guard(context, () => ref.read(actionsProvider).run((u) => ref.read(budgetRepositoryProvider).deleteBudget(u, existing.id)));
                    },
                  ),
                Expanded(
                  child: FilledButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final ok = await guard(c, () => ref.read(actionsProvider).run((u) => ref.read(budgetRepositoryProvider).saveBudget(u,
                          id: existing?.id, name: name.text, categoryId: cat, period: period, limit: Money.parse(limit.text), alertPercent: int.parse(alert.text))));
                      if (ok != null && c.mounted) Navigator.pop(c);
                    },
                    child: Text(l.tr('save')),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
