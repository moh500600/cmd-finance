import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';

// Charts render Decimal values converted to double for drawing only; every
// number shown as text comes from Decimal formatting.

double _d(Decimal x) => x.toDouble();

class ChartCard extends StatelessWidget {
  final String title;
  final Widget child;
  final double height;
  final Widget? legend;
  const ChartCard({super.key, required this.title, required this.child, this.height = 190, this.legend});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (legend != null) Padding(padding: const EdgeInsets.only(top: 6), child: legend),
            const SizedBox(height: 12),
            SizedBox(height: height, child: Directionality(textDirection: TextDirection.ltr, child: child)),
          ]),
        ),
      );
}

class Legend extends StatelessWidget {
  final List<(String, Color)> items;
  const Legend(this.items, {super.key});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 12, runSpacing: 4, children: [
        for (final i in items)
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 10, height: 10, decoration: BoxDecoration(color: i.$2, borderRadius: BorderRadius.circular(3))),
            const SizedBox(width: 4),
            Text(i.$1, style: const TextStyle(fontSize: 11)),
          ]),
      ]);
}

FlTitlesData _titles(List<String> labels, {bool left = true}) => FlTitlesData(
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      leftTitles: AxisTitles(
          sideTitles: SideTitles(
              showTitles: left,
              reservedSize: 40,
              getTitlesWidget: (v, meta) => Text(Money.compact(Decimal.parse(v.toStringAsFixed(0))), style: const TextStyle(fontSize: 9)))),
      bottomTitles: AxisTitles(
          sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              getTitlesWidget: (v, meta) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length || v != i.toDouble()) return const SizedBox.shrink();
                return Padding(padding: const EdgeInsets.only(top: 4), child: Text(labels[i], style: const TextStyle(fontSize: 10)));
              })),
    );

FlGridData _grid(BuildContext context) => FlGridData(
    drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.3), strokeWidth: 1));

/// Grouped bars (e.g. income vs expense per month).
class GroupedBars extends StatelessWidget {
  final List<String> labels;
  final List<List<Decimal>> series; // series[s][i]
  final List<Color> colors;
  const GroupedBars({super.key, required this.labels, required this.series, required this.colors});
  @override
  Widget build(BuildContext context) => BarChart(BarChartData(
        gridData: _grid(context),
        borderData: FlBorderData(show: false),
        titlesData: _titles(labels),
        barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(Money.format(series[ri][gi]), const TextStyle(color: Colors.white, fontSize: 11)))),
        barGroups: [
          for (var i = 0; i < labels.length; i++)
            BarChartGroupData(x: i, barsSpace: 3, barRods: [
              for (var s = 0; s < series.length; s++)
                BarChartRodData(toY: _d(series[s][i]), color: colors[s], width: series.length > 1 ? 8 : 14, borderRadius: BorderRadius.circular(4)),
            ]),
        ],
      ));
}

/// Signed bars (net cash flow): green positive, red negative.
class SignedBars extends StatelessWidget {
  final List<String> labels;
  final List<Decimal> values;
  const SignedBars({super.key, required this.labels, required this.values});
  @override
  Widget build(BuildContext context) => BarChart(BarChartData(
        gridData: _grid(context),
        borderData: FlBorderData(show: false),
        titlesData: _titles(labels),
        barTouchData: BarTouchData(touchTooltipData: BarTouchTooltipData(getTooltipItem: (g, gi, rod, ri) => BarTooltipItem(Money.format(values[gi]), const TextStyle(color: Colors.white, fontSize: 11)))),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(toY: _d(values[i]), color: values[i].sign < 0 ? AppColors.expense : AppColors.income, width: 14, borderRadius: BorderRadius.circular(4)),
            ]),
        ],
      ));
}

class TrendLine extends StatelessWidget {
  final List<String> labels;
  final List<Decimal> values;
  final Color color;
  const TrendLine({super.key, required this.labels, required this.values, this.color = AppColors.primary});
  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return LineChart(LineChartData(
      gridData: _grid(context),
      borderData: FlBorderData(show: false),
      titlesData: _titles(labels),
      lineTouchData: LineTouchData(touchTooltipData: LineTouchTooltipData(getTooltipItems: (spots) => [for (final s in spots) LineTooltipItem(Money.format(values[s.x.toInt()]), const TextStyle(color: Colors.white, fontSize: 11))])),
      lineBarsData: [
        LineChartBarData(
          spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), _d(values[i]))],
          isCurved: true,
          preventCurveOverShooting: true,
          color: color,
          barWidth: 3,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(show: true, gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)])),
        ),
      ],
    ));
  }
}

class Donut extends StatelessWidget {
  final List<(String, Decimal)> data;
  const Donut({super.key, required this.data});
  @override
  Widget build(BuildContext context) {
    final total = Money.sum(data.map((e) => e.$2));
    if (total.sign == 0) return const SizedBox.shrink();
    return Row(children: [
      Expanded(
        child: PieChart(PieChartData(
          sectionsSpace: 2,
          centerSpaceRadius: 38,
          sections: [
            for (var i = 0; i < data.length; i++)
              PieChartSectionData(
                value: _d(data[i].$2),
                color: AppColors.chart[i % AppColors.chart.length],
                radius: 34,
                title: '${Money.percent(data[i].$2, total).round()}%',
                titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700),
                showTitle: Money.percent(data[i].$2, total) >= Decimal.fromInt(6),
              ),
          ],
        )),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (var i = 0; i < data.length && i < 7; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.chart[i % AppColors.chart.length], borderRadius: BorderRadius.circular(3))),
                const SizedBox(width: 6),
                Expanded(child: Text(data[i].$1, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
              ]),
            ),
        ]),
      ),
    ]);
  }
}
