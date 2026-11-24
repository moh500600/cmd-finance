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
import '../../widgets/txn_tile.dart';

class DebtsScreen extends ConsumerWidget {
  const DebtsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: Text(l.tr('menu_debts')), bottom: TabBar(tabs: [Tab(text: l.tr('i_owe')), Tab(text: l.tr('owed_to_me'))])),
        floatingActionButton: Builder(
          builder: (ctx) => FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(l.tr('add_debt')),
            onPressed: () => Navigator.push(ctx, MaterialPageRoute(builder: (_) => DebtFormScreen(direction: DefaultTabController.of(ctx).index == 0 ? DebtDirection.iOwe : DebtDirection.owedToMe))),
          ),
        ),
        body: AsyncBody(ref.watch(debtsProvider), (list) => TabBarView(children: [
              for (final dir in DebtDirection.values) _DebtList(list.where((d) => d.debt.direction == dir).toList(), dir),
            ])),
      ),
    );
  }
}

class _DebtList extends StatelessWidget {
  final List<DebtSummary> list;
  final DebtDirection dir;
  const _DebtList(this.list, this.dir);
  @override
  Widget build(BuildContext context) {
    final l = context.l;
    if (list.isEmpty) return EmptyState(Icons.handshake_rounded, l.tr(dir == DebtDirection.iOwe ? 'no_debts' : 'no_receivables'));
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
      for (final d in list)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Card(
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtDetailScreen(id: d.debt.id))),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    IconBadge(Icons.person_rounded, dir == DebtDirection.iOwe ? AppColors.expense : AppColors.income),
                    const SizedBox(width: 10),
                    Expanded(child: Text(d.debt.party, style: const TextStyle(fontWeight: FontWeight.w800))),
                    _StatusChip(d),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Text('${l.tr('remaining')}: '),
                    Flexible(child: MoneyText(d.remaining, currency: d.debt.currency, style: const TextStyle(fontWeight: FontWeight.w800))),
                    const Spacer(),
                    Text('${l.tr('of')} '),
                    Flexible(child: MoneyText(d.totalPayable, currency: d.debt.currency, style: const TextStyle(fontSize: 12))),
                  ]),
                  const SizedBox(height: 8),
                  PercentBar(d.percentPaid, color: AppColors.income),
                  if (d.nextInstallment != null) ...[
                    const SizedBox(height: 6),
                    Text('${l.tr('next_due')}: ${isoDay(d.nextInstallment!.dueDate)} · ${Money.format(d.nextInstallment!.amount, currency: d.debt.currency)}',
                        style: TextStyle(fontSize: 12, color: d.overdue ? AppColors.expense : null)),
                  ],
                ]),
              ),
            ),
          ),
        ),
    ]);
  }
}

class _StatusChip extends StatelessWidget {
  final DebtSummary d;
  const _StatusChip(this.d);
  @override
  Widget build(BuildContext context) {
    final (key, color) = d.remaining.sign == 0 ? ('settled', AppColors.income) : d.overdue ? ('overdue', AppColors.expense) : ('open', AppColors.transfer);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(8)),
      child: Text(context.tr(key), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }
}

class DebtFormScreen extends ConsumerStatefulWidget {
  final DebtDirection direction;
  final Debt? existing;
  const DebtFormScreen({super.key, required this.direction, this.existing});
  @override
  ConsumerState<DebtFormScreen> createState() => _DebtFormScreenState();
}

class _DebtFormScreenState extends ConsumerState<DebtFormScreen> {
  final _form = GlobalKey<FormState>();
  final key = newIdempotencyKey();
  late final party = TextEditingController(text: widget.existing?.party ?? '');
  late final principal = TextEditingController(text: widget.existing?.principal.toString() ?? '');
  late final interest = TextEditingController(text: widget.existing?.interestRate.toString() ?? '0');
  late final installments = TextEditingController(text: '${widget.existing?.installments ?? 1}');
  late final notes = TextEditingController(text: widget.existing?.notes ?? '');
  late String? currency = widget.existing?.currency ?? ref.read(sessionProvider)!.baseCurrency;
  late DateTime start = widget.existing?.startDate ?? DateTime.now();
  late DateTime? due = widget.existing?.dueDate;
  late Frequency freq = widget.existing?.installmentFrequency ?? Frequency.monthly;
  String? accountId;
  bool moveMoney = false;

  bool get iOwe => widget.direction == DebtDirection.iOwe;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final ccys = ref.watch(currenciesProvider).value ?? const <Currency>[];
    final accs = ref.watch(accountsProvider).value ?? const <Account>[];
    final editing = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr(iOwe ? 'debt_i_owe_title' : 'debt_owed_title'))),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: party, decoration: InputDecoration(labelText: l.tr(iOwe ? 'creditor' : 'debtor'), prefixIcon: const Icon(Icons.person_outline)),
              validator: (v) => (v ?? '').trim().isEmpty ? l.tr('required') : null),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(flex: 3, child: AmountField(controller: principal, label: l.tr('principal'))),
            const SizedBox(width: 8),
            Expanded(flex: 2, child: CurrencyField(value: currency, currencies: ccys, label: l.tr('currency'), enabled: !editing, onChanged: (v) => setState(() => currency = v))),
          ]),
          const SizedBox(height: 10),
          AmountField(controller: interest, label: l.tr('interest_rate_annual'), suffix: '%', allowZero: true),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: DateField(label: l.tr('debt_date'), value: start, onChanged: (d) => setState(() => start = d))),
            const SizedBox(width: 8),
            Expanded(child: DateField(label: l.tr(iOwe ? 'due_date' : 'expected_date'), value: due, onChanged: (d) => setState(() => due = d), onClear: () => setState(() => due = null))),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextFormField(controller: installments, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.tr('installments')),
                  validator: (v) => (int.tryParse(v ?? '') ?? 0) < 1 ? l.tr('err_installments') : null),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<Frequency>(
                initialValue: freq,
                decoration: InputDecoration(labelText: l.tr('frequency')),
                items: [for (final f in [Frequency.weekly, Frequency.monthly, Frequency.quarterly, Frequency.yearly]) DropdownMenuItem(value: f, child: Text(l.tr('freq_${f.name}')))],
                onChanged: (v) => setState(() => freq = v!),
              ),
            ),
          ]),
          if (!editing) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: moveMoney,
              title: Text(l.tr(iOwe ? 'money_received_into' : 'money_paid_from')),
              subtitle: Text(l.tr('loan_not_income_note')),
              onChanged: (v) => setState(() => moveMoney = v),
            ),
            if (moveMoney) AccountField(value: accountId, accounts: accs, label: l.tr('account'), onChanged: (v) => setState(() => accountId = v)),
          ],
          const SizedBox(height: 10),
          TextFormField(controller: notes, decoration: InputDecoration(labelText: l.tr('notes')), maxLines: 2),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: () async {
              if (!_form.currentState!.validate()) return;
              final repo = ref.read(debtRepositoryProvider);
              final ok = await guard(context, () => ref.read(actionsProvider).run((u) async {
                    if (editing) {
                      final e = widget.existing!;
                      return repo.updateDebt(u, Debt(id: e.id, userId: e.userId, direction: e.direction, party: party.text.trim(), principal: Money.parse(principal.text),
                          currency: e.currency, interestRate: Money.parse(interest.text), startDate: start, dueDate: due, installments: int.parse(installments.text),
                          installmentFrequency: freq, notes: notes.text, status: e.status, accountId: e.accountId, createdAt: e.createdAt, updatedAt: DateTime.now()));
                    }
                    return repo.createDebt(u, direction: widget.direction, party: party.text, principal: Money.parse(principal.text), currency: currency!,
                        interestRate: Money.parse(interest.text), startDate: start, dueDate: due, installments: int.parse(installments.text), frequency: freq,
                        notes: notes.text, accountId: accountId, moveMoney: moveMoney, idempotencyKey: key);
                  }), success: l.tr('saved'));
              if (ok != null && context.mounted) Navigator.pop(context);
            },
            child: Text(l.tr('save')),
          ),
        ]),
      ),
    );
  }
}

class DebtDetailScreen extends ConsumerWidget {
  final String id;
  const DebtDetailScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final d = (ref.watch(debtsProvider).value ?? const <DebtSummary>[]).where((x) => x.debt.id == id).firstOrNull;
    if (d == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final c = d.debt.currency;
    final iOwe = d.debt.direction == DebtDirection.iOwe;
    return Scaffold(
      appBar: AppBar(title: Text(d.debt.party), actions: [
        IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtFormScreen(direction: d.debt.direction, existing: d.debt)))),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            if (!await confirm(context, l.tr('delete'), l.tr('delete_debt_note'), danger: true) || !context.mounted) return;
            final ok = await guard(context, () => ref.read(actionsProvider).run((u) => ref.read(debtRepositoryProvider).deleteDebt(u, id)).then((_) => true));
            if (ok == true && context.mounted) Navigator.pop(context);
          },
        ),
      ]),
      floatingActionButton: d.remaining.sign > 0
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.payments_rounded),
              label: Text(l.tr(iOwe ? 'record_payment' : 'record_collection')),
              onPressed: () => _pay(context, ref, d),
            )
          : null,
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              _kv(context, l.tr('principal'), Money.format(d.debt.principal, currency: c)),
              _kv(context, '${l.tr('interest')} (${d.debt.interestRate}%)', Money.format(d.interest, currency: c)),
              _kv(context, l.tr('total_payable'), Money.format(d.totalPayable, currency: c)),
              _kv(context, l.tr(iOwe ? 'paid' : 'collected'), Money.format(d.paid, currency: c)),
              _kv(context, l.tr('remaining'), Money.format(d.remaining, currency: c), bold: true),
              const SizedBox(height: 8),
              PercentBar(d.percentPaid, color: AppColors.income),
              const SizedBox(height: 8),
              _kv(context, l.tr('debt_date'), isoDay(d.debt.startDate)),
              if (d.debt.dueDate != null) _kv(context, l.tr(iOwe ? 'due_date' : 'expected_date'), isoDay(d.debt.dueDate!)),
              _kv(context, l.tr('status'), l.tr(d.remaining.sign == 0 ? 'settled' : d.overdue ? 'overdue' : 'open')),
              if (d.debt.notes.isNotEmpty) _kv(context, l.tr('notes'), d.debt.notes),
            ]),
          ),
        ),
        SectionTitle(l.tr('repayment_schedule')),
        Card(
          child: Column(children: [
            for (final i in d.schedule)
              ListTile(
                dense: true,
                leading: Icon(i.paid ? Icons.check_circle_rounded : (i.dueDate.isBefore(DateTime.now()) ? Icons.error_outline_rounded : Icons.radio_button_unchecked),
                    color: i.paid ? AppColors.income : (i.dueDate.isBefore(DateTime.now()) ? AppColors.expense : null)),
                title: Text('${l.tr('installment')} ${i.index}'),
                subtitle: Text(isoDay(i.dueDate)),
                trailing: MoneyText(i.amount, currency: c, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
        SectionTitle(l.tr(iOwe ? 'payment_history' : 'collection_history')),
        FutureBuilder(
          future: ref.read(debtRepositoryProvider).payments(ref.read(sessionProvider)!.id, id),
          builder: (context, s) => Card(
            child: (s.data ?? const []).isEmpty
                ? Padding(padding: const EdgeInsets.all(20), child: Text(l.tr('no_payments_yet'), textAlign: TextAlign.center))
                : Column(children: [for (final t in s.data!) TxnTile(t)]),
          ),
        ),
      ]),
    );
  }

  Widget _kv(BuildContext c, String k, String v, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(child: Text(k, style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant))),
        Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600), textDirection: TextDirection.ltr),
      ]));

  void _pay(BuildContext context, WidgetRef ref, DebtSummary d) {
    final l = context.l;
    final amount = TextEditingController(text: (d.nextInstallment?.amount ?? d.remaining).toString());
    final notes = TextEditingController();
    String? accountId = d.debt.accountId;
    var date = DateTime.now();
    final key = newIdempotencyKey();
    final form = GlobalKey<FormState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SheetFrame(
          title: l.tr(d.debt.direction == DebtDirection.iOwe ? 'record_payment' : 'record_collection'),
          child: Form(
            key: form,
            child: Column(children: [
              AmountField(controller: amount, label: l.tr('amount'), suffix: d.debt.currency),
              const SizedBox(height: 10),
              AccountField(value: accountId, accounts: ref.read(accountsProvider).value ?? const [], label: l.tr('account'), onChanged: (v) => set(() => accountId = v)),
              const SizedBox(height: 10),
              DateField(label: l.tr('date'), value: date, onChanged: (v) => set(() => date = v)),
              const SizedBox(height: 10),
              TextFormField(controller: notes, decoration: InputDecoration(labelText: l.tr('notes'))),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  final ok = await guard(c, () => ref.read(actionsProvider).run((u) => ref.read(debtRepositoryProvider)
                      .addPayment(u, d.debt.id, accountId: accountId!, amount: Money.parse(amount.text), date: date, notes: notes.text, idempotencyKey: key)));
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
}
