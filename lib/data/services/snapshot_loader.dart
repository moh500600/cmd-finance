import 'package:decimal/decimal.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/snapshot.dart';
import '../repositories/ledger_engine.dart';

/// Loads a [FinanceSnapshot] from the repositories, converting every holding
/// to the base currency with the latest manual rate (missing -> null).
class SnapshotLoader {
  final LedgerEngine engine;
  final AccountRepository accounts;
  final TransactionRepository txns;
  final BudgetRepository budgets;
  final DebtRepository debts;
  final GoalRepository goals;
  final BillRepository bills;
  final AssetRepository assets;
  final InvestmentRepository investments;
  SnapshotLoader({required this.engine, required this.accounts, required this.txns, required this.budgets, required this.debts, required this.goals,
      required this.bills, required this.assets, required this.investments});

  Future<FinanceSnapshot> load(String uid, {DateTime? now}) async {
    final n = now ?? DateTime.now();
    final base = await engine.baseCurrency(engine.db, uid);
    Future<Decimal?> conv(Decimal amount, String ccy) async {
      try {
        return (await engine.convert(engine.db, uid, amount, ccy, base, n)).amount;
      } on MissingRateException {
        return null;
      }
    }

    final accs = await accounts.accounts(uid);
    final cats = await accounts.categories(uid, includeArchived: true);
    final gs = await goals.goals(uid);
    final ds = await debts.debts(uid);
    final as = await assets.assets(uid);
    final inv = await investments.investments(uid);
    return FinanceSnapshot(
      base: base,
      now: n,
      accounts: [for (final a in accs) Valued(a, a.balance, a.currency, await conv(a.balance, a.currency))],
      goals: [for (final g in gs) Valued(g, g.current, g.goal.currency, await conv(g.current, g.goal.currency))],
      debts: [for (final d in ds) Valued(d, d.remaining, d.debt.currency, await conv(d.remaining, d.debt.currency))],
      assets: [for (final a in as) Valued(a, a.currentValue, a.currency, await conv(a.currentValue, a.currency))],
      investments: [for (final i in inv) Valued(i, i.investment.currentValue, i.investment.currency, await conv(i.investment.currentValue, i.investment.currency))],
      txns: await txns.query(uid, const TxnQuery()),
      budgets: await budgets.statuses(uid, n),
      bills: await bills.bills(uid),
      categories: {for (final c in cats) c.id: c},
      recurring: await txns.recurringRules(uid),
    );
  }
}

extension CategoryLookup on FinanceSnapshot {
  Category? category(FinTransaction t) => t.categoryId == null ? null : categories[t.categoryId];
}
