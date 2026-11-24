import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/l10n/l10n.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/transaction.dart';
import '../providers/providers.dart';
import '../screens/transactions/transaction_detail_screen.dart';
import 'common.dart';
import 'visuals.dart';

String txnTitle(L10n l, FinTransaction t, Map<String, Category> cats) {
  if (t.title.startsWith('fee:')) return l.tr('transfer_fee');
  if (t.title.isNotEmpty) return t.title;
  if (t.type == TxnType.income || t.type == TxnType.expense) return l.category(cats[t.categoryId]);
  return l.tr('txn_${t.type.name}');
}

class TxnTile extends ConsumerWidget {
  final FinTransaction t;
  const TxnTile(this.t, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final cats = {for (final c in ref.watch(categoriesProvider).value ?? const <Category>[]) c.id: c};
    final accs = {for (final a in ref.watch(accountsProvider).value ?? const <Account>[]) a.id: a};
    final cat = cats[t.categoryId];
    final color = t.isVoid ? Colors.grey : (cat != null ? Color(cat.color) : txnColor(t.type));
    final subtitle = t.type == TxnType.transfer
        ? '${accs[t.accountId]?.name ?? '—'} → ${accs[t.toAccountId]?.name ?? '—'}'
        : '${l.tr('txn_${t.type.name}')} · ${accs[t.accountId]?.name ?? '—'}';
    return ListTile(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionDetailScreen(id: t.id))),
      leading: IconBadge(cat != null ? categoryIcon(cat) : txnIcon(t.type), color),
      title: Text(txnTitle(l, t, cats), maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: FontWeight.w700, decoration: t.isVoid ? TextDecoration.lineThrough : null)),
      subtitle: Text('$subtitle · ${fmtDate(context, t.txnDate)}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        MoneyText(t.type == TxnType.transfer ? t.amount : t.amount * Decimal.fromInt(t.type.sign), currency: t.currency, signed: t.type != TxnType.transfer,
            colored: !t.isVoid && t.type != TxnType.transfer, style: const TextStyle(fontWeight: FontWeight.w800)),
        if (t.isVoid) Text(l.tr('voided'), style: const TextStyle(fontSize: 11, color: Colors.grey))
        else if (t.currency != t.baseCurrency) MoneyText(t.baseAmount, currency: t.baseCurrency, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ]),
    );
  }
}
