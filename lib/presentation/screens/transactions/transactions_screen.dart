import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/desktop_files.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/entities/account.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/repositories/repositories.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/txn_tile.dart';

/// Global search across all transactions: text (title/notes/amount/category/
/// account/currency/type), filters, sort, export CSV/Excel.
class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});
  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final search = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final q = ref.watch(txnQueryProvider);
    final set = ref.read(txnQueryProvider.notifier).set;
    final list = ref.watch(txnListProvider);
    final filters = [q.accountId, q.categoryId, q.currency, q.from, q.minAmount, q.maxAmount].where((x) => x != null).length + (q.includeVoided ? 1 : 0);
    return Scaffold(
      appBar: AppBar(
        title: Text(l.tr('nav_transactions')),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.sort_rounded),
            tooltip: l.tr('sort'),
            onSelected: (v) => set(q.copyWith(sort: v)),
            itemBuilder: (_) => [
              for (final s in const ['date_desc', 'date_asc', 'amount_desc', 'amount_asc'])
                CheckedPopupMenuItem(value: s, checked: q.sort == s, child: Text(l.tr('sort_$s'))),
            ],
          ),
          PopupMenuButton<bool>(
            icon: const Icon(Icons.ios_share_rounded),
            tooltip: l.tr('export'),
            onSelected: (excel) => _export(excel),
            itemBuilder: (_) => [PopupMenuItem(value: false, child: Text(l.tr('export_csv'))), PopupMenuItem(value: true, child: Text(l.tr('export_excel')))],
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: search,
                decoration: InputDecoration(hintText: l.tr('search_hint'), prefixIcon: const Icon(Icons.search_rounded), isDense: true,
                    suffixIcon: search.text.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () {
                      search.clear();
                      set(q.copyWith(text: ''));
                    })),
                onChanged: (v) => set(q.copyWith(text: v)),
              ),
            ),
            const SizedBox(width: 8),
            Badge(
              isLabelVisible: filters > 0,
              label: Text('$filters'),
              child: IconButton.filledTonal(icon: const Icon(Icons.tune_rounded), onPressed: () => _filters(context)),
            ),
          ]),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            for (final (key, types) in [
              ('all', null),
              ('income', {TxnType.income}),
              ('expenses', {TxnType.expense}),
              ('transfers', {TxnType.transfer}),
              ('debts', {TxnType.debtPayment, TxnType.debtCollection, TxnType.loanGiven, TxnType.loanReceived}),
              ('savings', {TxnType.savingsDeposit, TxnType.savingsWithdraw}),
            ])
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: ChoiceChip(
                  label: Text(l.tr(key)),
                  selected: types == null ? q.types == null : (q.types != null && q.types!.length == types.length && q.types!.containsAll(types)),
                  onSelected: (_) => set(types == null ? q.copyWith(clearTypes: true) : q.copyWith(types: types)),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: AsyncBody(list, (items) {
            if (items.isEmpty) return EmptyState(Icons.receipt_long_rounded, l.tr('no_results'));
            final income = Money.sum(items.where((t) => t.type == TxnType.income).map((t) => t.baseAmount));
            final expense = Money.sum(items.where((t) => t.type == TxnType.expense).map((t) => t.baseAmount));
            final base = items.first.baseCurrency;
            return ListView(padding: const EdgeInsets.only(bottom: 96), children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Wrap(spacing: 14, runSpacing: 2, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(l.tr('n_results', {'n': '${items.length}'}), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${l.tr('income')}: ', style: const TextStyle(fontSize: 12)),
                    MoneyText(income, currency: base, style: const TextStyle(fontSize: 12, color: AppColors.income, fontWeight: FontWeight.w700)),
                  ]),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('${l.tr('expenses')}: ', style: const TextStyle(fontSize: 12)),
                    MoneyText(expense, currency: base, style: const TextStyle(fontSize: 12, color: AppColors.expense, fontWeight: FontWeight.w700)),
                  ]),
                ]),
              ),
              for (final t in items) TxnTile(t),
            ]);
          }),
        ),
      ]),
    );
  }

  Future<void> _export(bool excel) async {
    final l = context.l;
    final items = await ref.read(txnListProvider.future);
    final cats = {for (final c in await ref.read(categoriesProvider.future)) c.id: c};
    final accs = {for (final a in await ref.read(accountsProvider.future)) a.id: a};
    final rows = <List<String>>[
      ['date', 'type', 'amount', 'currency', 'account', 'to_account', 'to_amount', 'fee', 'category', 'title', 'notes', 'base_amount', 'base_currency', 'rate', 'status', 'created_at', 'updated_at'],
      for (final t in items)
        [t.txnDate.toIso8601String(), t.type.name, Money.toDb(t.amount), t.currency, accs[t.accountId]?.name ?? '', accs[t.toAccountId]?.name ?? '',
          t.toAmount == null ? '' : Money.toDb(t.toAmount!), Money.toDb(t.fee), l.category(cats[t.categoryId]), t.title, t.notes, Money.toDb(t.baseAmount),
          t.baseCurrency, t.baseRate?.toString() ?? '', t.status.name, t.createdAt.toIso8601String(), t.updatedAt.toIso8601String()],
    ];
    if (!mounted) return;
    await guard(context, () async {
      final f = await ref.read(exportServiceProvider).table('finance_pro_transactions', rows, excel: excel, rtl: l.ar);
      if (!mounted) return;
      await shareOrSaveFile(context, f, text: l.tr('nav_transactions'));
    });
  }

  void _filters(BuildContext context) => showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const _FilterSheet());
}

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet();
  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late TxnQuery q = ref.read(txnQueryProvider);
  late final min = TextEditingController(text: q.minAmount?.toString() ?? ''), max = TextEditingController(text: q.maxAmount?.toString() ?? '');

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final accs = ref.watch(accountsProvider).value ?? const <Account>[];
    final cats = ref.watch(categoriesProvider).value ?? const <Category>[];
    final ccys = ref.watch(currenciesProvider).value ?? const [];
    return SheetFrame(
      title: l.tr('filters'),
      child: Column(children: [
        AccountField(value: q.accountId, accounts: accs, label: l.tr('account'), required: false,
            onChanged: (v) => setState(() => q = v == null ? q.copyWith(clearAccount: true) : q.copyWith(accountId: v))),
        const SizedBox(height: 10),
        CategoryField(value: q.categoryId, categories: cats, allowNone: true,
            onChanged: (v) => setState(() => q = v == null ? q.copyWith(clearCategory: true) : q.copyWith(categoryId: v))),
        const SizedBox(height: 10),
        DropdownButtonFormField<String?>(
          initialValue: q.currency,
          decoration: InputDecoration(labelText: l.tr('currency')),
          items: [DropdownMenuItem<String?>(value: null, child: Text(l.tr('all'))), for (final c in ccys) DropdownMenuItem(value: c.code, child: Text(c.code))],
          onChanged: (v) => setState(() => q = v == null ? q.copyWith(clearCurrency: true) : q.copyWith(currency: v)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: DateField(label: l.tr('from'), value: q.from, onChanged: (d) => setState(() => q = q.copyWith(from: dayOnly(d))))),
          const SizedBox(width: 8),
          Expanded(child: DateField(label: l.tr('to'), value: q.to?.subtract(const Duration(days: 1)), onChanged: (d) => setState(() => q = q.copyWith(to: dayOnly(d).add(const Duration(days: 1)))))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: AmountField(controller: min, label: l.tr('min_amount'), required: false, allowZero: true)),
          const SizedBox(width: 8),
          Expanded(child: AmountField(controller: max, label: l.tr('max_amount'), required: false, allowZero: true)),
        ]),
        SwitchListTile(value: q.includeVoided, title: Text(l.tr('show_voided')), onChanged: (v) => setState(() => q = q.copyWith(includeVoided: v))),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                ref.read(txnQueryProvider.notifier).set(TxnQuery(text: q.text, types: q.types, sort: q.sort));
                Navigator.pop(context);
              },
              child: Text(l.tr('clear')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: FilledButton(
              onPressed: () {
                final mn = Money.tryParse(min.text), mx = Money.tryParse(max.text);
                ref.read(txnQueryProvider.notifier).set(q.copyWith(clearAmounts: true).copyWith(minAmount: mn, maxAmount: mx));
                Navigator.pop(context);
              },
              child: Text(l.tr('apply')),
            ),
          ),
        ]),
      ]),
    );
  }
}
