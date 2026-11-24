import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;

import '../../core/errors/app_exception.dart';
import '../../core/money/money.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/repositories.dart';

class ImportResult {
  final int imported;
  final int skipped; // already imported (same row hash)
  final List<String> errors; // "row N: reason"
  const ImportResult(this.imported, this.skipped, this.errors);
}

/// Imports income/expense rows from CSV or Excel.
/// Columns (header row, any order, Arabic or English names accepted):
/// date, type (income/expense|دخل/مصروف), amount, currency, account, category, title, notes.
/// Each row gets a deterministic idempotency key (hash of its content), so
/// importing the same file twice never duplicates anything.
class ImportService {
  final AccountRepository accounts;
  final TransactionRepository txns;
  ImportService(this.accounts, this.txns);

  static const columns = ['date', 'type', 'amount', 'currency', 'account', 'category', 'title', 'notes'];
  static const _aliases = {
    'التاريخ': 'date', 'النوع': 'type', 'المبلغ': 'amount', 'العملة': 'currency', 'الحساب': 'account', 'التصنيف': 'category', 'العنوان': 'title', 'ملاحظات': 'notes', 'الملاحظات': 'notes',
  };

  static List<List<String>> parseCsv(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    return Csv().decode(text).map((r) => r.map((c) => '${c ?? ''}'.trim()).toList()).toList();
  }

  static List<List<String>> parseExcel(Uint8List bytes) {
    final book = xl.Excel.decodeBytes(bytes);
    final sheet = book.tables.values.first;
    return [for (final r in sheet.rows) [for (final c in r) (c?.value?.toString() ?? '').trim()]];
  }

  Future<ImportResult> importRows(String uid, List<List<String>> rows, String Function(Category c) categoryLabel) async {
    if (rows.length < 2) throw const AppException('err_import_empty');
    final header = rows.first.map((h) => _aliases[h.trim()] ?? h.trim().toLowerCase()).toList();
    int col(String name) => header.indexOf(name);
    for (final req in ['date', 'type', 'amount', 'account']) {
      if (col(req) < 0) throw AppException('err_import_column', args: {'col': req});
    }
    final accs = await accounts.accounts(uid);
    final cats = await accounts.categories(uid);
    var ok = 0, skipped = 0;
    final errors = <String>[];
    for (var i = 1; i < rows.length; i++) {
      final r = rows[i];
      if (r.every((c) => c.isEmpty)) continue;
      String cell(String name) => col(name) >= 0 && col(name) < r.length ? r[col(name)] : '';
      try {
        final typeRaw = cell('type').toLowerCase();
        final type = const {'income', 'دخل', 'ايراد', 'إيراد'}.contains(typeRaw) ? TxnType.income
            : const {'expense', 'مصروف', 'مصروفات'}.contains(typeRaw) ? TxnType.expense : null;
        if (type == null) throw 'type';
        final amount = Money.tryParse(cell('amount'));
        if (amount == null || amount.sign <= 0) throw 'amount';
        final date = DateTime.tryParse(cell('date'));
        if (date == null) throw 'date';
        final accName = cell('account');
        final acc = accs.where((a) => a.name.toLowerCase() == accName.toLowerCase()).firstOrNull;
        if (acc == null) throw 'account "$accName"';
        final kind = type == TxnType.income ? CategoryKind.income : CategoryKind.expense;
        final catName = cell('category').toLowerCase();
        final catList = cats.where((c) => c.kind == kind);
        final cat = catList.where((c) => c.key == catName || c.name.toLowerCase() == catName || categoryLabel(c).toLowerCase() == catName).firstOrNull ??
            catList.firstWhere((c) => c.key == (type == TxnType.income ? 'other_income' : 'other_expense'));
        final currency = cell('currency').isEmpty ? acc.currency : cell('currency').toUpperCase();
        final key = 'import:${sha1.convert(utf8.encode(r.join('\u0001'))).toString().substring(0, 20)}';
        final existed = (await txns.query(uid, const TxnQuery(includeVoided: true))).any((t) => t.idempotencyKey == key);
        if (existed) {
          skipped++;
          continue;
        }
        await txns.record(uid, TxnDraft(type: type, accountId: acc.id, amount: amount, currency: currency, categoryId: cat.id, title: cell('title'),
            notes: cell('notes'), txnDate: date, idempotencyKey: key));
        ok++;
      } on AppException catch (e) {
        errors.add('${i + 1}: ${e.code}${e.args.isEmpty ? '' : ' ${e.args.values.join('→')}'}');
      } catch (e) {
        errors.add('${i + 1}: $e');
      }
    }
    return ImportResult(ok, skipped, errors);
  }
}
