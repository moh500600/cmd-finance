import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/ids.dart';
import '../../../domain/entities/account.dart';
import '../../../domain/entities/currency.dart';
import '../../../domain/entities/planning.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/visuals.dart';

class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final now = DateTime.now();
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('menu_bills'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => showBillForm(context, ref), icon: const Icon(Icons.add), label: Text(l.tr('add_bill'))),
      body: AsyncBody(ref.watch(billsProvider), (list) {
        if (list.isEmpty) return EmptyState(Icons.receipt_long_rounded, l.tr('no_bills'));
        final overdue = list.where((b) => b.isOverdue(now)).toList();
        final upcoming = list.where((b) => b.active && !b.isOverdue(now)).toList();
        final done = list.where((b) => !b.active).toList();
        Widget section(String title, List<Bill> bills) => bills.isEmpty
            ? const SizedBox.shrink()
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SectionTitle(title),
                Card(child: Column(children: [for (final b in bills) _BillTile(b)])),
              ]);
        return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), children: [
          section(l.tr('overdue_bills'), overdue),
          section(l.tr('upcoming_bills'), upcoming),
          section(l.tr('finished_bills'), done),
        ]);
      }),
    );
  }
}

class _BillTile extends ConsumerWidget {
  final Bill b;
  const _BillTile(this.b);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final now = DateTime.now();
    final color = b.isOverdue(now) ? AppColors.expense : b.isDueSoon(now) ? AppColors.warning : AppColors.primary;
    final days = dayOnly(b.dueDate).difference(dayOnly(now)).inDays;
    return ListTile(
      leading: IconBadge(billIcon(b.kind), b.active ? color : Colors.grey),
      title: Text(b.name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(b.active
          ? '${isoDay(b.dueDate)} · ${days < 0 ? l.tr('days_late', {'n': '${-days}'}) : days == 0 ? l.tr('due_today') : l.tr('in_days', {'n': '$days'})} · ${l.tr('freq_${b.recurrence.name}')}'
          : l.tr('paid_closed')),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        MoneyText(b.amount, currency: b.currency, style: const TextStyle(fontWeight: FontWeight.w800)),
        if (b.active)
          SizedBox(
            height: 26,
            child: TextButton(style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)), onPressed: () => payBill(context, ref, b), child: Text(l.tr('pay'))),
          ),
      ]),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => BillDetailScreen(id: b.id))),
    );
  }
}

void payBill(BuildContext context, WidgetRef ref, Bill b) {
  final l = context.l;
  final amount = TextEditingController(text: b.amount.toString());
  String? accountId = b.accountId;
  var date = DateTime.now();
  final key = newIdempotencyKey();
  final form = GlobalKey<FormState>();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SheetFrame(
        title: '${l.tr('pay')}: ${b.name}',
        child: Form(
          key: form,
          child: Column(children: [
            AmountField(controller: amount, label: l.tr('amount'), suffix: b.currency),
            const SizedBox(height: 10),
            AccountField(value: accountId, accounts: ref.read(accountsProvider).value ?? const [], label: l.tr('paid_from'), onChanged: (v) => set(() => accountId = v)),
            const SizedBox(height: 10),
            DateField(label: l.tr('date'), value: date, onChanged: (v) => set(() => date = v)),
            const SizedBox(height: 6),
            Text(l.tr('pay_bill_note'), style: Theme.of(c).textTheme.bodySmall),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                final ok = await guard(c, () => ref.read(actionsProvider).run((u) => ref.read(billRepositoryProvider)
                    .payBill(u, b.id, accountId: accountId!, amount: Money.parse(amount.text), date: date, idempotencyKey: key)));
                if (ok != null && c.mounted) {
                  Navigator.pop(c);
                  await ref.read(actionsProvider).rescheduleReminders();
                }
              },
              child: Text(l.tr('pay')),
            ),
          ]),
        ),
      ),
    ),
  );
}

void showBillForm(BuildContext context, WidgetRef ref, {Bill? existing}) {
  final l = context.l;
  final name = TextEditingController(text: existing?.name ?? '');
  final amount = TextEditingController(text: existing?.amount.toString() ?? '');
  final remind = TextEditingController(text: '${existing?.remindDaysBefore ?? 3}');
  final notes = TextEditingController(text: existing?.notes ?? '');
  var kind = existing?.kind ?? BillKind.electricity;
  var rec = existing?.recurrence ?? Frequency.monthly;
  String? currency = existing?.currency ?? ref.read(sessionProvider)!.baseCurrency;
  String? accountId = existing?.accountId;
  var due = existing?.dueDate ?? DateTime.now().add(const Duration(days: 7));
  final form = GlobalKey<FormState>();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SheetFrame(
        title: l.tr(existing == null ? 'add_bill' : 'edit_bill'),
        child: Form(
          key: form,
          child: Column(children: [
            TextFormField(controller: name, decoration: InputDecoration(labelText: l.tr('name')), validator: (v) => (v ?? '').trim().isEmpty ? l.tr('required') : null),
            const SizedBox(height: 10),
            DropdownButtonFormField<BillKind>(
              initialValue: kind,
              decoration: InputDecoration(labelText: l.tr('type')),
              items: [for (final k in BillKind.values) DropdownMenuItem(value: k, child: Row(children: [Icon(billIcon(k), size: 18), const SizedBox(width: 8), Text(l.tr('bill_${k.name}'))]))],
              onChanged: (v) => set(() => kind = v!),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(flex: 3, child: AmountField(controller: amount, label: l.tr('amount'))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: CurrencyField(value: currency, currencies: ref.read(currenciesProvider).value ?? const <Currency>[], label: l.tr('currency'), onChanged: (v) => set(() => currency = v))),
            ]),
            const SizedBox(height: 10),
            DateField(label: l.tr('due_date'), value: due, onChanged: (d) => set(() => due = d)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<Frequency>(
                  initialValue: rec,
                  decoration: InputDecoration(labelText: l.tr('repeat')),
                  items: [for (final f in [Frequency.once, Frequency.weekly, Frequency.monthly, Frequency.quarterly, Frequency.yearly]) DropdownMenuItem(value: f, child: Text(l.tr('freq_${f.name}')))],
                  onChanged: (v) => set(() => rec = v!),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(controller: remind, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.tr('remind_days_before')))),
            ]),
            const SizedBox(height: 10),
            AccountField(value: accountId, accounts: ref.read(accountsProvider).value ?? const <Account>[], required: false, label: l.tr('default_account'), onChanged: (v) => set(() => accountId = v)),
            const SizedBox(height: 10),
            TextFormField(controller: notes, decoration: InputDecoration(labelText: l.tr('notes'))),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (!form.currentState!.validate() || currency == null) return;
                final ok = await guard(c, () => ref.read(actionsProvider).run((u) => ref.read(billRepositoryProvider).saveBill(u, id: existing?.id, name: name.text, kind: kind,
                    amount: Money.parse(amount.text), currency: currency!, dueDate: due, recurrence: rec, remindDaysBefore: int.tryParse(remind.text) ?? 3,
                    accountId: accountId, notes: notes.text)));
                if (ok != null && c.mounted) {
                  Navigator.pop(c);
                  await ref.read(actionsProvider).rescheduleReminders();
                }
              },
              child: Text(l.tr('save')),
            ),
          ]),
        ),
      ),
    ),
  );
}

class BillDetailScreen extends ConsumerWidget {
  final String id;
  const BillDetailScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final b = (ref.watch(billsProvider).value ?? const <Bill>[]).where((x) => x.id == id).firstOrNull;
    if (b == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    ref.watch(revisionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(b.name), actions: [
        IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => showBillForm(context, ref, existing: b)),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            if (!await confirm(context, l.tr('delete'), l.tr('delete_bill_note'), danger: true) || !context.mounted) return;
            final ok = await guard(context, () => ref.read(actionsProvider).run((u) => ref.read(billRepositoryProvider).deleteBill(u, id)).then((_) => true));
            if (ok == true && context.mounted) Navigator.pop(context);
          },
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(child: _BillTile(b)),
        SectionTitle(l.tr('payment_history')),
        FutureBuilder(
          future: ref.read(billRepositoryProvider).payments(ref.read(sessionProvider)!.id, id),
          builder: (context, s) => Card(
            child: (s.data ?? const <BillPayment>[]).isEmpty
                ? Padding(padding: const EdgeInsets.all(20), child: Text(l.tr('no_payments_yet'), textAlign: TextAlign.center))
                : Column(children: [
                    for (final p in s.data!)
                      ListTile(
                        leading: Icon(p.voided ? Icons.block_rounded : Icons.check_circle_rounded, color: p.voided ? Colors.grey : AppColors.income),
                        title: Text('${l.tr('cycle_due')} ${isoDay(p.dueDate)}'),
                        subtitle: Text('${l.tr('paid_on')} ${isoDay(p.paidAt)}${p.voided ? ' · ${l.tr('voided')}' : ''}'),
                        trailing: MoneyText(p.amount, currency: p.currency, style: const TextStyle(fontWeight: FontWeight.w700)),
                      ),
                  ]),
          ),
        ),
      ]),
    );
  }
}
