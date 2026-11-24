import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/entities/currency.dart';
import '../../../domain/entities/holdings.dart';
import '../../providers/providers.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';

/// Tracking only — the app never executes trades.
class InvestmentsScreen extends ConsumerWidget {
  const InvestmentsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('menu_investments'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => showInvestmentForm(context, ref), icon: const Icon(Icons.add), label: Text(l.tr('add_investment'))),
      body: AsyncBody(ref.watch(investmentsProvider), (list) {
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          InfoBanner(Icons.info_outline_rounded, l.tr('tracking_only_note'), color: AppColors.transfer),
          if (list.isEmpty) EmptyState(Icons.trending_up_rounded, l.tr('no_investments')),
          if (list.length > 1) ...[
            const SizedBox(height: 12),
            ChartCard(title: l.tr('performance_comparison'), child: SignedBars(labels: [for (final i in list) i.investment.name.length > 6 ? i.investment.name.substring(0, 6) : i.investment.name], values: [for (final i in list) i.roi])),
          ],
          const SizedBox(height: 10),
          for (final i in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InvestmentDetailScreen(id: i.investment.id))),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        IconBadge(Icons.trending_up_rounded, i.profitLoss.sign < 0 ? AppColors.expense : AppColors.income),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(i.investment.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                          Text(l.tr('inv_${i.investment.type.name}'), style: const TextStyle(fontSize: 12)),
                        ])),
                        Text('ROI ${i.roi}%', style: TextStyle(fontWeight: FontWeight.w800, color: i.roi.sign < 0 ? AppColors.expense : AppColors.income), textDirection: TextDirection.ltr),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: _col(l.tr('capital'), MoneyText(i.capital, currency: i.investment.currency))),
                        Expanded(child: _col(l.tr('current_value'), MoneyText(i.investment.currentValue, currency: i.investment.currency))),
                        Expanded(child: _col(l.tr('profit_loss'), MoneyText(i.profitLoss, currency: i.investment.currency, colored: true, signed: true))),
                      ]),
                    ]),
                  ),
                ),
              ),
            ),
        ]);
      }),
    );
  }

  static Widget _col(String k, Widget v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(k, style: const TextStyle(fontSize: 11)), v]);
}

void showInvestmentForm(BuildContext context, WidgetRef ref, {Investment? existing, String? capital}) {
  final l = context.l;
  final name = TextEditingController(text: existing?.name ?? '');
  final cap = TextEditingController(text: capital ?? '');
  final current = TextEditingController(text: existing?.currentValue.toString() ?? '');
  final notes = TextEditingController(text: existing?.notes ?? '');
  var type = existing?.type ?? InvestmentType.stocks;
  String? currency = existing?.currency ?? ref.read(sessionProvider)!.baseCurrency;
  var start = existing?.startDate ?? DateTime.now();
  final form = GlobalKey<FormState>();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SheetFrame(
        title: l.tr(existing == null ? 'add_investment' : 'edit_investment'),
        child: Form(
          key: form,
          child: Column(children: [
            TextFormField(controller: name, decoration: InputDecoration(labelText: l.tr('name')), validator: (v) => (v ?? '').trim().isEmpty ? l.tr('required') : null),
            const SizedBox(height: 10),
            DropdownButtonFormField<InvestmentType>(
              initialValue: type,
              decoration: InputDecoration(labelText: l.tr('investment_type')),
              items: [for (final t in InvestmentType.values) DropdownMenuItem(value: t, child: Text(l.tr('inv_${t.name}')))],
              onChanged: (v) => set(() => type = v!),
            ),
            const SizedBox(height: 10),
            CurrencyField(value: currency, currencies: ref.read(currenciesProvider).value ?? const <Currency>[], label: l.tr('currency'), enabled: existing == null, onChanged: (v) => set(() => currency = v)),
            const SizedBox(height: 10),
            if (existing == null) ...[AmountField(controller: cap, label: l.tr('capital')), const SizedBox(height: 10)],
            AmountField(controller: current, label: l.tr('current_value_optional'), required: false, allowZero: true),
            const SizedBox(height: 10),
            DateField(label: l.tr('investment_date'), value: start, onChanged: (d) => set(() => start = d)),
            const SizedBox(height: 10),
            TextFormField(controller: notes, decoration: InputDecoration(labelText: l.tr('notes'))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (!form.currentState!.validate() || currency == null) return;
                final ok = await guard(c, () => ref.read(actionsProvider).run((u) => ref.read(investmentRepositoryProvider).saveInvestment(u, id: existing?.id, name: name.text, type: type,
                    currency: currency!, startDate: start, capital: existing != null ? Money.parse('1') : Money.parse(cap.text), currentValue: Money.tryParse(current.text) ?? existing?.currentValue, notes: notes.text)));
                if (ok != null && c.mounted) Navigator.pop(c);
              },
              child: Text(l.tr('save')),
            ),
          ]),
        ),
      ),
    ),
  );
}

class InvestmentDetailScreen extends ConsumerWidget {
  final String id;
  const InvestmentDetailScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final p = (ref.watch(investmentsProvider).value ?? const <InvestmentPerformance>[]).where((x) => x.investment.id == id).firstOrNull;
    if (p == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final c = p.investment.currency;
    return Scaffold(
      appBar: AppBar(title: Text(p.investment.name), actions: [
        IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => showInvestmentForm(context, ref, existing: p.investment)),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            if (!await confirm(context, l.tr('delete'), l.tr('delete_investment_note'), danger: true) || !context.mounted) return;
            final ok = await guard(context, () => ref.read(actionsProvider).run((u) => ref.read(investmentRepositoryProvider).deleteInvestment(u, id)).then((_) => true));
            if (ok == true && context.mounted) Navigator.pop(context);
          },
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(icon: const Icon(Icons.add), label: Text(l.tr('add_entry')), onPressed: () => _entry(context, ref, p)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _kv(context, l.tr('capital'), Money.format(p.capital, currency: c)),
              _kv(context, l.tr('withdrawals'), Money.format(p.withdrawals, currency: c)),
              _kv(context, l.tr('dividends'), Money.format(p.dividends, currency: c)),
              _kv(context, l.tr('current_value'), Money.format(p.investment.currentValue, currency: c)),
              const Divider(),
              _kv(context, l.tr('profit_loss'), Money.format(p.profitLoss, currency: c, showSign: true)),
              _kv(context, 'ROI', '${p.roi}%'),
              _kv(context, l.tr('investment_date'), isoDay(p.investment.startDate)),
            ]),
          ),
        ),
        SectionTitle(l.tr('operations_log')),
        Card(
          child: Column(children: [
            for (final e in p.entries.reversed)
              ListTile(
                dense: true,
                leading: Icon(switch (e.kind) {
                  InvestmentEntryKind.contribution => Icons.add_circle_outline,
                  InvestmentEntryKind.withdrawal => Icons.remove_circle_outline,
                  InvestmentEntryKind.dividend => Icons.paid_outlined,
                  InvestmentEntryKind.valuation => Icons.price_change_outlined,
                }),
                title: Text(l.tr('entry_${e.kind.name}')),
                subtitle: Text('${isoDay(e.date)} ${e.note}'),
                trailing: MoneyText(e.amount, currency: c, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _kv(BuildContext c, String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(k, style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant))), Text(v, style: const TextStyle(fontWeight: FontWeight.w700), textDirection: TextDirection.ltr)]));

  void _entry(BuildContext context, WidgetRef ref, InvestmentPerformance p) {
    final l = context.l;
    final amount = TextEditingController();
    final note = TextEditingController();
    var kind = InvestmentEntryKind.valuation;
    var date = DateTime.now();
    final form = GlobalKey<FormState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SheetFrame(
          title: l.tr('add_entry'),
          child: Form(
            key: form,
            child: Column(children: [
              DropdownButtonFormField<InvestmentEntryKind>(
                initialValue: kind,
                decoration: InputDecoration(labelText: l.tr('type')),
                items: [for (final k in InvestmentEntryKind.values) DropdownMenuItem(value: k, child: Text(l.tr('entry_${k.name}')))],
                onChanged: (v) => set(() => kind = v!),
              ),
              const SizedBox(height: 10),
              AmountField(controller: amount, label: l.tr(kind == InvestmentEntryKind.valuation ? 'new_value' : 'amount'), suffix: p.investment.currency,
                  allowZero: kind == InvestmentEntryKind.valuation),
              const SizedBox(height: 10),
              DateField(label: l.tr('date'), value: date, onChanged: (d) => set(() => date = d)),
              const SizedBox(height: 10),
              TextFormField(controller: note, decoration: InputDecoration(labelText: l.tr('notes'))),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  final ok = await guard(c, () => ref.read(actionsProvider).run((u) => ref.read(investmentRepositoryProvider).addEntry(u, p.investment.id, kind, Money.parse(amount.text), date, note: note.text)).then((_) => true));
                  if (ok == true && c.mounted) Navigator.pop(c);
                },
                child: Text(l.tr('save')),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
