import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/account.dart';
import '../../../domain/entities/currency.dart';
import '../../../domain/services/snapshot.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/txn_tile.dart';
import '../../widgets/visuals.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('nav_accounts')), actions: [
        IconButton(icon: const Icon(Icons.add_card_rounded), tooltip: l.tr('add_account'), onPressed: () => showAccountForm(context)),
      ]),
      body: AsyncBody(ref.watch(snapshotProvider), (s) {
        if (s.accounts.isEmpty) {
          return EmptyState(Icons.account_balance_wallet_rounded, l.tr('no_accounts'),
              action: FilledButton.icon(onPressed: () => showAccountForm(context), icon: const Icon(Icons.add), label: Text(l.tr('add_account'))));
        }
        final total = s.accountsTotal();
        final byType = <AccountType, List<Valued<Account>>>{};
        for (final a in s.accounts) {
          byType.putIfAbsent(a.item.type, () => []).add(a);
        }
        return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
          Card(
            color: AppColors.primary,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.tr('total_balances'), style: const TextStyle(color: Colors.white70)),
                MoneyText(total.total, currency: s.base, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                if (!total.complete) Text(l.tr('excludes_no_rate', {'ccy': total.missing.join(', ')}), style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
              ]),
            ),
          ),
          for (final type in AccountType.values)
            if (byType[type] != null) ...[
              SectionTitle(l.tr('acct_${type.name}')),
              Card(
                child: Column(children: [
                  for (final v in byType[type]!)
                    ListTile(
                      leading: IconBadge(accountIcon(v.item.type), v.item.isActive ? Color(v.item.color) : Colors.grey),
                      title: Text(v.item.name, style: TextStyle(fontWeight: FontWeight.w700, color: v.item.isActive ? null : Colors.grey)),
                      subtitle: Text(v.item.isActive ? (v.item.description.isEmpty ? v.currency : v.item.description) : l.tr('disabled')),
                      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                        MoneyText(v.amount, currency: v.currency, colored: v.amount.sign < 0, style: const TextStyle(fontWeight: FontWeight.w800)),
                        if (v.currency != s.base)
                          v.base == null
                              ? Text(l.tr('no_rate'), style: const TextStyle(fontSize: 11, color: AppColors.warning))
                              : MoneyText(v.base!, currency: s.base, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ]),
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountDetailScreen(id: v.item.id))),
                    ),
                ]),
              ),
            ],
        ]);
      }),
    );
  }
}

Future<void> showAccountForm(BuildContext context, {Account? existing}) =>
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => AccountForm(existing: existing));

class AccountForm extends ConsumerStatefulWidget {
  final Account? existing;
  const AccountForm({super.key, this.existing});
  @override
  ConsumerState<AccountForm> createState() => _AccountFormState();
}

class _AccountFormState extends ConsumerState<AccountForm> {
  final _form = GlobalKey<FormState>();
  late final name = TextEditingController(text: widget.existing?.name ?? '');
  late final desc = TextEditingController(text: widget.existing?.description ?? '');
  late final opening = TextEditingController(text: widget.existing?.openingBalance.toString() ?? '0');
  late final low = TextEditingController(text: widget.existing?.lowBalanceAlert?.toString() ?? '');
  late AccountType type = widget.existing?.type ?? AccountType.cash;
  late String? currency = widget.existing?.currency ?? ref.read(sessionProvider)?.baseCurrency;
  late int color = widget.existing?.color ?? AppColors.chart.first.toARGB32();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final ccys = ref.watch(currenciesProvider).value ?? const <Currency>[];
    return SheetFrame(
      title: l.tr(widget.existing == null ? 'add_account' : 'edit_account'),
      child: Form(
        key: _form,
        child: Column(children: [
          TextFormField(controller: name, decoration: InputDecoration(labelText: l.tr('account_name')), validator: (v) => (v ?? '').trim().isEmpty ? l.tr('required') : null),
          const SizedBox(height: 10),
          DropdownButtonFormField<AccountType>(
            initialValue: type,
            decoration: InputDecoration(labelText: l.tr('account_type')),
            items: [for (final t in AccountType.values) DropdownMenuItem(value: t, child: Row(children: [Icon(accountIcon(t), size: 18), const SizedBox(width: 8), Text(l.tr('acct_${t.name}'))]))],
            onChanged: (v) => setState(() => type = v!),
          ),
          const SizedBox(height: 10),
          CurrencyField(value: currency, currencies: ccys, label: l.tr('currency'), enabled: widget.existing == null, onChanged: (v) => setState(() => currency = v)),
          const SizedBox(height: 10),
          AmountField(controller: opening, label: l.tr('opening_balance'), allowZero: true, suffix: currency),
          if (widget.existing != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(l.tr('opening_edit_note'), style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 10),
          AmountField(controller: low, label: l.tr('low_balance_alert'), required: false, allowZero: true, suffix: currency),
          const SizedBox(height: 10),
          TextFormField(controller: desc, decoration: InputDecoration(labelText: l.tr('description')), maxLines: 2),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            for (final c in AppColors.chart.take(8))
              GestureDetector(
                onTap: () => setState(() => color = c.toARGB32()),
                child: CircleAvatar(radius: 15, backgroundColor: c, child: color == c.toARGB32() ? const Icon(Icons.check, size: 16, color: Colors.white) : null),
              ),
          ]),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              if (!_form.currentState!.validate() || currency == null) return;
              final repo = ref.read(accountRepositoryProvider);
              final ok = await guard(context, () => ref.read(actionsProvider).run((u) async {
                    final lowV = Money.tryParse(low.text);
                    if (widget.existing == null) {
                      return repo.createAccount(u, name: name.text, type: type, currency: currency!, openingBalance: Money.parse(opening.text),
                          description: desc.text, color: color, lowBalanceAlert: lowV);
                    }
                    return repo.updateAccount(u, widget.existing!.copyWith(name: name.text, type: type, description: desc.text, color: color,
                        openingBalance: Money.parse(opening.text), lowBalanceAlert: lowV, clearLow: lowV == null));
                  }));
              if (ok != null && context.mounted) Navigator.pop(context);
            },
            child: Text(l.tr('save')),
          ),
        ]),
      ),
    );
  }
}

/// Account page: balance, details, full transaction log, edit and disable.
class AccountDetailScreen extends ConsumerWidget {
  final String id;
  const AccountDetailScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final acc = (ref.watch(accountsProvider).value ?? const <Account>[]).where((a) => a.id == id).firstOrNull;
    if (acc == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: Text(acc.name), actions: [
        IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => showAccountForm(context, existing: acc)),
        PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'toggle') {
              await guard(context, () => ref.read(actionsProvider).run((u) => ref.read(accountRepositoryProvider).setActive(u, acc.id, !acc.isActive)),
                  success: l.tr(acc.isActive ? 'account_disabled' : 'account_enabled'));
            }
          },
          itemBuilder: (_) => [PopupMenuItem(value: 'toggle', child: Text(l.tr(acc.isActive ? 'disable_account' : 'enable_account')))],
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconBadge(accountIcon(acc.type), Color(acc.color)),
                const SizedBox(width: 10),
                Expanded(child: Text('${l.tr('acct_${acc.type.name}')} · ${acc.currency}', style: const TextStyle(fontWeight: FontWeight.w700))),
                if (!acc.isActive) Chip(label: Text(l.tr('disabled'))),
              ]),
              const SizedBox(height: 12),
              Text(l.tr('current_balance'), style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              MoneyText(acc.balance, currency: acc.currency, colored: acc.balance.sign < 0, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
              const Divider(height: 24),
              _kv(context, l.tr('opening_balance'), Money.format(acc.openingBalance, currency: acc.currency)),
              _kv(context, l.tr('created_at'), fmtDate(context, acc.createdAt.toLocal())),
              if (acc.lowBalanceAlert != null) _kv(context, l.tr('low_balance_alert'), Money.format(acc.lowBalanceAlert!, currency: acc.currency)),
              if (acc.description.isNotEmpty) _kv(context, l.tr('description'), acc.description),
            ]),
          ),
        ),
        SectionTitle(l.tr('transaction_log')),
        AsyncBody(ref.watch(accountTxnsProvider(acc.id)), (list) => Card(
              child: list.isEmpty
                  ? Padding(padding: const EdgeInsets.all(20), child: Text(l.tr('no_transactions_yet'), textAlign: TextAlign.center))
                  : Column(children: [for (final t in list) TxnTile(t)]),
            )),
      ]),
    );
  }

  Widget _kv(BuildContext c, String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(k, style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant))), Text(v, style: const TextStyle(fontWeight: FontWeight.w600))]));
}
