import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../core/utils/ids.dart';
import '../../../domain/entities/currency.dart';
import '../../../domain/entities/planning.dart';
import '../../providers/providers.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/txn_tile.dart';

class SavingsScreen extends ConsumerWidget {
  const SavingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('menu_savings'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => showGoalForm(context, ref), icon: const Icon(Icons.add), label: Text(l.tr('add_goal'))),
      body: AsyncBody(ref.watch(goalsProvider), (list) {
        if (list.isEmpty) return EmptyState(Icons.savings_rounded, l.tr('no_goals'));
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          for (final g in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => GoalDetailScreen(id: g.goal.id))),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(children: [
                      SizedBox(
                        width: 64,
                        height: 64,
                        child: Stack(alignment: Alignment.center, children: [
                          CircularProgressIndicator(value: (g.percent.toDouble() / 100).clamp(0, 1), strokeWidth: 7, color: Color(g.goal.color),
                              backgroundColor: Color(g.goal.color).withValues(alpha: 0.15)),
                          Text('${g.percent.round()}%', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13), textDirection: TextDirection.ltr),
                        ]),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(g.goal.name, style: const TextStyle(fontWeight: FontWeight.w800))),
                            if (g.reached) const Icon(Icons.emoji_events_rounded, color: AppColors.gold),
                          ]),
                          MoneyText(g.current, currency: g.goal.currency, style: const TextStyle(fontWeight: FontWeight.w700)),
                          Text('${l.tr('target')}: ${Money.format(g.goal.target, currency: g.goal.currency)}', style: const TextStyle(fontSize: 12)),
                          if (g.monthlyNeeded(DateTime.now()) != null && !g.reached)
                            Text(l.tr('save_per_month', {'amount': Money.format(g.monthlyNeeded(DateTime.now())!, currency: g.goal.currency)}),
                                style: const TextStyle(fontSize: 12, color: AppColors.primary)),
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ]);
      }),
    );
  }
}

void showGoalForm(BuildContext context, WidgetRef ref, {SavingsGoal? existing}) {
  final l = context.l;
  final name = TextEditingController(text: existing?.name ?? '');
  final target = TextEditingController(text: existing?.target.toString() ?? '');
  final initial = TextEditingController(text: existing?.initialAmount.toString() ?? '0');
  final notes = TextEditingController(text: existing?.notes ?? '');
  String? currency = existing?.currency ?? ref.read(sessionProvider)!.baseCurrency;
  DateTime? deadline = existing?.deadline;
  var color = existing?.color ?? AppColors.chart[1].toARGB32();
  final form = GlobalKey<FormState>();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SheetFrame(
        title: l.tr(existing == null ? 'add_goal' : 'edit_goal'),
        child: Form(
          key: form,
          child: Column(children: [
            TextFormField(controller: name, decoration: InputDecoration(labelText: l.tr('goal_name')), validator: (v) => (v ?? '').trim().isEmpty ? l.tr('required') : null),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(flex: 3, child: AmountField(controller: target, label: l.tr('target'))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: CurrencyField(value: currency, currencies: ref.read(currenciesProvider).value ?? const <Currency>[], label: l.tr('currency'),
                  enabled: existing == null, onChanged: (v) => set(() => currency = v))),
            ]),
            const SizedBox(height: 10),
            AmountField(controller: initial, label: l.tr('current_amount_start'), allowZero: true),
            const SizedBox(height: 10),
            DateField(label: l.tr('deadline'), value: deadline, onChanged: (d) => set(() => deadline = d), onClear: () => set(() => deadline = null)),
            const SizedBox(height: 10),
            TextFormField(controller: notes, decoration: InputDecoration(labelText: l.tr('notes'))),
            const SizedBox(height: 10),
            Wrap(spacing: 8, children: [
              for (final col in AppColors.chart.take(8))
                GestureDetector(onTap: () => set(() => color = col.toARGB32()),
                    child: CircleAvatar(radius: 14, backgroundColor: col, child: color == col.toARGB32() ? const Icon(Icons.check, size: 14, color: Colors.white) : null)),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (!form.currentState!.validate() || currency == null) return;
                final ok = await guard(c, () => ref.read(actionsProvider).run((u) => ref.read(goalRepositoryProvider).saveGoal(u, id: existing?.id, name: name.text,
                    target: Money.parse(target.text), currency: currency!, initialAmount: Money.tryParse(initial.text), deadline: deadline, color: color, notes: notes.text)));
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

class GoalDetailScreen extends ConsumerWidget {
  final String id;
  const GoalDetailScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final g = (ref.watch(goalsProvider).value ?? const <GoalStatus>[]).where((x) => x.goal.id == id).firstOrNull;
    if (g == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final c = g.goal.currency;
    return Scaffold(
      appBar: AppBar(title: Text(g.goal.name), actions: [
        IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => showGoalForm(context, ref, existing: g.goal)),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            if (!await confirm(context, l.tr('delete'), l.tr('delete_goal_note'), danger: true) || !context.mounted) return;
            final ok = await guard(context, () => ref.read(actionsProvider).run((u) => ref.read(goalRepositoryProvider).deleteGoal(u, id)).then((_) => true));
            if (ok == true && context.mounted) Navigator.pop(context);
          },
        ),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              Text('${g.percent}%', style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Color(g.goal.color)), textDirection: TextDirection.ltr),
              const SizedBox(height: 8),
              PercentBar(g.percent, color: Color(g.goal.color)),
              const SizedBox(height: 12),
              Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                _col(l.tr('current'), MoneyText(g.current, currency: c, style: const TextStyle(fontWeight: FontWeight.w800))),
                _col(l.tr('target'), MoneyText(g.goal.target, currency: c, style: const TextStyle(fontWeight: FontWeight.w800))),
                _col(l.tr('remaining'), MoneyText(g.remaining, currency: c, style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
              if (g.goal.deadline != null) ...[
                const Divider(height: 24),
                Text('${l.tr('deadline')}: ${isoDay(g.goal.deadline!)}'),
                if (g.monthlyNeeded(DateTime.now()) != null && !g.reached)
                  Text(l.tr('save_per_month', {'amount': Money.format(g.monthlyNeeded(DateTime.now())!, currency: c)}), style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ],
              if (g.reached) Padding(padding: const EdgeInsets.only(top: 8), child: InfoBanner(Icons.emoji_events_rounded, l.tr('alert_goal_reached', {'name': g.goal.name}), color: AppColors.income)),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: FilledButton.icon(icon: const Icon(Icons.add_rounded), label: Text(l.tr('deposit')), onPressed: () => _move(context, ref, g, true))),
          const SizedBox(width: 10),
          Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.remove_rounded), label: Text(l.tr('withdraw')), onPressed: g.current.sign > 0 ? () => _move(context, ref, g, false) : null)),
        ]),
        const SizedBox(height: 12),
        if (g.history.length > 1)
          ChartCard(title: l.tr('progress_chart'), child: TrendLine(labels: [for (final h in g.history) '${h.$1.day}/${h.$1.month}'], values: [for (final h in g.history) h.$2], color: Color(g.goal.color))),
        SectionTitle(l.tr('movements')),
        FutureBuilder(
          future: ref.read(goalRepositoryProvider).movements(ref.read(sessionProvider)!.id, id),
          builder: (context, s) => Card(
            child: (s.data ?? const []).isEmpty
                ? Padding(padding: const EdgeInsets.all(20), child: Text(l.tr('no_movements'), textAlign: TextAlign.center))
                : Column(children: [for (final t in s.data!) TxnTile(t)]),
          ),
        ),
      ]),
    );
  }

  Widget _col(String k, Widget v) => Column(children: [Text(k, style: const TextStyle(fontSize: 12)), v]);

  void _move(BuildContext context, WidgetRef ref, GoalStatus g, bool deposit) {
    final l = context.l;
    final amount = TextEditingController();
    String? accountId;
    final key = newIdempotencyKey();
    final form = GlobalKey<FormState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => SheetFrame(
          title: l.tr(deposit ? 'deposit' : 'withdraw'),
          child: Form(
            key: form,
            child: Column(children: [
              AmountField(controller: amount, label: l.tr('amount'), suffix: g.goal.currency),
              const SizedBox(height: 10),
              AccountField(value: accountId, accounts: ref.read(accountsProvider).value ?? const [], required: false,
                  label: l.tr(deposit ? 'from_account_optional' : 'to_account_optional'), onChanged: (v) => set(() => accountId = v)),
              const SizedBox(height: 6),
              Text(l.tr('goal_move_note'), style: Theme.of(c).textTheme.bodySmall),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () async {
                  if (!form.currentState!.validate()) return;
                  final reached = await guard(c, () => ref.read(actionsProvider).run((u) => ref.read(goalRepositoryProvider)
                      .move(u, g.goal.id, deposit: deposit, accountId: accountId, amount: Money.parse(amount.text), date: DateTime.now(), idempotencyKey: key)));
                  if (reached == null || !c.mounted) return;
                  Navigator.pop(c);
                  if (reached && ref.read(settingsProvider).notifications.goals) {
                    await ref.read(notificationServiceProvider).showNow(950, l.tr('app_name'), l.tr('alert_goal_reached', {'name': g.goal.name}));
                    if (context.mounted) showSnack(context, '🎉 ${l.tr('alert_goal_reached', {'name': g.goal.name})}');
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
}
