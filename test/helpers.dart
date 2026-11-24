import 'package:decimal/decimal.dart';
import 'package:finance_pro/core/security/password_hasher.dart';
import 'package:finance_pro/data/db/app_database.dart';
import 'package:finance_pro/data/repositories/account_repository_impl.dart';
import 'package:finance_pro/data/repositories/auth_repository_impl.dart';
import 'package:finance_pro/data/repositories/currency_repository_impl.dart';
import 'package:finance_pro/data/repositories/holdings_repositories_impl.dart';
import 'package:finance_pro/data/repositories/ledger_engine.dart';
import 'package:finance_pro/data/repositories/planning_repositories_impl.dart';
import 'package:finance_pro/data/repositories/transaction_repository_impl.dart';
import 'package:finance_pro/data/services/snapshot_loader.dart';
import 'package:finance_pro/domain/entities/account.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Decimal d(String s) => Decimal.parse(s);

class Env {
  final Database db;
  final String uid;
  final LedgerEngine engine;
  final AuthRepositoryImpl auth;
  final CurrencyRepositoryImpl fx;
  final AccountRepositoryImpl accounts;
  final TransactionRepositoryImpl txns;
  final BudgetRepositoryImpl budgets;
  final DebtRepositoryImpl debts;
  final GoalRepositoryImpl goals;
  final BillRepositoryImpl bills;
  final AssetRepositoryImpl assets;
  final InvestmentRepositoryImpl investments;
  final BackupRepositoryImpl backup;
  Env(this.db, this.uid, this.engine)
      : auth = AuthRepositoryImpl(db, hasher: const PasswordHasher(iterations: 10)),
        fx = CurrencyRepositoryImpl(engine),
        accounts = AccountRepositoryImpl(engine),
        txns = TransactionRepositoryImpl(engine),
        budgets = BudgetRepositoryImpl(engine),
        debts = DebtRepositoryImpl(engine),
        goals = GoalRepositoryImpl(engine),
        bills = BillRepositoryImpl(engine),
        assets = AssetRepositoryImpl(engine),
        investments = InvestmentRepositoryImpl(engine),
        backup = BackupRepositoryImpl(engine);

  SnapshotLoader get loader => SnapshotLoader(engine: engine, accounts: accounts, txns: txns, budgets: budgets, debts: debts, goals: goals,
      bills: bills, assets: assets, investments: investments);

  Future<String> cat(String key) async => (await accounts.categories(uid)).firstWhere((c) => c.key == key).id;
  Future<Decimal> balance(String accountId) async => (await accounts.account(uid, accountId))!.balance;
  Future<Account> acc(String name, String ccy, String opening, {AccountType type = AccountType.cash}) =>
      accounts.createAccount(uid, name: name, type: type, currency: ccy, openingBalance: d(opening));

  static int _n = 0;
  static Future<Env> create({String base = 'YER'}) async {
    final email = 'user${_n++}@test.co';
    sqfliteFfiInit();
    final db = await AppDatabase.open(databaseFactoryFfiNoIsolate, 'file:mem$_n?mode=memory&cache=shared');
    final auth = AuthRepositoryImpl(db, hasher: const PasswordHasher(iterations: 10));
    final u = await auth.signUp(name: 'Mohammad', email: email, password: 'secret1', baseCurrency: base);
    return Env(db, u.user.id, LedgerEngine(db));
  }
}
