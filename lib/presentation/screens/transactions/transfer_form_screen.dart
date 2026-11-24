import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/ids.dart';
import '../../../domain/entities/account.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

/// Transfer between own accounts (never income/expense). Cross-currency:
/// enter the amount received; the effective rate and the FX difference vs
/// your latest manual rate are shown. Fees are recorded as an expense.
class TransferFormScreen extends ConsumerStatefulWidget {
  const TransferFormScreen({super.key});
  @override
  ConsumerState<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends ConsumerState<TransferFormScreen> {
  final _form = GlobalKey<FormState>();
  final key = newIdempotencyKey();
  final amount = TextEditingController(), toAmount = TextEditingController(), fee = TextEditingController(), notes = TextEditingController();
  String? fromId, toId;
  DateTime date = DateTime.now();
  bool saving = false;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final accs = (ref.watch(accountsProvider).value ?? const <Account>[]).where((a) => a.isActive).toList();
    final from = accs.where((a) => a.id == fromId).firstOrNull, to = accs.where((a) => a.id == toId).firstOrNull;
    final cross = from != null && to != null && from.currency != to.currency;
    final a = Money.tryParse(amount.text), ta = Money.tryParse(toAmount.text);
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('add_transfer'))),
      body: accs.length < 2
          ? EmptyState(Icons.swap_horiz_rounded, l.tr('need_two_accounts'))
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                AccountField(value: fromId, accounts: accs, label: l.tr('from_account'), onChanged: (v) => setState(() => fromId = v)),
                const SizedBox(height: 6),
                Center(
                  child: IconButton.filledTonal(
                    icon: const Icon(Icons.swap_vert_rounded),
                    onPressed: () => setState(() {
                      final t = fromId;
                      fromId = toId;
                      toId = t;
                    }),
                  ),
                ),
                const SizedBox(height: 6),
                AccountField(value: toId, accounts: accs, label: l.tr('to_account'), onChanged: (v) => setState(() => toId = v)),
                const SizedBox(height: 12),
                AmountField(controller: amount, label: l.tr('amount_sent'), suffix: from?.currency, onChanged: (_) => setState(() {})),
                if (cross) ...[
                  const SizedBox(height: 12),
                  AmountField(controller: toAmount, label: l.tr('amount_received'), suffix: to.currency, required: false, onChanged: (_) => setState(() {})),
                  const SizedBox(height: 6),
                  _FxPanel(from: from, to: to, amount: a, received: ta, date: date),
                ],
                const SizedBox(height: 12),
                AmountField(controller: fee, label: l.tr('transfer_fee'), suffix: from?.currency, required: false, allowZero: true),
                const SizedBox(height: 12),
                DateField(label: l.tr('date_time'), value: date, withTime: true, onChanged: (d) => setState(() => date = d)),
                const SizedBox(height: 12),
                TextFormField(controller: notes, decoration: InputDecoration(labelText: l.tr('notes')), maxLines: 2),
                const SizedBox(height: 8),
                InfoBanner(Icons.info_outline_rounded, l.tr('transfer_not_income_note'), color: AppColors.transfer),
                const SizedBox(height: 18),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.transfer),
                  onPressed: saving ? null : () => _save(from, to),
                  icon: const Icon(Icons.check_rounded),
                  label: Text(l.tr('save')),
                ),
              ]),
            ),
    );
  }

  Future<void> _save(Account? from, Account? to) async {
    if (!_form.currentState!.validate() || from == null || to == null) return;
    if (from.id == to.id) {
      showSnack(context, context.tr('err_same_account'), error: true);
      return;
    }
    setState(() => saving = true);
    final ok = await guard(context, () async {
      await ref.read(actionsProvider).transfer(TransferDraft(
            fromAccountId: from.id, toAccountId: to.id, amount: Money.parse(amount.text),
            toAmount: from.currency != to.currency ? Money.tryParse(toAmount.text) : null,
            fee: Money.tryParse(fee.text) ?? Decimal.zero, txnDate: date, notes: notes.text, idempotencyKey: key));
      return true;
    }, success: context.tr('saved'));
    if (!mounted) return;
    setState(() => saving = false);
    if (ok == true) Navigator.pop(context);
  }
}

class _FxPanel extends ConsumerWidget {
  final Account from, to;
  final Decimal? amount, received;
  final DateTime date;
  const _FxPanel({required this.from, required this.to, required this.amount, required this.received, required this.date});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    if (amount == null || amount!.sign <= 0) return const SizedBox.shrink();
    ref.watch(revisionProvider);
    return FutureBuilder(
      future: ref.read(currencyRepositoryProvider).tryConvert(ref.read(sessionProvider)!.id, amount!, from.currency, to.currency, date),
      builder: (context, snap) {
        final conv = snap.data;
        final lines = <String>[];
        if (received != null && received!.sign > 0) {
          lines.add(l.tr('effective_rate', {'rate': Money.div(received!, amount!, scale: 6).toString(), 'from': from.currency, 'to': to.currency}));
          if (conv != null) {
            final diff = received! - conv.amount;
            lines.add(l.tr('fx_difference', {'diff': Money.format(diff, currency: to.currency, showSign: true), 'rate': conv.rate.toString(), 'source': conv.source ?? ''}));
          }
        } else if (conv != null) {
          lines.add(l.tr('will_receive', {'amount': Money.format(conv.amount, currency: to.currency), 'rate': conv.rate.toString(), 'source': conv.source ?? ''}));
        } else {
          return InfoBanner(Icons.warning_amber_rounded, l.tr('transfer_need_rate', {'from': from.currency, 'to': to.currency}),
              onTap: () => showRateDialog(context, from: from.currency, to: to.currency, date: date));
        }
        return InfoBanner(Icons.currency_exchange_rounded, lines.join('\n'), color: AppColors.transfer);
      },
    );
  }
}
