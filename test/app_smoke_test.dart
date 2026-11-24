// UI smoke test: boots the real app on an in-memory database, seeds a
// realistic multi-currency ledger through the real repositories, and renders
// every main screen in Arabic and English. With SCREENSHOTS=1 it writes PNGs
// to build/screens/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:decimal/decimal.dart';
import 'package:finance_pro/app.dart';
import 'package:finance_pro/core/security/password_hasher.dart';
import 'package:finance_pro/core/utils/dates.dart';
import 'package:finance_pro/data/db/app_database.dart';
import 'package:finance_pro/data/repositories/auth_repository_impl.dart';
import 'package:finance_pro/domain/entities/account.dart';
import 'package:finance_pro/domain/entities/holdings.dart';
import 'package:finance_pro/domain/entities/planning.dart';
import 'package:finance_pro/domain/entities/transaction.dart';
import 'package:finance_pro/presentation/providers/providers.dart';
import 'package:finance_pro/presentation/screens/accounts/accounts_screen.dart';
import 'package:finance_pro/presentation/screens/assistant/assistant_screen.dart';
import 'package:finance_pro/presentation/screens/more/more_screen.dart';
import 'package:finance_pro/presentation/screens/planning/debts_screen.dart';
import 'package:finance_pro/presentation/screens/planning/savings_screen.dart';
import 'package:finance_pro/presentation/screens/settings/settings_screen.dart';
import 'package:finance_pro/presentation/screens/transactions/transaction_detail_screen.dart';
import 'package:finance_pro/presentation/screens/transactions/transaction_form_screen.dart';
import 'package:finance_pro/presentation/screens/transactions/transfer_form_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final shots = Platform.environment['SCREENSHOTS'] == '1';
final _boundary = GlobalKey();
Decimal d(String s) => Decimal.parse(s);

Future<void> _loadFonts() async {
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final tajawal = FontLoader('Tajawal');
  for (final w in ['Regular', 'Medium', 'Bold']) {
    tajawal.addFont(Future.value(ByteData.sublistView(File('assets/fonts/Tajawal-$w.ttf').readAsBytesSync())));
  }
  await tajawal.load();
  final icons = File('$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    final l = FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await l.load();
  }
}

final _errs = <String>[];
void Function(FlutterErrorDetails)? _origOnError;
Future<void> _shot(WidgetTester tester, String name) async {
  await tester.pump(const Duration(milliseconds: 900));
  if (_errs.isNotEmpty) {
    final all = _errs.join('\n----\n');
    _errs.clear();
    FlutterError.onError = _origOnError;
    fail('UI errors on/before $name:\n$all');
  }
  if (!shots) return;
  await tester.runAsync(() async {
    final b = _boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final img = await b.toImage(pixelRatio: 2.5);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    final f = File('build/screens/$name.png')..createSync(recursive: true);
    f.writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Future<void> _seed(ProviderContainer c, String uid, bool ar) async {
  final fx = c.read(currencyRepositoryProvider), accs = c.read(accountRepositoryProvider), tx = c.read(transactionRepositoryProvider);
  final now = DateTime.now();
  final m0 = DateTime(now.year, now.month - 4, 1);
  await fx.addRate(uid, from: 'SAR', to: 'YER', rate: d('140'), source: ar ? 'صرافة الكريمي' : 'Kuraimi exchange', date: m0);
  await fx.addRate(uid, from: 'USD', to: 'YER', rate: d('530'), source: ar ? 'صرافة الكريمي' : 'Kuraimi exchange', date: m0);
  await fx.addRate(uid, from: 'USD', to: 'YER', rate: d('535'), source: ar ? 'بنك التضامن' : 'Tadhamon Bank', date: DateTime(now.year, now.month, 1));
  final cash = await accs.createAccount(uid, name: ar ? 'الصندوق النقدي' : 'Cash box', type: AccountType.cash, currency: 'YER', openingBalance: d('950000'), color: 0xFF0F766E);
  final bank = await accs.createAccount(uid, name: ar ? 'بنك الكريمي' : 'Kuraimi Bank', type: AccountType.bank, currency: 'YER', openingBalance: d('1200000'), color: 0xFF2563EB,
      lowBalanceAlert: d('100000'));
  final sar = await accs.createAccount(uid, name: ar ? 'حساب بالريال السعودي' : 'SAR account', type: AccountType.bank, currency: 'SAR', openingBalance: d('3500'), color: 0xFF16A34A);
  final usd = await accs.createAccount(uid, name: ar ? 'محفظة جيب' : 'Jaib wallet', type: AccountType.ewallet, currency: 'USD', openingBalance: d('820'), color: 0xFF7C3AED);
  final cats = {for (final x in await accs.categories(uid)) x.key: x.id};
  var k = 0;
  Future<FinTransaction> rec(TxnType t, String acc, String amt, String ccy, String cat, String title, DateTime date) => tx.record(uid,
      TxnDraft(type: t, accountId: acc, amount: d(amt), currency: ccy, categoryId: cats[cat], title: title, txnDate: date, idempotencyKey: 'seed${k++}'));
  for (var i = 3; i >= 0; i--) {
    final m = DateTime(now.year, now.month - i, 1);
    DateTime day(int dd) => DateTime(m.year, m.month, i == 0 ? (dd > now.day ? now.day : dd) : dd, 10);
    await rec(TxnType.income, bank.id, '${650000 + i * 15000}', 'YER', 'salary', ar ? 'راتب الشهر' : 'Monthly salary', day(1));
    await rec(TxnType.income, usd.id, '${180 + i * 40}', 'USD', 'freelance', ar ? 'مشروع تطبيق' : 'App project', day(8));
    await rec(TxnType.expense, cash.id, '${85000 + i * 6000}', 'YER', 'food', ar ? 'مقاضي البيت' : 'Groceries', day(3));
    await rec(TxnType.expense, cash.id, '${30000 + i * 2000}', 'YER', 'transport', ar ? 'بترول ومواصلات' : 'Fuel & transport', day(6));
    await rec(TxnType.expense, bank.id, '45000', 'YER', 'internet', ar ? 'اشتراك الإنترنت' : 'Internet plan', day(2));
    await rec(TxnType.expense, sar.id, '${250 + i * 20}', 'SAR', 'shopping', ar ? 'ملابس' : 'Clothes', day(12));
    await rec(TxnType.expense, cash.id, '${12000 + i * 1500}', 'YER', 'health', ar ? 'صيدلية' : 'Pharmacy', day(14));
  }
  final lunch = await rec(TxnType.expense, cash.id, '5000', 'YER', 'food', ar ? 'غداء' : 'Lunch', now.subtract(const Duration(hours: 2)));
  await tx.transfer(uid, TransferDraft(fromAccountId: sar.id, toAccountId: bank.id, amount: d('500'), toAmount: d('69500'), fee: d('5'), txnDate: now.subtract(const Duration(days: 1)),
      notes: ar ? 'تحويل للبنك' : 'To bank', idempotencyKey: 'seedT'));
  await tx.saveRecurring(uid, template: TxnDraft(type: TxnType.expense, accountId: bank.id, amount: d('120000'), currency: 'YER', categoryId: cats['housing'],
      title: ar ? 'إيجار الشقة' : 'Apartment rent', txnDate: now, idempotencyKey: 'rt'), frequency: Frequency.monthly, firstDate: DateTime(now.year, now.month + 1, 1));
  final b = c.read(budgetRepositoryProvider);
  await b.saveBudget(uid, name: ar ? 'الطعام' : 'Food', categoryId: cats['food'], period: BudgetPeriod.monthly, limit: d('100000'));
  await b.saveBudget(uid, name: ar ? 'المواصلات' : 'Transport', categoryId: cats['transport'], period: BudgetPeriod.monthly, limit: d('60000'));
  await b.saveBudget(uid, name: ar ? 'الميزانية العامة' : 'Overall', period: BudgetPeriod.monthly, limit: d('600000'));
  final debts = c.read(debtRepositoryProvider);
  final dbt = await debts.createDebt(uid, direction: DebtDirection.iOwe, party: ar ? 'أحمد علي' : 'Ahmed Ali', principal: d('300000'), currency: 'YER', interestRate: d('0'),
      startDate: DateTime(now.year, now.month - 2, 5), installments: 6, notes: ar ? 'سلفة سيارة' : 'Car loan', idempotencyKey: 'sd1');
  await debts.addPayment(uid, dbt.id, accountId: bank.id, amount: d('50000'), date: DateTime(now.year, now.month - 1, 5), idempotencyKey: 'sd1p');
  await debts.createDebt(uid, direction: DebtDirection.owedToMe, party: ar ? 'خالد سالم' : 'Khaled Salem', principal: d('400'), currency: 'USD', interestRate: d('0'),
      startDate: DateTime(now.year, now.month - 1, 10), dueDate: now.add(const Duration(days: 20)), idempotencyKey: 'sd2');
  final g = c.read(goalRepositoryProvider);
  final goal = await g.saveGoal(uid, name: ar ? 'شراء سيارة' : 'Buy a car', target: d('5000'), currency: 'USD', initialAmount: d('1200'), deadline: DateTime(now.year + 1, now.month, 1), color: 0xFF0EA5E9);
  await g.move(uid, goal.id, deposit: true, accountId: usd.id, amount: d('300'), date: now.subtract(const Duration(days: 10)), idempotencyKey: 'g1');
  await g.saveGoal(uid, name: ar ? 'صندوق الطوارئ' : 'Emergency fund', target: d('1500000'), currency: 'YER', initialAmount: d('900000'), color: 0xFFF59E0B);
  final bills = c.read(billRepositoryProvider);
  await bills.saveBill(uid, name: ar ? 'فاتورة الكهرباء' : 'Electricity bill', kind: BillKind.electricity, amount: d('28000'), currency: 'YER', dueDate: now.add(const Duration(days: 2)), accountId: cash.id);
  await bills.saveBill(uid, name: ar ? 'اشتراك يمن نت' : 'YemenNet plan', kind: BillKind.internet, amount: d('45000'), currency: 'YER', dueDate: now.subtract(const Duration(days: 1)));
  await bills.saveBill(uid, name: ar ? 'الإيجار' : 'Rent', kind: BillKind.rent, amount: d('120000'), currency: 'YER', dueDate: now.add(const Duration(days: 12)));
  final assets = c.read(assetRepositoryProvider);
  final car = await assets.saveAsset(uid, name: ar ? 'سيارة هايلكس' : 'Hilux truck', type: AssetType.vehicle, purchaseValue: d('9000'), currentValue: d('8200'), currency: 'USD',
      purchaseDate: DateTime(now.year - 2, 3, 1));
  await assets.addValue(uid, car.id, d('7900'), now.subtract(const Duration(days: 5)));
  await assets.saveAsset(uid, name: ar ? 'ذهب 50 جرام' : 'Gold 50 g', type: AssetType.gold, purchaseValue: d('3100'), currentValue: d('3900'), currency: 'USD');
  final inv = c.read(investmentRepositoryProvider);
  final shop = await inv.saveInvestment(uid, name: ar ? 'شراكة متجر' : 'Shop partnership', type: InvestmentType.business, currency: 'YER', startDate: DateTime(now.year, 1, 1),
      capital: d('2000000'), currentValue: d('2350000'));
  await inv.addEntry(uid, shop.id, InvestmentEntryKind.dividend, d('150000'), now.subtract(const Duration(days: 20)));
  await inv.saveInvestment(uid, name: ar ? 'محفظة أسهم' : 'Stock portfolio', type: InvestmentType.stocks, currency: 'USD', startDate: DateTime(now.year, 2, 1),
      capital: d('1500'), currentValue: d('1380'));
  c.read(revisionProvider.notifier).bump();
  _lunchId = lunch.id;
  _debtId = dbt.id;
  _goalId = goal.id;
  _bankId = bank.id;
}

String _lunchId = '', _debtId = '', _goalId = '', _bankId = '';

void main() {
  sqfliteFfiInit();

  setUpAll(() async {
    await initializeDateFormatting('ar');
    await initializeDateFormatting('en');
    await _loadFonts(); // real Tajawal metrics, so overflow checks mean something
  });

  for (final lang in ['ar', 'en']) {
    testWidgets('app boots, signs in and renders all screens ($lang)', (tester) async {
      if (shots) debugDisableShadows = false;
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.7;
      addTearDown(tester.view.reset);
      final ar = lang == 'ar';
            _origOnError = FlutterError.onError;
      FlutterError.onError = (d) => _errs.add(d.toString());

      SharedPreferences.setMockInitialValues({'lang': lang, 'theme': ThemeMode.light.index});
      final prefs = await SharedPreferences.getInstance();
      late Database db;
      late String uid;
      await tester.runAsync(() async {
        db = await AppDatabase.open(databaseFactoryFfiNoIsolate, 'file:smoke_$lang?mode=memory&cache=shared');
        final auth = AuthRepositoryImpl(db, hasher: const PasswordHasher(iterations: 10));
        uid = (await auth.signUp(name: ar ? 'محمد نضال' : 'Mohammad Nidal', email: 'm$lang@x.com', password: 'secret123', baseCurrency: 'YER')).user.id;
      });

      final container = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPrefsProvider.overrideWithValue(prefs),
      ]);
      addTearDown(container.dispose);

      await tester.pumpWidget(UncontrolledProviderScope(container: container, child: RepaintBoundary(key: _boundary, child: const FinanceProApp())));
      await tester.pump();
      expect(find.byType(TextFormField), findsWidgets); // login screen
      await _shot(tester, '${lang}_00_login');

      await tester.runAsync(() async {
        final user = await AuthRepositoryImpl(db).getUser(uid);
        await container.read(sessionProvider.notifier).signIn(user!);
        await _seed(container, uid, ar);
      });

      Future<void> settle([int n = 8]) async {
        for (var i = 0; i < n; i++) {
          await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 40)));
          await tester.pump(const Duration(milliseconds: 120));
        }
      }

      await settle(10);
      expect(find.byType(NavigationBar), findsOneWidget);
      await _shot(tester, '${lang}_01_dashboard');

      final navLabels = ar ? ['العمليات', 'الحسابات', 'التقارير', 'المزيد'] : ['Transactions', 'Accounts', 'Reports', 'More'];
      for (final (i, label) in navLabels.indexed) {
        await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
        await settle();
        await _shot(tester, '${lang}_0${i + 2}_${['transactions', 'accounts', 'reports', 'more'][i]}');
      }

      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      Future<void> open(Widget w, String name) async {
        nav.push(MaterialPageRoute(builder: (_) => w));
        await settle();
        await _shot(tester, name);
        final ex = tester.takeException();
        if (ex is FlutterError) debugPrint(ex.toStringDeep());
        expect(ex, isNull, reason: name);
        nav.pop();
        await settle(3);
      }

      await open(const TransactionFormScreen(type: TxnType.expense), '${lang}_06_add_expense');
      await open(const TransferFormScreen(), '${lang}_07_transfer');
      await open(TransactionDetailScreen(id: _lunchId), '${lang}_08_txn_detail');
      await open(AccountDetailScreen(id: _bankId), '${lang}_09_account_detail');
      await open(routeTarget('budgets'), '${lang}_10_budgets');
      await open(routeTarget('debts'), '${lang}_11_debts');
      await open(DebtDetailScreen(id: _debtId), '${lang}_12_debt_detail');
      await open(routeTarget('savings'), '${lang}_13_savings');
      await open(GoalDetailScreen(id: _goalId), '${lang}_14_goal_detail');
      await open(routeTarget('bills'), '${lang}_15_bills');
      await open(routeTarget('assets'), '${lang}_16_assets');
      await open(routeTarget('investments'), '${lang}_17_investments');
      await open(routeTarget('currencies'), '${lang}_18_currencies');
      await open(routeTarget('recurring'), '${lang}_19_recurring');
      await open(routeTarget('categories'), '${lang}_20_categories');
      await open(const SettingsScreen(), '${lang}_21_settings');
      await open(const SharingScreen(), '${lang}_22_sharing');
      await open(const NotificationSettingsScreen(), '${lang}_23_notifications');
      await open(const DataScreen(), '${lang}_24_backup');

      // Assistant: a real quick-add and a real question through the rule-based engine.
      nav.push(MaterialPageRoute(builder: (_) => const AssistantScreen()));
      await settle();
      await tester.enterText(find.byType(TextField).last, ar ? 'كم صرفت هذا الشهر؟' : 'how much did I spend this month?');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await settle();
      await tester.enterText(find.byType(TextField).last, ar ? 'صرفت 5000 ريال يمني غداء' : 'spent 20 USD on lunch');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await settle();
      expect(find.byType(FilledButton), findsWidgets); // "review & confirm"
      await _shot(tester, '${lang}_25_assistant');
      nav.pop();
      await settle(3);

      // Dark theme dashboard
      await tester.runAsync(() => container.read(settingsProvider.notifier).update((s) => s.copyWith(theme: ThemeMode.dark)));
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(ar ? 'الرئيسية' : 'Home')));
      await settle();
      await _shot(tester, '${lang}_26_dashboard_dark');

      expect(tester.takeException(), isNull);
      FlutterError.onError = _origOnError;
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => db.close());
      debugDisableShadows = true;
    }, timeout: const Timeout(Duration(minutes: 4)));
  }
}
