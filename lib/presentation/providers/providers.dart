import 'dart:async';
import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' show DateTimeComponents;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../core/l10n/l10n.dart';
import '../../core/money/money.dart';
import '../../core/utils/dates.dart';
import '../../data/repositories/account_repository_impl.dart';
import '../../data/repositories/auth_repository_impl.dart';
import '../../data/repositories/currency_repository_impl.dart';
import '../../data/repositories/holdings_repositories_impl.dart';
import '../../data/repositories/ledger_engine.dart';
import '../../data/repositories/planning_repositories_impl.dart';
import '../../data/repositories/transaction_repository_impl.dart';
import '../../data/services/export_service.dart';
import '../../data/services/file_storage_service.dart';
import '../../data/services/import_service.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/settings_repository.dart';
import '../../data/services/snapshot_loader.dart';
import '../../domain/assistant/assistant_engine.dart';
import '../../domain/assistant/rule_based_assistant.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/currency.dart';
import '../../domain/entities/holdings.dart';
import '../../domain/entities/planning.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/repositories.dart';
import '../../domain/services/alerts.dart';
import '../../domain/services/snapshot.dart';

// ------------------------------------------------------------------ infra
final databaseProvider = Provider<Database>((ref) => throw UnimplementedError('override in main'));
final sharedPrefsProvider = Provider<SharedPreferences>((ref) => throw UnimplementedError('override in main'));
final initialUserProvider = Provider<AppUser?>((ref) => null);

final engineProvider = Provider((ref) => LedgerEngine(ref.watch(databaseProvider)));
final settingsRepositoryProvider = Provider((ref) => SettingsRepository(ref.watch(sharedPrefsProvider)));
final authRepositoryProvider = Provider<AuthRepository>((ref) => AuthRepositoryImpl(ref.watch(databaseProvider)));
final currencyRepositoryProvider = Provider<CurrencyRepository>((ref) => CurrencyRepositoryImpl(ref.watch(engineProvider)));
final accountRepositoryProvider = Provider<AccountRepository>((ref) => AccountRepositoryImpl(ref.watch(engineProvider)));
final transactionRepositoryProvider = Provider<TransactionRepository>((ref) => TransactionRepositoryImpl(ref.watch(engineProvider)));
final budgetRepositoryProvider = Provider<BudgetRepository>((ref) => BudgetRepositoryImpl(ref.watch(engineProvider)));
final debtRepositoryProvider = Provider<DebtRepository>((ref) => DebtRepositoryImpl(ref.watch(engineProvider)));
final goalRepositoryProvider = Provider<GoalRepository>((ref) => GoalRepositoryImpl(ref.watch(engineProvider)));
final billRepositoryProvider = Provider<BillRepository>((ref) => BillRepositoryImpl(ref.watch(engineProvider)));
final assetRepositoryProvider = Provider<AssetRepository>((ref) => AssetRepositoryImpl(ref.watch(engineProvider)));
final investmentRepositoryProvider = Provider<InvestmentRepository>((ref) => InvestmentRepositoryImpl(ref.watch(engineProvider)));
final backupRepositoryProvider = Provider<BackupRepository>((ref) => BackupRepositoryImpl(ref.watch(engineProvider)));
final fileStorageProvider = Provider((ref) => FileStorageService());
final exportServiceProvider = Provider((ref) => ExportService(ref.watch(fileStorageProvider)));
final importServiceProvider = Provider((ref) => ImportService(ref.watch(accountRepositoryProvider), ref.watch(transactionRepositoryProvider)));
final notificationServiceProvider = Provider((ref) => NotificationService());

/// Swap for an LLM-backed engine later (no keys are shipped).
final assistantEngineProvider = Provider<AssistantEngine>((ref) => RuleBasedAssistant());

final snapshotLoaderProvider = Provider((ref) => SnapshotLoader(
      engine: ref.watch(engineProvider), accounts: ref.watch(accountRepositoryProvider), txns: ref.watch(transactionRepositoryProvider),
      budgets: ref.watch(budgetRepositoryProvider), debts: ref.watch(debtRepositoryProvider), goals: ref.watch(goalRepositoryProvider),
      bills: ref.watch(billRepositoryProvider), assets: ref.watch(assetRepositoryProvider), investments: ref.watch(investmentRepositoryProvider),
    ));

// ------------------------------------------------------------------ settings & session
class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(settingsRepositoryProvider).load();
  Future<void> update(AppSettings Function(AppSettings) change) async {
    state = change(state);
    await ref.read(settingsRepositoryProvider).save(state);
  }

  void reload() => state = ref.read(settingsRepositoryProvider).load();
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
final l10nProvider = Provider((ref) => L10n(ref.watch(settingsProvider.select((s) => s.lang))));

class SessionNotifier extends Notifier<AppUser?> {
  @override
  AppUser? build() => ref.read(initialUserProvider);

  Future<void> signIn(AppUser user) async {
    final device = _deviceLabel();
    final s = await ref.read(authRepositoryProvider).startSession(user.id, device);
    await ref.read(settingsRepositoryProvider).setSession(user.id, s.id);
    state = user;
  }

  void refresh(AppUser user) => state = user;

  Future<void> signOut() async {
    final sid = ref.read(settingsRepositoryProvider).sessionId;
    if (state != null && sid != null) await ref.read(authRepositoryProvider).revokeSession(state!.id, sid);
    await ref.read(settingsRepositoryProvider).setSession(null, null);
    await ref.read(notificationServiceProvider).cancelAll();
    state = null;
  }

  static String _deviceLabel() {
    try {
      return '${Platform.operatingSystem} ${Platform.operatingSystemVersion}'.trim();
    } catch (_) {
      return 'device';
    }
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, AppUser?>(SessionNotifier.new);

class LockNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(settingsProvider).lockEnabled;
  void unlock() => state = false;
  void lock() {
    if (ref.read(settingsProvider).lockEnabled) state = true;
  }
}

final lockProvider = NotifierProvider<LockNotifier, bool>(LockNotifier.new);

class RevisionNotifier extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final revisionProvider = NotifierProvider<RevisionNotifier, int>(RevisionNotifier.new);

String _uid(Ref ref) {
  ref.watch(revisionProvider);
  final u = ref.watch(sessionProvider);
  if (u == null) throw StateError('not signed in');
  return u.id;
}

// ------------------------------------------------------------------ queries
final snapshotProvider = FutureProvider<FinanceSnapshot>((ref) async => ref.watch(snapshotLoaderProvider).load(_uid(ref)));
final accountsProvider = FutureProvider<List<Account>>((ref) async => ref.watch(accountRepositoryProvider).accounts(_uid(ref)));
final categoriesProvider = FutureProvider<List<Category>>((ref) async => ref.watch(accountRepositoryProvider).categories(_uid(ref)));
final currenciesProvider = FutureProvider<List<Currency>>((ref) async {
  ref.watch(revisionProvider);
  return ref.watch(currencyRepositoryProvider).currencies();
});
final ratesProvider = FutureProvider<List<ExchangeRate>>((ref) async => ref.watch(currencyRepositoryProvider).rates(_uid(ref)));
final recurringProvider = FutureProvider<List<RecurringRule>>((ref) async => ref.watch(transactionRepositoryProvider).recurringRules(_uid(ref)));
final debtsProvider = FutureProvider<List<DebtSummary>>((ref) async => ref.watch(debtRepositoryProvider).debts(_uid(ref)));
final goalsProvider = FutureProvider<List<GoalStatus>>((ref) async => ref.watch(goalRepositoryProvider).goals(_uid(ref)));
final billsProvider = FutureProvider<List<Bill>>((ref) async => ref.watch(billRepositoryProvider).bills(_uid(ref)));
final budgetStatusProvider = FutureProvider<List<BudgetStatus>>((ref) async => ref.watch(budgetRepositoryProvider).statuses(_uid(ref), DateTime.now()));
final assetsProvider = FutureProvider<List<Asset>>((ref) async => ref.watch(assetRepositoryProvider).assets(_uid(ref)));
final investmentsProvider = FutureProvider<List<InvestmentPerformance>>((ref) async => ref.watch(investmentRepositoryProvider).investments(_uid(ref)));
final txnProvider = FutureProvider.family<FinTransaction?, String>((ref, id) async => ref.watch(transactionRepositoryProvider).get(_uid(ref), id));
final auditProvider = FutureProvider.family<List<AuditEntry>, String?>((ref, entityId) async =>
    ref.watch(transactionRepositoryProvider).audit(_uid(ref), entityId: entityId, limit: entityId == null ? 300 : 50));
final sessionsProvider = FutureProvider<List<SessionInfo>>((ref) async => ref.watch(authRepositoryProvider).sessions(_uid(ref)));

class TxnQueryNotifier extends Notifier<TxnQuery> {
  @override
  TxnQuery build() => const TxnQuery();
  void set(TxnQuery q) => state = q;
}

final txnQueryProvider = NotifierProvider<TxnQueryNotifier, TxnQuery>(TxnQueryNotifier.new);
final txnListProvider = FutureProvider<List<FinTransaction>>((ref) async =>
    ref.watch(transactionRepositoryProvider).query(_uid(ref), ref.watch(txnQueryProvider)));

final accountTxnsProvider = FutureProvider.family<List<FinTransaction>, String>((ref, accountId) async =>
    ref.watch(transactionRepositoryProvider).query(_uid(ref), TxnQuery(accountId: accountId, includeVoided: true)));

// ------------------------------------------------------------------ actions (writes)
/// Every write goes through here: repository call, then refresh + alerts.
class FinanceActions {
  final Ref ref;
  FinanceActions(this.ref);

  String get uid => ref.read(sessionProvider)!.id;
  L10n get l => ref.read(l10nProvider);
  void _bump() => ref.read(revisionProvider.notifier).bump();

  Future<T> run<T>(Future<T> Function(String uid) body) async {
    final r = await body(uid);
    _bump();
    return r;
  }

  /// Records an income/expense and fires instant alerts (large expense, low balance, budget).
  Future<FinTransaction> record(TxnDraft d) async {
    final t = await run((u) => ref.read(transactionRepositoryProvider).record(u, d));
    await _afterTxn(t);
    return t;
  }

  Future<FinTransaction> transfer(TransferDraft d) => run((u) => ref.read(transactionRepositoryProvider).transfer(u, d));

  Future<void> _afterTxn(FinTransaction t) async {
    final s = ref.read(settingsProvider).notifications;
    final snap = await ref.read(snapshotLoaderProvider).load(uid);
    final alerts = AlertsService(l.tr).afterTransaction(t, snap, largeThreshold: s.largeExpense ? Money.tryParse(s.largeExpenseThreshold) : null);
    final notifier = ref.read(notificationServiceProvider);
    var id = 900;
    for (final a in alerts) {
      final enabled = switch (a.kind) { 'large' => s.largeExpense, 'low_balance' => s.lowBalance, 'budget' => s.budget, _ => true };
      if (enabled) await notifier.showNow(id++, l.tr('app_name'), a.message);
    }
  }

  /// Posts due recurring/scheduled transactions and refreshes reminders.
  Future<void> startup() async {
    try {
      await ref.read(transactionRepositoryProvider).processDue(uid, DateTime.now());
    } catch (_) {}
    _bump();
    await rescheduleReminders();
  }

  Future<void> rescheduleReminders() async {
    try {
      final prefs = ref.read(settingsProvider).notifications;
      final snap = await ref.read(snapshotLoaderProvider).load(uid);
      final plan = ReminderPlanner.plan(snap);
      final out = <ScheduledAlert>[];
      for (final p in plan) {
        final enabled = switch (p.$3) { 'bill' || 'bill_today' => prefs.bills, 'debt' || 'receivable' => prefs.debts, 'goal' => prefs.goals, _ => true };
        if (enabled) out.add(ScheduledAlert(p.$1, p.$2, l.tr('notif_${p.$3}_title'), l.tr('notif_${p.$3}_body', {'name': p.$4, 'detail': p.$5})));
      }
      final now = DateTime.now();
      final inc = snap.txns.where((t) => t.type == TxnType.income && DateRange.of(PeriodKind.monthly, now).contains(t.txnDate)).fold(Decimal.zero, (a, t) => a + t.baseAmount);
      final exp = snap.txns.where((t) => t.type == TxnType.expense && DateRange.of(PeriodKind.monthly, now).contains(t.txnDate)).fold(Decimal.zero, (a, t) => a + t.baseAmount);
      final body = l.tr('notif_summary_body', {'inc': Money.format(inc, currency: snap.base), 'exp': Money.format(exp, currency: snap.base)});
      if (prefs.daily) {
        out.add(ScheduledAlert(10, DateTime(now.year, now.month, now.day, prefs.dailyHour), l.tr('notif_daily_title'), body, repeat: DateTimeComponents.time));
      }
      if (prefs.weekly) {
        final fri = startOfWeek(now).add(const Duration(days: 6));
        out.add(ScheduledAlert(11, DateTime(fri.year, fri.month, fri.day, 20), l.tr('notif_weekly_title'), body, repeat: DateTimeComponents.dayOfWeekAndTime));
      }
      if (prefs.monthly) {
        out.add(ScheduledAlert(12, DateTime(now.year, now.month + 1, 1, 10), l.tr('notif_monthly_title'), body, repeat: DateTimeComponents.dayOfMonthAndTime));
      }
      await ref.read(notificationServiceProvider).reschedule(out);
    } catch (e) {
      debugPrint('reminders: $e');
    }
  }
}

final actionsProvider = Provider((ref) => FinanceActions(ref));
