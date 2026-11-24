import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../../domain/services/report_builder.dart';
import 'file_storage_service.dart';

/// PDF (Arabic font, RTL) and Excel/CSV exports, written to app documents.
class ExportService {
  final FileStorageService storage;
  ExportService(this.storage);

  String _stamp() => DateFormat('yyyyMMdd_HHmm').format(DateTime.now());

  Future<File> reportPdf(ReportData r, {required String userName, required bool ar}) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Bold.ttf'));
    final dir = ar ? pw.TextDirection.rtl : pw.TextDirection.ltr;
    final accent = PdfColor.fromInt(0xFF0F766E);
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular, bold: bold));
    final maxChart = r.chart.isEmpty ? Money.zero : r.chart.map((e) => e.$2.abs()).reduce((a, b) => a > b ? a : b);
    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      textDirection: dir,
      margin: const pw.EdgeInsets.all(28),
      build: (ctx) => [
        pw.Text('${ar ? 'CMD Finance' : 'CMD Finance'} — ${r.title}', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: accent), textDirection: dir),
        pw.SizedBox(height: 4),
        pw.Text('$userName • ${r.period} • ${DateFormat('yyyy/MM/dd HH:mm').format(DateTime.now())}', style: const pw.TextStyle(color: PdfColors.grey700), textDirection: dir),
        pw.Divider(),
        pw.Wrap(spacing: 8, runSpacing: 8, children: [
          for (final s in r.summary)
            pw.Container(
              width: 160,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300), borderRadius: pw.BorderRadius.circular(6)),
              child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.Text(s.$1, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700), textDirection: dir),
                pw.Text(s.$2, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: accent), textDirection: dir),
              ]),
            ),
        ]),
        for (final w in r.warnings) pw.Padding(padding: const pw.EdgeInsets.only(top: 6), child: pw.Text('⚠ $w', style: const pw.TextStyle(color: PdfColors.orange800), textDirection: dir)),
        if (r.chart.isNotEmpty && maxChart.sign > 0) ...[
          pw.SizedBox(height: 12),
          for (final c in r.chart.take(12))
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(children: [
                pw.SizedBox(width: 110, child: pw.Text(c.$1, style: const pw.TextStyle(fontSize: 9), textDirection: dir, maxLines: 1)),
                pw.Expanded(
                  child: pw.Align(
                    alignment: ar ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
                    child: pw.Container(height: 9, width: 4 + 300 * (Money.div(c.$2.abs(), maxChart, scale: 4).toDouble()), color: c.$2.sign < 0 ? PdfColors.red300 : accent),
                  ),
                ),
              ]),
            ),
        ],
        for (final t in r.tables) ...[
          pw.SizedBox(height: 14),
          pw.Text(t.title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 13), textDirection: dir),
          pw.SizedBox(height: 6),
          if (t.rows.isEmpty)
            pw.Text(ar ? 'لا توجد بيانات' : 'No data', textDirection: dir)
          else
            pw.TableHelper.fromTextArray(
              headerDirection: dir,
              tableDirection: dir,
              cellAlignment: ar ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.white, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration: pw.BoxDecoration(color: accent),
              headers: t.headers,
              data: t.rows,
            ),
        ],
      ],
    ));
    return storage.writeExport('finance_pro_${r.type.name}_${_stamp()}.pdf', await doc.save());
  }

  Future<File> reportExcel(ReportData r, {required bool ar}) async {
    final book = xl.Excel.createExcel();
    final summary = book['Summary'];
    summary.isRTL = ar;
    summary.appendRow([xl.TextCellValue(r.title), xl.TextCellValue(r.period)]);
    for (final s in r.summary) {
      summary.appendRow([xl.TextCellValue(s.$1), xl.TextCellValue(s.$2)]);
    }
    for (final w in r.warnings) {
      summary.appendRow([xl.TextCellValue('⚠'), xl.TextCellValue(w)]);
    }
    var i = 1;
    for (final t in r.tables) {
      final name = 'T${i++} ${t.title}'.replaceAll(RegExp(r'[\[\]\*\?/\\:]'), ' ');
      final sh = book[name.length > 30 ? name.substring(0, 30) : name];
      sh.isRTL = ar;
      sh.appendRow([for (final h in t.headers) xl.TextCellValue(h)]);
      for (final row in t.rows) {
        sh.appendRow([for (final c in row) xl.TextCellValue(c)]);
      }
    }
    book.delete('Sheet1');
    return storage.writeExport('finance_pro_${r.type.name}_${_stamp()}.xlsx', book.encode()!);
  }

  /// Raw rows (first = headers) to CSV or Excel. Amounts are decimal strings.
  Future<File> table(String baseName, List<List<String>> rows, {required bool excel, bool rtl = false}) async {
    if (!excel) {
      final csvText = Csv(lineDelimiter: '\n').encode(rows);
      return storage.writeExport('${baseName}_${_stamp()}.csv', utf8.encode('\uFEFF$csvText'));
    }
    final book = xl.Excel.createExcel();
    final sh = book['Data'];
    sh.isRTL = rtl;
    for (final r in rows) {
      sh.appendRow([for (final c in r) xl.TextCellValue(c)]);
    }
    book.delete('Sheet1');
    return storage.writeExport('${baseName}_${_stamp()}.xlsx', book.encode()!);
  }

  Future<File> backupJson(String json) => storage.writeExport('finance_pro_backup_${isoDay(DateTime.now())}_${_stamp()}.json', utf8.encode(json));
}
