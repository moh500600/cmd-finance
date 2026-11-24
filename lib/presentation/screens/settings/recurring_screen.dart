import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/entities/transaction.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/visuals.dart';

/// Recurring and scheduled income/expenses (posted automatically when due).
class RecurringScreen extends ConsumerWidget {
  const RecurringScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('menu_recurring'))),
      body: AsyncBody(ref.watch(recurringProvider), (rules) {
        if (rules.isEmpty) return EmptyState(Icons.event_repeat_rounded, l.tr('no_recurring'));
        return ListView(padding: const EdgeInsets.all(16), children: [
          InfoBanner(Icons.info_outline_rounded, l.tr('recurring_screen_note'), color: AppColors.transfer),
          const SizedBox(height: 10),
          Card(
            child: Column(children: [
              for (final r in rules)
                ListTile(
                  leading: IconBadge(txnIcon(r.template.type), txnColor(r.template.type)),
                  title: Text(r.template.title.isEmpty ? l.tr('txn_${r.template.type.name}') : r.template.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    r.scheduledOnce ? l.tr('scheduled') : l.tr('freq_${r.frequency.name}'),
                    '${l.tr('next')}: ${isoDay(r.nextDate)}',
                    if (!r.active) l.tr('stopped'),
                    if (r.lastError != null) '⚠ ${r.lastError}',
                  ].join(' · ')),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    MoneyText(r.template.amount, currency: r.template.currency, style: TextStyle(fontWeight: FontWeight.w700, color: r.template.type == TxnType.income ? AppColors.income : AppColors.expense)),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        final repo = ref.read(transactionRepositoryProvider);
                        if (v == 'toggle') await guard(context, () => ref.read(actionsProvider).run((u) => repo.setRecurringActive(u, r.id, !r.active)));
                        if (v == 'delete' && context.mounted && await confirm(context, l.tr('delete'), l.tr('delete_recurring_note'), danger: true)) {
                          if (context.mounted) await guard(context, () => ref.read(actionsProvider).run((u) => repo.deleteRecurring(u, r.id)));
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(value: 'toggle', child: Text(l.tr(r.active ? 'pause' : 'resume'))),
                        PopupMenuItem(value: 'delete', child: Text(l.tr('delete'))),
                      ],
                    ),
                  ]),
                ),
            ]),
          ),
        ]);
      }),
    );
  }
}
