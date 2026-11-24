import 'dart:convert';

import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../../core/utils/dates.dart';

/// Ledger entry types. Only [income] and [expense] count in income/expense
/// totals; transfers, debt principal and savings movements are balance moves.
enum TxnType { income, expense, transfer, debtPayment, debtCollection, loanGiven, loanReceived, savingsDeposit, savingsWithdraw }

extension TxnTypeX on TxnType {
  /// +1 money enters the account, -1 leaves it (transfers handled separately).
  int get sign => switch (this) {
        TxnType.income || TxnType.debtCollection || TxnType.loanReceived || TxnType.savingsWithdraw => 1,
        TxnType.expense || TxnType.debtPayment || TxnType.loanGiven || TxnType.savingsDeposit => -1,
        TxnType.transfer => 0,
      };
  bool get countsAsIncome => this == TxnType.income;
  bool get countsAsExpense => this == TxnType.expense;
}

enum TxnStatus { posted, voided }

class FinTransaction {
  final String id;
  final String userId;
  final TxnType type;
  final String? accountId; // source account (null only for goal moves without account)
  final String? toAccountId; // transfers
  final String? categoryId;
  final Decimal amount; // original amount
  final String currency; // original currency
  final Decimal? accountAmount; // amount in the account's currency (== amount when same)
  final String? accountRateId;
  final Decimal? toAmount; // transfer: amount credited to destination
  final String? toCurrency;
  final Decimal? fxRate; // transfer: effective rate used (to/from)
  final Decimal fee; // transfer fee in source currency (also posted as linked expense)
  final String? parentId; // fee expense -> transfer
  final Decimal baseAmount; // converted to base currency at txn date
  final String baseCurrency;
  final String? baseRateId;
  final Decimal? baseRate;
  final String title;
  final String notes;
  final DateTime txnDate;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TxnStatus status;
  final DateTime? voidedAt;
  final String? voidReason;
  final String idempotencyKey;
  final String? recurringId;
  final String? refType; // debt | goal | bill
  final String? refId;
  final List<String> attachments;

  const FinTransaction({
    required this.id, required this.userId, required this.type, this.accountId, this.toAccountId, this.categoryId,
    required this.amount, required this.currency, this.accountAmount, this.accountRateId, this.toAmount, this.toCurrency,
    this.fxRate, required this.fee, this.parentId, required this.baseAmount, required this.baseCurrency, this.baseRateId, this.baseRate,
    this.title = '', this.notes = '', required this.txnDate, required this.createdAt, required this.updatedAt,
    this.status = TxnStatus.posted, this.voidedAt, this.voidReason, required this.idempotencyKey, this.recurringId,
    this.refType, this.refId, this.attachments = const [],
  });

  bool get isVoid => status == TxnStatus.voided;
  Decimal get effectiveAccountAmount => accountAmount ?? amount;

  factory FinTransaction.fromMap(Map<String, Object?> m) => FinTransaction(
        id: m['id'] as String, userId: m['user_id'] as String, type: TxnType.values.byName(m['type'] as String),
        accountId: m['account_id'] as String?, toAccountId: m['to_account_id'] as String?, categoryId: m['category_id'] as String?,
        amount: Money.fromDb(m['amount']), currency: m['currency'] as String,
        accountAmount: Money.fromDbNullable(m['account_amount']), accountRateId: m['account_rate_id'] as String?,
        toAmount: Money.fromDbNullable(m['to_amount']), toCurrency: m['to_currency'] as String?, fxRate: Money.fromDbNullable(m['fx_rate']),
        fee: Money.fromDb(m['fee']), parentId: m['parent_id'] as String?,
        baseAmount: Money.fromDb(m['base_amount']), baseCurrency: m['base_currency'] as String, baseRateId: m['base_rate_id'] as String?,
        baseRate: Money.fromDbNullable(m['base_rate']),
        title: (m['title'] as String?) ?? '', notes: (m['notes'] as String?) ?? '',
        txnDate: parseDt(m['txn_date']!), createdAt: parseDt(m['created_at']!), updatedAt: parseDt(m['updated_at']!),
        status: TxnStatus.values.byName(m['status'] as String), voidedAt: parseDtN(m['voided_at']), voidReason: m['void_reason'] as String?,
        idempotencyKey: m['idempotency_key'] as String, recurringId: m['recurring_id'] as String?,
        refType: m['ref_type'] as String?, refId: m['ref_id'] as String?,
        attachments: m['attachments'] == null ? const [] : (jsonDecode(m['attachments'] as String) as List).cast<String>(),
      );

  Map<String, Object?> toMap() => {
        'id': id, 'user_id': userId, 'type': type.name, 'account_id': accountId, 'to_account_id': toAccountId,
        'category_id': categoryId, 'amount': Money.toDb(amount), 'currency': currency,
        'account_amount': accountAmount == null ? null : Money.toDb(accountAmount!), 'account_rate_id': accountRateId,
        'to_amount': toAmount == null ? null : Money.toDb(toAmount!), 'to_currency': toCurrency,
        'fx_rate': fxRate?.toString(), 'fee': Money.toDb(fee), 'parent_id': parentId,
        'base_amount': Money.toDb(baseAmount), 'base_currency': baseCurrency, 'base_rate_id': baseRateId, 'base_rate': baseRate?.toString(),
        'title': title, 'notes': notes, 'txn_date': txnDate.toIso8601String(),
        'created_at': createdAt.toIso8601String(), 'updated_at': updatedAt.toIso8601String(), 'status': status.name,
        'voided_at': voidedAt?.toIso8601String(), 'void_reason': voidReason, 'idempotency_key': idempotencyKey,
        'recurring_id': recurringId, 'ref_type': refType, 'ref_id': refId, 'attachments': jsonEncode(attachments),
      };
}

/// What the user enters for an income/expense (or a debt/goal/bill movement).
class TxnDraft {
  final TxnType type;
  final String? accountId;
  final Decimal amount;
  final String currency;
  final String? categoryId;
  final String title;
  final String notes;
  final DateTime txnDate;
  final List<String> attachments;
  final String idempotencyKey;
  final String? refType;
  final String? refId;
  final String? recurringId;
  const TxnDraft({required this.type, required this.accountId, required this.amount, required this.currency, this.categoryId,
      this.title = '', this.notes = '', required this.txnDate, this.attachments = const [], required this.idempotencyKey,
      this.refType, this.refId, this.recurringId});

  Map<String, Object?> toJson() => {
        'type': type.name, 'account_id': accountId, 'amount': amount.toString(), 'currency': currency, 'category_id': categoryId,
        'title': title, 'notes': notes, 'txn_date': txnDate.toIso8601String(), 'attachments': attachments, 'idempotency_key': idempotencyKey,
        'ref_type': refType, 'ref_id': refId, 'recurring_id': recurringId,
      };
  factory TxnDraft.fromJson(Map<String, Object?> j) => TxnDraft(
      type: TxnType.values.byName(j['type'] as String), accountId: j['account_id'] as String?, amount: Money.parse(j['amount'] as String),
      currency: j['currency'] as String, categoryId: j['category_id'] as String?, title: (j['title'] as String?) ?? '',
      notes: (j['notes'] as String?) ?? '', txnDate: DateTime.parse(j['txn_date'] as String),
      attachments: ((j['attachments'] as List?) ?? const []).cast<String>(), idempotencyKey: j['idempotency_key'] as String,
      refType: j['ref_type'] as String?, refId: j['ref_id'] as String?, recurringId: j['recurring_id'] as String?);

  TxnDraft copyWith({DateTime? txnDate, String? idempotencyKey, String? recurringId}) => TxnDraft(
      type: type, accountId: accountId, amount: amount, currency: currency, categoryId: categoryId, title: title, notes: notes,
      txnDate: txnDate ?? this.txnDate, attachments: attachments, idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      refType: refType, refId: refId, recurringId: recurringId ?? this.recurringId);
}

class TransferDraft {
  final String fromAccountId;
  final String toAccountId;
  final Decimal amount; // in source currency
  final Decimal? toAmount; // required when currencies differ (actual amount received)
  final Decimal fee; // in source currency
  final DateTime txnDate;
  final String notes;
  final String idempotencyKey;
  TransferDraft({required this.fromAccountId, required this.toAccountId, required this.amount, this.toAmount, Decimal? fee,
      required this.txnDate, this.notes = '', required this.idempotencyKey})
      : fee = fee ?? Decimal.zero;
}

/// Recurring income/expense or a one-off scheduled future transaction.
class RecurringRule {
  final String id;
  final String userId;
  final bool scheduledOnce;
  final Frequency frequency;
  final DateTime nextDate;
  final DateTime? endDate;
  final bool active;
  final TxnDraft template;
  final String? lastError;
  final DateTime createdAt;
  const RecurringRule({required this.id, required this.userId, required this.scheduledOnce, required this.frequency, required this.nextDate,
      this.endDate, this.active = true, required this.template, this.lastError, required this.createdAt});

  factory RecurringRule.fromMap(Map<String, Object?> m) => RecurringRule(
      id: m['id'] as String, userId: m['user_id'] as String, scheduledOnce: (m['scheduled_once'] as int) == 1,
      frequency: Frequency.values.byName(m['frequency'] as String), nextDate: DateTime.parse(m['next_date'] as String),
      endDate: parseDtN(m['end_date']), active: (m['active'] as int) == 1,
      template: TxnDraft.fromJson(jsonDecode(m['template'] as String) as Map<String, Object?>), lastError: m['last_error'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String));
}

class AuditEntry {
  final String id;
  final String userId;
  final String entity;
  final String entityId;
  final String action;
  final String? before;
  final String? after;
  final DateTime at;
  const AuditEntry({required this.id, required this.userId, required this.entity, required this.entityId, required this.action, this.before, this.after, required this.at});
  factory AuditEntry.fromMap(Map<String, Object?> m) => AuditEntry(
      id: m['id'] as String, userId: m['user_id'] as String, entity: m['entity'] as String, entityId: m['entity_id'] as String,
      action: m['action'] as String, before: m['before_json'] as String?, after: m['after_json'] as String?, at: DateTime.parse(m['at'] as String));
}
