import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/account.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/txn_tile.dart';
import '../../widgets/visuals.dart';
import 'transaction_form_screen.dart';

/// Full record of one transaction: original/account/base amounts, rate used,
/// timestamps, attachments, audit trail, edit and void (soft delete).
class TransactionDetailScreen extends ConsumerWidget {
  final String id;
  const TransactionDetailScreen({super.key, required this.id});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('transaction'))),
      body: AsyncBody(ref.watch(txnProvider(id)), (t) {
        if (t == null) return EmptyState(Icons.search_off_rounded, l.tr('err_txn_not_found'));
        final cats = {for (final c in ref.watch(categoriesProvider).value ?? const <Category>[]) c.id: c};
        final accs = {for (final a in ref.watch(accountsProvider).value ?? const <Account>[]) a.id: a};
        final audit = ref.watch(auditProvider(id)).value ?? const [];
        final editable = !t.isVoid && (t.type == TxnType.income || t.type == TxnType.expense) && t.refType == null && t.parentId == null;
        Widget row(String k, Widget v) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 130, child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
                Expanded(child: v),
              ]),
            );
        Widget text(String s) => Text(s, style: const TextStyle(fontWeight: FontWeight.w600));
        return ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                IconBadge(cats[t.categoryId] != null ? categoryIcon(cats[t.categoryId]) : txnIcon(t.type), txnColor(t.type), size: 56),
                const SizedBox(height: 10),
                Text(txnTitle(l, t, cats), style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                const SizedBox(height: 6),
                MoneyText(t.amount, currency: t.currency, style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: txnColor(t.type))),
                if (t.isVoid)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Chip(label: Text('${l.tr('voided')} · ${t.voidReason ?? ''}'), backgroundColor: AppColors.expense.withValues(alpha: 0.12)),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(children: [
                row(l.tr('type'), text(l.tr('txn_${t.type.name}'))),
                if (t.categoryId != null) row(l.tr('category'), text(l.category(cats[t.categoryId]))),
                row(l.tr(t.type == TxnType.transfer ? 'from_account' : 'account'), text(accs[t.accountId]?.name ?? '—')),
                if (t.toAccountId != null) row(l.tr('to_account'), text(accs[t.toAccountId]?.name ?? '—')),
                row(l.tr('original_amount'), MoneyText(t.amount, currency: t.currency, style: const TextStyle(fontWeight: FontWeight.w600))),
                if (t.accountAmount != null && accs[t.accountId] != null && accs[t.accountId]!.currency != t.currency)
                  row(l.tr('account_amount'), MoneyText(t.accountAmount!, currency: accs[t.accountId]!.currency, style: const TextStyle(fontWeight: FontWeight.w600))),
                if (t.toAmount != null) row(l.tr('amount_received'), MoneyText(t.toAmount!, currency: t.toCurrency, style: const TextStyle(fontWeight: FontWeight.w600))),
                if (t.fxRate != null && t.toCurrency != t.currency) row(l.tr('rate_used'), text('1 ${t.currency} = ${t.fxRate} ${t.toCurrency}')),
                if (t.fee.sign > 0) row(l.tr('transfer_fee'), MoneyText(t.fee, currency: t.currency, style: const TextStyle(fontWeight: FontWeight.w600))),
                row(l.tr('base_amount'), MoneyText(t.baseAmount, currency: t.baseCurrency, style: const TextStyle(fontWeight: FontWeight.w600))),
                if (t.currency != t.baseCurrency && t.baseRate != null) row(l.tr('base_rate'), text('1 ${t.currency} = ${t.baseRate} ${t.baseCurrency}')),
                row(l.tr('txn_date'), text(fmtDate(context, t.txnDate, time: true))),
                row(l.tr('created_at'), text(fmtDate(context, t.createdAt.toLocal(), time: true))),
                row(l.tr('updated_at'), text(fmtDate(context, t.updatedAt.toLocal(), time: true))),
                if (t.notes.isNotEmpty) row(l.tr('notes'), text(t.notes)),
                if (t.recurringId != null) row(l.tr('recurring'), text('✓')),
                row(l.tr('idempotency_key'), Text(t.idempotencyKey, style: const TextStyle(fontSize: 11), textDirection: TextDirection.ltr)),
              ]),
            ),
          ),
          if (t.attachments.isNotEmpty) ...[
            SectionTitle(l.tr('attachments')),
            Card(
              child: Column(children: [
                for (final a in t.attachments)
                  ListTile(
                    leading: File(a).existsSync() && RegExp(r'\.(jpe?g|png|webp)$', caseSensitive: false).hasMatch(a)
                        ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(a), width: 44, height: 44, fit: BoxFit.cover))
                        : const Icon(Icons.insert_drive_file_rounded),
                    title: Text(p.basename(a), overflow: TextOverflow.ellipsis),
                    onTap: () => OpenFilex.open(a),
                  ),
              ]),
            ),
          ],
          SectionTitle(l.tr('audit_trail')),
          Card(
            child: Column(children: [
              for (final e in audit)
                ExpansionTile(
                  leading: Icon(switch (e.action) { 'create' => Icons.add_circle_outline, 'void' => Icons.block_rounded, _ => Icons.edit_note_rounded }),
                  title: Text(l.tr('audit_${e.action}')),
                  subtitle: Text(fmtDate(context, e.at.toLocal(), time: true)),
                  children: [
                    if (e.before != null) _json(l.tr('before'), e.before!),
                    if (e.after != null) _json(l.tr('after'), e.after!),
                  ],
                ),
            ]),
          ),
          const SizedBox(height: 16),
          if (editable)
            OutlinedButton.icon(
              icon: const Icon(Icons.edit_rounded),
              label: Text(l.tr('edit')),
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TransactionFormScreen(type: t.type, existing: t))),
            ),
          const SizedBox(height: 8),
          if (!t.isVoid && t.parentId == null)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.expense),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(l.tr('delete_void')),
              onPressed: () async {
                if (!await confirm(context, l.tr('delete_void'), l.tr('void_explain'), danger: true)) return;
                if (!context.mounted) return;
                await guard(context, () => ref.read(actionsProvider).run((u) => ref.read(transactionRepositoryProvider).voidTxn(u, t.id, reason: l.tr('deleted_by_user'))),
                    success: l.tr('voided_done'));
              },
            ),
        ]);
      }),
    );
  }

  Widget _json(String label, String raw) {
    String pretty;
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      const keep = ['amount', 'currency', 'account_amount', 'base_amount', 'base_currency', 'to_amount', 'fee', 'status', 'title', 'txn_date', 'category_id', 'account_id'];
      pretty = keep.where(m.containsKey).map((k) => '$k: ${m[k]}').join('\n');
    } catch (_) {
      pretty = raw;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text('$label\n$pretty', style: const TextStyle(fontSize: 11, fontFamily: 'monospace'), textDirection: TextDirection.ltr),
      ),
    );
  }
}
