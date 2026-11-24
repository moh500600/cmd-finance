import 'dart:io';

import 'package:finance_pro/core/l10n/strings.dart';
import 'package:finance_pro/core/utils/dates.dart';
import 'package:finance_pro/domain/entities/account.dart';
import 'package:finance_pro/domain/entities/holdings.dart';
import 'package:finance_pro/domain/entities/planning.dart';
import 'package:finance_pro/domain/entities/transaction.dart';
import 'package:finance_pro/domain/services/report_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every literal key used in lib/ exists in Arabic and English', () {
    final used = <String>{};
    final re = RegExp(r"\btr\(\s*'([^'$]+)'");
    final ex = RegExp(r"AppException\('([a-z_]+)'");
    final tern = RegExp(r"\btr\([^;']*?\?\s*'([^'$]+)'\s*:\s*'([^'$]+)'");
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final s = f.readAsStringSync();
      for (final m in re.allMatches(s)) {
        used.add(m.group(1)!);
      }
      for (final m in ex.allMatches(s)) {
        used.add(m.group(1)!);
      }
      for (final m in tern.allMatches(s)) {
        used
          ..add(m.group(1)!)
          ..add(m.group(2)!);
      }
    }
    final missing = used.where((k) => !kStrings.containsKey(k)).toList()..sort();
    expect(missing, isEmpty, reason: 'missing keys: $missing');
    expect(used.length, greaterThan(400));
  });

  test('keys built from enums exist', () {
    final dyn = [
      for (final t in TxnType.values) 'txn_${t.name}',
      for (final t in AccountType.values) 'acct_${t.name}',
      for (final t in AssetType.values) 'asset_${t.name}',
      for (final t in InvestmentType.values) 'inv_${t.name}',
      for (final t in InvestmentEntryKind.values) 'entry_${t.name}',
      for (final t in BillKind.values) 'bill_${t.name}',
      for (final t in Frequency.values) 'freq_${t.name}',
      for (final t in PeriodKind.values) 'period_${t.name}',
      for (final t in ReportType.values) 'report_${t.name}',
      for (final t in BudgetPeriod.values) t.name,
      for (final t in DebtDirection.values) t.name,
      for (final t in ['create', 'update', 'void']) 'audit_$t',
      for (final k in ['bill', 'bill_today', 'debt', 'receivable', 'goal']) ...['notif_${k}_title', 'notif_${k}_body'],
      for (final c in ['YER', 'SAR', 'USD', 'EUR']) 'ccy_$c',
      for (final k in ['salary', 'business', 'sales', 'freelance', 'rent_income', 'investments', 'gifts', 'other_income', 'food', 'transport', 'housing', 'utilities',
          'internet', 'health', 'education', 'shopping', 'entertainment', 'travel', 'bills', 'fees', 'other_expense']) 'cat_$k',
      for (final k in ['assistant', 'transfer', 'budgets', 'debts', 'savings', 'bills', 'assets', 'investments', 'currencies', 'recurring', 'categories', 'settings']) 'menu_$k',
      for (final k in ['system', 'light', 'dark']) 'theme_$k',
      for (final k in ['large_expense', 'low_balance', 'budget', 'goals', 'bills', 'debts', 'daily', 'weekly', 'monthly']) 'n_$k',
    ];
    final missing = dyn.where((k) => !kStrings.containsKey(k)).toList();
    expect(missing, isEmpty, reason: '$missing');
  });

  test('Arabic and English carry the same placeholders and are not empty', () {
    final ph = RegExp(r'\{(\w+)\}');
    kStrings.forEach((k, v) {
      expect(v.length, 2, reason: k);
      expect(v[0].trim(), isNotEmpty, reason: k);
      expect(v[1].trim(), isNotEmpty, reason: k);
      final a = ph.allMatches(v[0]).map((m) => m.group(1)).toSet(), e = ph.allMatches(v[1]).map((m) => m.group(1)).toSet();
      expect(a, e, reason: 'placeholders differ for $k');
    });
  });
}
