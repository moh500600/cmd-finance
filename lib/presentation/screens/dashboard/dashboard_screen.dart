import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/services/alerts.dart';
import '../../../domain/services/finance_math.dart';
import '../../../domain/services/snapshot.dart';
import '../../providers/providers.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/txn_tile.dart';
import '../more/more_screen.dart';

final dashPeriodProvider = NotifierProvider<_PeriodN, PeriodKind>(_PeriodN.new);

class _PeriodN extends Notifier<PeriodKind> {
  @override
  PeriodKind build() => PeriodKind.monthly;
  void set(PeriodKind k) => state = k;
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final user = ref.watch(sessionProvider);
    final period = ref.watch(dashPeriodProvider);
    final hide = ref.watch(settingsProvider.select((s) => s.hideAmounts));
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.tr('hello_name', {'name': user?.name ?? ''}), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          Text(l.tr('dashboard_sub'), style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          IconButton(
            tooltip: l.tr('hide_amounts'),
            icon: Icon(hide ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            onPressed: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(hideAmounts: !s.hideAmounts)),
          ),
        ],
      ),
      body: AsyncBody(ref.watch(snapshotProvider), (s) {
        final range = DateRange.of(period, s.now);
        final st = DashboardStats.compute(s, range);
        final alerts = AlertsService(l.tr).current(s);
        final months = Charts.months(s, n: 6);
        final labels = [for (final m in months) '${m.month.month}/${m.month.year % 100}'];
        final byCat = FinanceMath.byCategory(s.txns, range);
        final thisM = DateRange.of(PeriodKind.monthly, s.now), lastM = thisM.previous(PeriodKind.monthly);
        final cmpCats = FinanceMath.byCategory(s.txns, thisM).take(5).map((e) => e.key).toList();
        final lastMap = {for (final e in FinanceMath.byCategory(s.txns, lastM)) e.key: e.value};
        final thisMap = {for (final e in FinanceMath.byCategory(s.txns, thisM)) e.key: e.value};
        final recent = s.txns.take(6).toList();
        return RefreshIndicator(
          onRefresh: () async => ref.read(actionsProvider).startup(),
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 96), children: [
            _NetWorthHero(st: st, base: s.base),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final k in const [PeriodKind.daily, PeriodKind.weekly, PeriodKind.monthly, PeriodKind.quarterly, PeriodKind.yearly])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: ChoiceChip(label: Text(l.tr('period_${k.name}')), selected: period == k, onSelected: (_) => ref.read(dashPeriodProvider.notifier).set(k)),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(builder: (context, c) {
              final cols = c.maxWidth > 700 ? 4 : 2;
              final w = (c.maxWidth - (cols - 1) * 10) / cols;
              final cards = [
                _Stat(l.tr('stat_total_assets'), st.totalAssets, Icons.account_balance_rounded, AppColors.primary),
                _Stat(l.tr('stat_cash'), st.cash, Icons.payments_rounded, AppColors.gold),
                _Stat(l.tr('stat_bank'), st.bank, Icons.account_balance_outlined, AppColors.transfer),
                _Stat(l.tr('stat_income'), st.income, Icons.south_west_rounded, AppColors.income),
                _Stat(l.tr('stat_expense'), st.expense, Icons.north_east_rounded, AppColors.expense),
                _Stat(l.tr('stat_net_cash_flow'), st.netCashFlow, Icons.waterfall_chart_rounded, st.netCashFlow.total.sign < 0 ? AppColors.expense : AppColors.income),
                _Stat(l.tr('stat_i_owe'), st.iOwe, Icons.call_made_rounded, AppColors.expense),
                _Stat(l.tr('stat_owed_to_me'), st.owedToMe, Icons.call_received_rounded, AppColors.income),
                _Stat(l.tr('stat_net_worth'), st.netWorth, Icons.diamond_rounded, AppColors.primaryDark),
                _Stat(l.tr('stat_savings_rate'), null, Icons.savings_rounded, AppColors.primary, percent: st.savingsRate),
              ];
              return Wrap(spacing: 10, runSpacing: 10, children: [for (final x in cards) SizedBox(width: w, child: _StatCard(x, base: s.base))]);
            }),
            if (alerts.isNotEmpty) ...[
              SectionTitle(l.tr('financial_alerts')),
              for (final a in alerts.take(6))
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InfoBanner(
                    switch (a.level) { AlertLevel.danger => Icons.error_rounded, AlertLevel.success => Icons.celebration_rounded, AlertLevel.info => Icons.info_rounded, _ => Icons.warning_rounded },
                    a.message,
                    color: switch (a.level) { AlertLevel.danger => AppColors.expense, AlertLevel.success => AppColors.income, AlertLevel.info => AppColors.transfer, _ => AppColors.warning },
                    onTap: a.route == null ? null : () => openRoute(context, a.route!),
                  ),
                ),
            ],
            SectionTitle(l.tr('charts')),
            ChartCard(
              title: l.tr('chart_income_vs_expense'),
              legend: Legend([(l.tr('income'), AppColors.income), (l.tr('expenses'), AppColors.expense)]),
              child: GroupedBars(labels: labels, series: [[for (final m in months) m.income], [for (final m in months) m.expense]], colors: const [AppColors.income, AppColors.expense]),
            ),
            const SizedBox(height: 10),
            ChartCard(
              title: '${l.tr('chart_expense_by_category')} · ${l.tr('period_${period.name}')}',
              height: 170,
              child: byCat.isEmpty ? Center(child: Text(l.tr('no_expenses_period'))) : Donut(data: [for (final e in byCat.take(8)) (l.category(s.categories[e.key]), e.value)]),
            ),
            const SizedBox(height: 10),
            ChartCard(title: l.tr('chart_balance_trend'), child: TrendLine(labels: labels, values: [for (final m in months) m.balance ?? Decimal.zero])),
            const SizedBox(height: 10),
            ChartCard(title: l.tr('chart_monthly_cash_flow'), child: SignedBars(labels: labels, values: [for (final m in months) m.net])),
            const SizedBox(height: 10),
            ChartCard(
              title: l.tr('chart_month_comparison'),
              legend: Legend([(l.tr('last_month'), AppColors.transfer.withValues(alpha: 0.5)), (l.tr('this_month'), AppColors.primary)]),
              child: cmpCats.isEmpty
                  ? Center(child: Text(l.tr('no_expenses_period')))
                  : GroupedBars(
                      labels: [for (final k in cmpCats) _short(l.category(s.categories[k]))],
                      series: [[for (final k in cmpCats) lastMap[k] ?? Decimal.zero], [for (final k in cmpCats) thisMap[k] ?? Decimal.zero]],
                      colors: [AppColors.transfer.withValues(alpha: 0.5), AppColors.primary]),
            ),
            SectionTitle(l.tr('recent_transactions')),
            Card(
              child: recent.isEmpty
                  ? Padding(padding: const EdgeInsets.all(20), child: Text(l.tr('no_transactions_yet'), textAlign: TextAlign.center))
                  : Column(children: [for (final t in recent) TxnTile(t)]),
            ),
          ]),
        );
      }),
    );
  }

  static String _short(String s) => s.length > 7 ? '${s.substring(0, 6)}…' : s;
}

class _Stat {
  final String label;
  final BaseTotal? value;
  final IconData icon;
  final Color color;
  final Decimal? percent;
  const _Stat(this.label, this.value, this.icon, this.color, {this.percent});
}

class _StatCard extends StatelessWidget {
  final _Stat s;
  final String base;
  const _StatCard(this.s, {required this.base});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              IconBadge(s.icon, s.color, size: 30),
              const Spacer(),
              if (s.value != null && !s.value!.complete) Tooltip(message: context.tr('missing_rates_for'), child: const Icon(Icons.warning_amber_rounded, size: 16, color: AppColors.warning)),
            ]),
            const SizedBox(height: 8),
            Text(s.label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            if (s.percent != null)
              Text('${s.percent}%', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800), textDirection: TextDirection.ltr)
            else
              MoneyText(s.value!.total, currency: base, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          ]),
        ),
      );
}

class _NetWorthHero extends StatelessWidget {
  final DashboardStats st;
  final String base;
  const _NetWorthHero({required this.st, required this.base});
  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark, Color(0xFF0B1324)], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontFamily: 'Tajawal'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l.tr('stat_net_worth'), style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          MoneyText(st.netWorth.total, currency: base, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w800)),
          if (!st.netWorth.complete)
            Text(l.tr('excludes_no_rate', {'ccy': st.netWorth.missing.join(', ')}), style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _mini(l.tr('stat_income'), st.income.total, Icons.south_west_rounded)),
            Expanded(child: _mini(l.tr('stat_expense'), st.expense.total, Icons.north_east_rounded)),
            Expanded(child: _mini(l.tr('stat_savings_rate'), null, Icons.savings_rounded, pct: '${st.savingsRate}%')),
          ]),
        ]),
      ),
    );
  }

  Widget _mini(String label, Decimal? v, IconData i, {String? pct}) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(i, size: 14, color: Colors.white70), const SizedBox(width: 4), Flexible(child: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70), overflow: TextOverflow.ellipsis))]),
        pct != null
            ? Text(pct, style: const TextStyle(fontWeight: FontWeight.w800), textDirection: TextDirection.ltr)
            : MoneyText(v!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ]);
}

/// Navigation for alert taps.
void openRoute(BuildContext context, String route) => Navigator.push(context, MaterialPageRoute(builder: (_) => routeTarget(route)));

String moneyBase(Decimal d, String base) => Money.format(d, currency: base);
