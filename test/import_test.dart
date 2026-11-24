import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as xl;
import 'package:finance_pro/data/services/import_service.dart';
import 'package:finance_pro/domain/entities/transaction.dart';
import 'package:finance_pro/domain/repositories/repositories.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers.dart';

void main() {
  test('CSV import (Arabic headers): records rows, re-import skips them, bad rows are reported', () async {
    final e = await Env.create();
    final cash = await e.acc('Cash', 'YER', '100000');
    final svc = ImportService(e.accounts, e.txns);
    const csv = '\uFEFFالتاريخ,النوع,المبلغ,العملة,الحساب,التصنيف,العنوان\n'
        '2026-10-01,مصروف,٥٠٠٠,YER,Cash,food,غداء\n'
        '2026-10-02,income,20000,,cash,salary,راتب\n'
        '2026-10-03,expense,abc,YER,Cash,food,x\n'
        '2026-10-04,expense,10,YER,Nope,food,x\n';
    final rows = ImportService.parseCsv(Uint8List.fromList(utf8.encode(csv)));
    final r1 = await svc.importRows(e.uid, rows, (c) => c.name);
    expect(r1.imported, 2);
    expect(r1.errors.length, 2);
    expect(await e.balance(cash.id), d('115000'));
    final r2 = await svc.importRows(e.uid, rows, (c) => c.name);
    expect(r2.imported, 0);
    expect(r2.skipped, 2);
    expect(await e.balance(cash.id), d('115000'));
    final all = await e.txns.query(e.uid, const TxnQuery());
    expect(all.where((t) => t.type == TxnType.expense).single.amount, d('5000'));
  });

  test('Excel import', () async {
    final e = await Env.create();
    final bank = await e.acc('Bank', 'YER', '0');
    final book = xl.Excel.createExcel();
    final s = book[book.getDefaultSheet()!];
    s.appendRow([for (final h in ImportService.columns) xl.TextCellValue(h)]);
    s.appendRow([for (final v in ['2026-10-05', 'income', '7500.50', 'YER', 'Bank', 'salary', 'bonus', '']) xl.TextCellValue(v)]);
    final rows = ImportService.parseExcel(Uint8List.fromList(book.encode()!));
    final r = await ImportService(e.accounts, e.txns).importRows(e.uid, rows, (c) => c.name);
    expect(r.imported, 1);
    expect(await e.balance(bank.id), d('7500.5'));
  });
}
