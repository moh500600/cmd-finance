import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../../core/platform/desktop_files.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/ids.dart';
import '../../../domain/entities/account.dart';
import '../../../domain/entities/currency.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../settings/categories_screen.dart';

enum _Repeat { once, recurring, scheduled }

/// Add / edit income or expense. One idempotency key per opened form, so a
/// double tap never records twice.
class TransactionFormScreen extends ConsumerStatefulWidget {
  final TxnType type;
  final FinTransaction? existing;
  final TxnDraft? prefill; // from the assistant's quick add
  const TransactionFormScreen({super.key, required this.type, this.existing, this.prefill});
  @override
  ConsumerState<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends ConsumerState<TransactionFormScreen> {
  final _form = GlobalKey<FormState>();
  late final key = widget.existing?.idempotencyKey ?? newIdempotencyKey();
  late final amount = TextEditingController(text: widget.existing?.amount.toString() ?? widget.prefill?.amount.toString() ?? '');
  late final title = TextEditingController(text: widget.existing?.title ?? widget.prefill?.title ?? '');
  late final notes = TextEditingController(text: widget.existing?.notes ?? '');
  late String? accountId = widget.existing?.accountId ?? widget.prefill?.accountId;
  late String? categoryId = widget.existing?.categoryId ?? widget.prefill?.categoryId;
  late String? currency = widget.existing?.currency ?? widget.prefill?.currency;
  late DateTime date = widget.existing?.txnDate ?? widget.prefill?.txnDate ?? DateTime.now();
  late List<String> attachments = [...?widget.existing?.attachments];
  _Repeat repeat = _Repeat.once;
  Frequency freq = Frequency.monthly;
  DateTime? endDate;
  bool saving = false;

  bool get income => widget.type == TxnType.income;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final accs = ref.watch(accountsProvider).value ?? const <Account>[];
    final cats = (ref.watch(categoriesProvider).value ?? const <Category>[]).where((c) => c.kind == (income ? CategoryKind.income : CategoryKind.expense)).toList();
    final ccys = ref.watch(currenciesProvider).value ?? const <Currency>[];
    final user = ref.watch(sessionProvider)!;
    final acc = accs.where((a) => a.id == accountId).firstOrNull;
    if (accountId == null && accs.where((a) => a.isActive).isNotEmpty) {
      accountId = accs.firstWhere((a) => a.isActive).id;
    }
    currency ??= acc?.currency;
    final color = income ? AppColors.income : AppColors.expense;
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing != null ? l.tr(income ? 'edit_income' : 'edit_expense') : l.tr(income ? 'add_income' : 'add_expense'))),
      body: accs.where((a) => a.isActive).isEmpty
          ? EmptyState(Icons.account_balance_wallet_rounded, l.tr('need_account_first'))
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Row(children: [
                  Expanded(flex: 3, child: AmountField(controller: amount, label: l.tr('amount'), onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: CurrencyField(value: currency, currencies: ccys, label: l.tr('currency'), onChanged: (v) => setState(() => currency = v))),
                ]),
                _ConversionHint(amount: amount.text, currency: currency, account: acc, base: user.baseCurrency, date: date),
                const SizedBox(height: 12),
                AccountField(value: accountId, accounts: accs, label: l.tr(income ? 'received_in' : 'paid_from'), onChanged: (v) => setState(() {
                      accountId = v;
                      currency = accs.firstWhere((a) => a.id == v).currency;
                    })),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: CategoryField(value: categoryId, categories: cats, onChanged: (v) => setState(() => categoryId = v))),
                  IconButton(
                    tooltip: l.tr('add_category'),
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    onPressed: () async {
                      final id = await showCategoryEditor(context, ref, income ? CategoryKind.income : CategoryKind.expense);
                      if (id != null) setState(() => categoryId = id);
                    },
                  ),
                ]),
                const SizedBox(height: 12),
                DateField(label: l.tr('date_time'), value: date, withTime: true, onChanged: (d) => setState(() => date = d)),
                const SizedBox(height: 12),
                TextFormField(controller: title, decoration: InputDecoration(labelText: l.tr(income ? 'income_source' : 'description'), prefixIcon: const Icon(Icons.short_text_rounded)),
                    maxLength: 120, validator: (v) => (v ?? '').length > 120 ? l.tr('too_long') : null),
                TextFormField(controller: notes, decoration: InputDecoration(labelText: l.tr('notes'), prefixIcon: const Icon(Icons.notes_rounded)), maxLines: 3, maxLength: 1000),
                const SizedBox(height: 4),
                Text(l.tr(income ? 'attachments' : 'invoice_attachments'), style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in attachments)
                    InputChip(label: Text(p.basename(a), overflow: TextOverflow.ellipsis), avatar: const Icon(Icons.attach_file_rounded, size: 16),
                        onDeleted: () => setState(() => attachments.remove(a))),
                  ActionChip(avatar: const Icon(Icons.photo_camera_outlined, size: 18), label: Text(l.tr('add_photo')), onPressed: _addPhoto),
                  ActionChip(avatar: const Icon(Icons.upload_file_rounded, size: 18), label: Text(l.tr('add_file')), onPressed: _addFile),
                ]),
                if (widget.existing == null) ...[
                  const SizedBox(height: 16),
                  SegmentedButton<_Repeat>(
                    segments: [
                      ButtonSegment(value: _Repeat.once, label: Text(l.tr('once'))),
                      ButtonSegment(value: _Repeat.recurring, label: Text(l.tr('recurring'))),
                      ButtonSegment(value: _Repeat.scheduled, label: Text(l.tr('scheduled'))),
                    ],
                    selected: {repeat},
                    onSelectionChanged: (s) => setState(() => repeat = s.first),
                  ),
                  if (repeat == _Repeat.recurring) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<Frequency>(
                      initialValue: freq,
                      decoration: InputDecoration(labelText: l.tr('frequency')),
                      items: [for (final f in Frequency.values.where((f) => f != Frequency.once)) DropdownMenuItem(value: f, child: Text(l.tr('freq_${f.name}')))],
                      onChanged: (v) => setState(() => freq = v!),
                    ),
                    const SizedBox(height: 10),
                    DateField(label: l.tr('end_date_optional'), value: endDate, onChanged: (d) => setState(() => endDate = d), onClear: () => setState(() => endDate = null)),
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.tr('recurring_note'), style: Theme.of(context).textTheme.bodySmall)),
                  ],
                  if (repeat == _Repeat.scheduled)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text(l.tr('scheduled_note'), style: Theme.of(context).textTheme.bodySmall)),
                ],
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: color),
                  onPressed: saving ? null : _save,
                  icon: const Icon(Icons.check_rounded),
                  label: Text(l.tr('save')),
                ),
              ]),
            ),
    );
  }

  Future<void> _addPhoto() async {
    final x = await pickImageFile(source: ImageSource.gallery, imageQuality: 80);
    if (x == null) return;
    final path = await ref.read(fileStorageProvider).saveBytes(await x.readAsBytes(), x.name);
    setState(() => attachments.add(path));
  }

  Future<void> _addFile() async {
    final f = await FilePicker.pickFile();
    if (f == null) return;
    final path = await ref.read(fileStorageProvider).saveBytes(await f.xFile.readAsBytes(), f.name);
    setState(() => attachments.add(path));
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (repeat == _Repeat.scheduled && !date.isAfter(DateTime.now())) {
      showSnack(context, context.tr('scheduled_future'), error: true);
      return;
    }
    setState(() => saving = true);
    final l = context.l;
    final draft = TxnDraft(type: widget.type, accountId: accountId, amount: Money.parse(amount.text), currency: currency!, categoryId: categoryId,
        title: title.text, notes: notes.text, txnDate: date, attachments: attachments, idempotencyKey: key);
    final actions = ref.read(actionsProvider);
    final ok = await guard(context, () async {
      if (widget.existing != null) {
        await actions.run((u) => ref.read(transactionRepositoryProvider).updateTxn(u, widget.existing!.id, draft));
      } else if (repeat == _Repeat.once) {
        await actions.record(draft);
      } else {
        // validate rates now so the user hears about a missing rate immediately
        await ref.read(currencyRepositoryProvider).convert(actions.uid, draft.amount, draft.currency, ref.read(sessionProvider)!.baseCurrency, date);
        await actions.run((u) => ref.read(transactionRepositoryProvider).saveRecurring(u, template: draft, frequency: freq, firstDate: date,
            endDate: endDate, scheduledOnce: repeat == _Repeat.scheduled));
        await actions.startup();
      }
      return true;
    }, success: l.tr('saved'));
    if (!mounted) return;
    setState(() => saving = false);
    if (ok == true) Navigator.pop(context, true);
  }
}

/// Shows which manual rate will be used — or says clearly that one is missing.
class _ConversionHint extends ConsumerWidget {
  final String amount;
  final String? currency;
  final Account? account;
  final String base;
  final DateTime date;
  const _ConversionHint({required this.amount, required this.currency, required this.account, required this.base, required this.date});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = Money.tryParse(amount);
    if (a == null || currency == null) return const SizedBox.shrink();
    final targets = {if (account != null && account!.currency != currency) account!.currency, if (base != currency) base};
    if (targets.isEmpty) return const SizedBox.shrink();
    final repo = ref.watch(currencyRepositoryProvider);
    final uid = ref.watch(sessionProvider)!.id;
    ref.watch(revisionProvider);
    return FutureBuilder(
      future: Future.wait([for (final t in targets) repo.tryConvert(uid, a, currency!, t, date)]),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final l = context.l;
        final lines = <Widget>[];
        var i = 0;
        for (final t in targets) {
          final c = snap.data![i++];
          lines.add(Padding(
            padding: const EdgeInsets.only(top: 6),
            child: c == null
                ? InfoBanner(Icons.warning_amber_rounded, l.tr('rate_missing_inline', {'from': currency!, 'to': t}),
                    onTap: () => showRateDialog(context, from: currency, to: t, date: date))
                : InfoBanner(Icons.currency_exchange_rounded,
                    l.tr('rate_used_inline', {'amount': Money.format(c.amount, currency: t), 'rate': c.rate.toString(), 'from': currency!, 'to': t, 'date': isoDay(c.rateDate!), 'source': c.source ?? ''}),
                    color: AppColors.transfer),
          ));
        }
        return Column(children: lines);
      },
    );
  }
}
