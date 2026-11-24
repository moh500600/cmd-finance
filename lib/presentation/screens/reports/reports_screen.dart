import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/desktop_files.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/services/report_builder.dart';
import '../../providers/providers.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportType type = ReportType.profitLoss;
  PeriodKind period = PeriodKind.monthly;
  DateRange? custom;
  DateTime anchor = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('nav_reports')), actions: [
        IconButton(tooltip: 'PDF', icon: const Icon(Icons.picture_as_pdf_rounded), onPressed: () => _export(pdf: true)),
        IconButton(tooltip: 'Excel', icon: const Icon(Icons.table_view_rounded), onPressed: () => _export(pdf: false)),
      ]),
      body: AsyncBody(ref.watch(snapshotProvider), (s) {
        final range = DateRange.of(period, anchor, custom: custom);
        final r = ReportBuilder(s, l.tr, l.category).build(type, range, _label(range));
        return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final t in ReportType.values)
                Padding(padding: const EdgeInsetsDirectional.only(end: 6), child: ChoiceChip(label: Text(l.tr('report_${t.name}')), selected: type == t, onSelected: (_) => setState(() => type = t))),
            ]),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              for (final p in PeriodKind.values)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 6),
                  child: ChoiceChip(
                    label: Text(l.tr('period_${p.name}')),
                    selected: period == p,
                    onSelected: (_) async {
                      if (p == PeriodKind.custom) {
                        final picked = await showDateRangePicker(context: context, firstDate: DateTime(2000), lastDate: DateTime(2100),
                            initialDateRange: DateTimeRange(start: range.start, end: range.end.subtract(const Duration(days: 1))));
                        if (picked == null) return;
                        custom = DateRange(dayOnly(picked.start), dayOnly(picked.end).add(const Duration(days: 1)));
                      }
                      setState(() => period = p);
                    },
                  ),
                ),
            ]),
          ),
          if (period != PeriodKind.custom)
            Row(children: [
              IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () => setState(() => anchor = range.previous(period).start)),
              Expanded(child: Text(_label(range), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
              IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => setState(() => anchor = range.end)),
            ])
          else
            Padding(padding: const EdgeInsets.all(8), child: Text(_label(range), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
          Text(r.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final x in r.summary)
              Container(
                padding: const EdgeInsets.all(10),
                constraints: const BoxConstraints(minWidth: 150),
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLowest, borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(x.$1, style: const TextStyle(fontSize: 12)),
                  Text(x.$2, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15), textDirection: TextDirection.ltr),
                ]),
              ),
          ]),
          for (final w in r.warnings) Padding(padding: const EdgeInsets.only(top: 8), child: InfoBanner(Icons.warning_amber_rounded, w)),
          if (r.chart.isNotEmpty) ...[
            const SizedBox(height: 12),
            ChartCard(
              title: l.tr('chart'),
              child: type == ReportType.netWorth || type == ReportType.cashFlow
                  ? (type == ReportType.netWorth
                      ? TrendLine(labels: [for (final c in r.chart) c.$1], values: [for (final c in r.chart) c.$2])
                      : SignedBars(labels: [for (final c in r.chart) c.$1.length > 5 ? c.$1.substring(c.$1.length - 5) : c.$1], values: [for (final c in r.chart) c.$2]))
                  : Donut(data: [for (final c in r.chart.take(8)) (c.$1, c.$2.abs())]),
            ),
          ],
          for (final t in r.tables) ...[
            SectionTitle(t.title),
            Card(
              child: t.rows.isEmpty
                  ? Padding(padding: const EdgeInsets.all(18), child: Text(l.tr('no_data'), textAlign: TextAlign.center))
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: DataTable(
                        headingRowColor: WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.08)),
                        columnSpacing: 18,
                        dataRowMinHeight: 36,
                        dataRowMaxHeight: 44,
                        columns: [for (final h in t.headers) DataColumn(label: Text(h, style: const TextStyle(fontWeight: FontWeight.w800)))],
                        rows: [for (final row in t.rows.take(300)) DataRow(cells: [for (final c in row) DataCell(Text(c, style: const TextStyle(fontSize: 12)))])],
                      ),
                    ),
            ),
          ],
        ]);
      }),
    );
  }

  String _label(DateRange r) => '${isoDay(r.start)} → ${isoDay(r.end.subtract(const Duration(days: 1)))}';

  Future<void> _export({required bool pdf}) async {
    final l = context.l;
    await guard(context, () async {
      final s = await ref.read(snapshotProvider.future);
      final range = DateRange.of(period, anchor, custom: custom);
      final r = ReportBuilder(s, l.tr, l.category).build(type, range, _label(range));
      final svc = ref.read(exportServiceProvider);
      final f = pdf ? await svc.reportPdf(r, userName: ref.read(sessionProvider)!.name, ar: l.ar) : await svc.reportExcel(r, ar: l.ar);
      if (!mounted) return;
      await shareOrSaveFile(context, f, text: r.title);
    });
  }
}
