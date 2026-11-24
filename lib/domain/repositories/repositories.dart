import 'package:decimal/decimal.dart';

import '../../core/utils/dates.dart';
import '../entities/account.dart';
import '../entities/currency.dart';
import '../entities/holdings.dart';
import '../entities/planning.dart';
import '../entities/transaction.dart';
import '../entities/user.dart';

/// Repository interfaces (domain layer). The local SQLite implementations live
/// in data/repositories; the Supabase sync layer pushes/pulls the same rows.

abstract class AuthRepository {
  Future<SignUpResult> signUp({required String name, required String email, required String password, required String baseCurrency});
  Future<AppUser> signIn(String email, String password);
  Future<AppUser?> getUser(String id);
  /// Resets the password with the one-time recovery code; returns a NEW recovery code.
  Future<String> resetPassword({required String email, required String recoveryCode, required String newPassword});
  Future<void> changePassword(String uid, String oldPassword, String newPassword);
  Future<AppUser> updateProfile(String uid, {required String name, required String email, String? avatarPath});
  Future<void> deleteAccount(String uid, String password);
  Future<SessionInfo> startSession(String uid, String device);
  Future<List<SessionInfo>> sessions(String uid);
  Future<void> revokeSession(String uid, String sessionId);
  Future<bool> isSessionActive(String sessionId);
  Future<void> touchSession(String sessionId);
}

abstract class CurrencyRepository {
  Future<List<Currency>> currencies();
  Future<void> addCurrency(Currency c);
  Future<List<ExchangeRate>> rates(String uid, {String? from, String? to});
  Future<ExchangeRate> addRate(String uid, {required String from, required String to, required Decimal rate, required String source, required DateTime date});
  Future<void> deleteRate(String uid, String id);
  /// Converts using the latest MANUAL rate dated on/before [date] (direct or
  /// exact inverse). Throws MissingRateException when none exists.
  Future<Conversion> convert(String uid, Decimal amount, String from, String to, DateTime date);
  Future<Conversion?> tryConvert(String uid, Decimal amount, String from, String to, DateTime date);
  /// Re-bases every transaction; throws MissingRateException (nothing changes) if a rate is missing.
  Future<void> changeBaseCurrency(String uid, String newBase);
}

abstract class AccountRepository {
  Future<List<Account>> accounts(String uid, {bool includeInactive = true});
  Future<Account?> account(String uid, String id);
  Future<Account> createAccount(String uid, {required String name, required AccountType type, required String currency,
      required Decimal openingBalance, String description = '', int color = 0xFF0F766E, Decimal? lowBalanceAlert});
  Future<Account> updateAccount(String uid, Account updated);
  Future<void> setActive(String uid, String id, bool active);
  Future<List<Category>> categories(String uid, {CategoryKind? kind, bool includeArchived = false});
  Future<Category> saveCategory(String uid, {String? id, required CategoryKind kind, required String name, required int icon, required int color});
  Future<void> archiveCategory(String uid, String id);
}

class TxnQuery {
  final String? text;
  final Set<TxnType>? types;
  final String? accountId;
  final String? categoryId;
  final String? currency;
  final DateTime? from; // inclusive
  final DateTime? to; // exclusive
  final Decimal? minAmount;
  final Decimal? maxAmount;
  final bool includeVoided;
  final String sort; // date_desc | date_asc | amount_desc | amount_asc
  final int? limit;
  const TxnQuery({this.text, this.types, this.accountId, this.categoryId, this.currency, this.from, this.to, this.minAmount, this.maxAmount,
      this.includeVoided = false, this.sort = 'date_desc', this.limit});
  TxnQuery copyWith({String? text, Set<TxnType>? types, bool clearTypes = false, String? accountId, bool clearAccount = false, String? categoryId,
          bool clearCategory = false, String? currency, bool clearCurrency = false, DateTime? from, DateTime? to, bool clearDates = false,
          Decimal? minAmount, Decimal? maxAmount, bool clearAmounts = false, bool? includeVoided, String? sort}) =>
      TxnQuery(
          text: text ?? this.text, types: clearTypes ? null : types ?? this.types, accountId: clearAccount ? null : accountId ?? this.accountId,
          categoryId: clearCategory ? null : categoryId ?? this.categoryId, currency: clearCurrency ? null : currency ?? this.currency,
          from: clearDates ? null : from ?? this.from, to: clearDates ? null : to ?? this.to,
          minAmount: clearAmounts ? null : minAmount ?? this.minAmount, maxAmount: clearAmounts ? null : maxAmount ?? this.maxAmount,
          includeVoided: includeVoided ?? this.includeVoided, sort: sort ?? this.sort, limit: limit);
}

class RecurringResult {
  final int created;
  final List<String> errors;
  const RecurringResult(this.created, this.errors);
}

abstract class TransactionRepository {
  Future<FinTransaction> record(String uid, TxnDraft draft);
  Future<FinTransaction> transfer(String uid, TransferDraft draft);
  Future<FinTransaction> updateTxn(String uid, String id, TxnDraft draft);
  Future<FinTransaction> voidTxn(String uid, String id, {String reason = ''});
  Future<FinTransaction?> get(String uid, String id);
  Future<List<FinTransaction>> query(String uid, TxnQuery q);
  Future<List<RecurringRule>> recurringRules(String uid);
  Future<RecurringRule> saveRecurring(String uid, {required TxnDraft template, required Frequency frequency, required DateTime firstDate, DateTime? endDate, bool scheduledOnce = false});
  Future<void> setRecurringActive(String uid, String id, bool active);
  Future<void> deleteRecurring(String uid, String id);
  Future<RecurringResult> processDue(String uid, DateTime now);
  Future<List<AuditEntry>> audit(String uid, {String? entity, String? entityId, int limit = 200});
}

abstract class BudgetRepository {
  Future<List<Budget>> budgets(String uid);
  Future<Budget> saveBudget(String uid, {String? id, required String name, String? categoryId, required BudgetPeriod period, required Decimal limit, int alertPercent = 80});
  Future<void> deleteBudget(String uid, String id);
  Future<List<BudgetStatus>> statuses(String uid, DateTime now);
}

abstract class DebtRepository {
  Future<List<DebtSummary>> debts(String uid);
  Future<DebtSummary?> debt(String uid, String id);
  Future<Debt> createDebt(String uid, {required DebtDirection direction, required String party, required Decimal principal, required String currency,
      Decimal? interestRate, required DateTime startDate, DateTime? dueDate, int installments = 1, Frequency frequency = Frequency.monthly,
      String notes = '', String? accountId, bool moveMoney = false, required String idempotencyKey});
  Future<Debt> updateDebt(String uid, Debt d);
  Future<FinTransaction> addPayment(String uid, String debtId, {required String accountId, required Decimal amount, required DateTime date, String notes = '', required String idempotencyKey});
  Future<List<FinTransaction>> payments(String uid, String debtId);
  Future<void> deleteDebt(String uid, String id);
}

abstract class GoalRepository {
  Future<List<GoalStatus>> goals(String uid);
  Future<GoalStatus?> goal(String uid, String id);
  Future<SavingsGoal> saveGoal(String uid, {String? id, required String name, required Decimal target, required String currency, Decimal? initialAmount, DateTime? deadline, int color = 0xFF0EA5E9, String notes = ''});
  /// Returns true when this movement made the goal reach its target.
  Future<bool> move(String uid, String goalId, {required bool deposit, String? accountId, required Decimal amount, required DateTime date, String notes = '', required String idempotencyKey});
  Future<List<FinTransaction>> movements(String uid, String goalId);
  Future<void> deleteGoal(String uid, String id);
}

abstract class BillRepository {
  Future<List<Bill>> bills(String uid, {bool includeInactive = true});
  Future<Bill> saveBill(String uid, {String? id, required String name, required BillKind kind, required Decimal amount, required String currency,
      required DateTime dueDate, Frequency recurrence = Frequency.monthly, int remindDaysBefore = 3, String? accountId, String? categoryId, String notes = ''});
  Future<FinTransaction> payBill(String uid, String billId, {required String accountId, Decimal? amount, required DateTime date, required String idempotencyKey});
  Future<List<BillPayment>> payments(String uid, String billId);
  Future<void> deleteBill(String uid, String id);
}

abstract class AssetRepository {
  Future<List<Asset>> assets(String uid);
  Future<Asset> saveAsset(String uid, {String? id, required String name, required AssetType type, required Decimal purchaseValue, required Decimal currentValue,
      required String currency, DateTime? purchaseDate, List<String> documents = const [], String notes = ''});
  Future<void> addValue(String uid, String assetId, Decimal value, DateTime date, {String note = ''});
  Future<List<ValuePoint>> history(String uid, String assetId);
  Future<void> deleteAsset(String uid, String id);
}

abstract class InvestmentRepository {
  Future<List<InvestmentPerformance>> investments(String uid);
  Future<Investment> saveInvestment(String uid, {String? id, required String name, required InvestmentType type, required String currency,
      required DateTime startDate, required Decimal capital, Decimal? currentValue, String notes = ''});
  Future<void> addEntry(String uid, String investmentId, InvestmentEntryKind kind, Decimal amount, DateTime date, {String note = ''});
  Future<void> deleteInvestment(String uid, String id);
}

/// Everything about a user, as JSON, for backup/restore.
abstract class BackupRepository {
  Future<Map<String, Object?>> export(String uid);
  Future<void> restore(String uid, Map<String, Object?> data);
}
