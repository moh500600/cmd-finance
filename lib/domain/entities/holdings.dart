import 'dart:convert';

import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../../core/utils/dates.dart';

enum AssetType { realEstate, vehicle, device, gold, business, investment, other }

class Asset {
  final String id;
  final String userId;
  final String name;
  final AssetType type;
  final Decimal purchaseValue;
  final Decimal currentValue;
  final String currency;
  final DateTime? purchaseDate;
  final List<String> documents;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Asset({required this.id, required this.userId, required this.name, required this.type, required this.purchaseValue, required this.currentValue,
      required this.currency, this.purchaseDate, this.documents = const [], this.notes = '', required this.createdAt, required this.updatedAt});
  Decimal get change => currentValue - purchaseValue;
  Decimal get changePercent => Money.percent(change, purchaseValue);
  factory Asset.fromMap(Map<String, Object?> m) => Asset(
      id: m['id'] as String, userId: m['user_id'] as String, name: m['name'] as String, type: AssetType.values.byName(m['type'] as String),
      purchaseValue: Money.fromDb(m['purchase_value']), currentValue: Money.fromDb(m['current_value']), currency: m['currency'] as String,
      purchaseDate: parseDtN(m['purchase_date']), documents: m['documents'] == null ? const [] : (jsonDecode(m['documents'] as String) as List).cast<String>(),
      notes: (m['notes'] as String?) ?? '', createdAt: DateTime.parse(m['created_at'] as String), updatedAt: DateTime.parse(m['updated_at'] as String));
  Map<String, Object?> toMap() => {'id': id, 'user_id': userId, 'name': name, 'type': type.name, 'purchase_value': Money.toDb(purchaseValue),
        'current_value': Money.toDb(currentValue), 'currency': currency, 'purchase_date': purchaseDate?.toIso8601String(), 'documents': jsonEncode(documents),
        'notes': notes, 'created_at': createdAt.toIso8601String(), 'updated_at': updatedAt.toIso8601String()};
}

class ValuePoint {
  final String id;
  final String parentId;
  final Decimal value;
  final DateTime date;
  final String note;
  const ValuePoint({required this.id, required this.parentId, required this.value, required this.date, this.note = ''});
}

enum InvestmentType { stocks, funds, crypto, realEstate, business, gold, deposit, other }

enum InvestmentEntryKind { contribution, withdrawal, dividend, valuation }

class Investment {
  final String id;
  final String userId;
  final String name;
  final InvestmentType type;
  final String currency;
  final DateTime startDate;
  final Decimal currentValue;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  const Investment({required this.id, required this.userId, required this.name, required this.type, required this.currency, required this.startDate,
      required this.currentValue, this.notes = '', required this.createdAt, required this.updatedAt});
  factory Investment.fromMap(Map<String, Object?> m) => Investment(
      id: m['id'] as String, userId: m['user_id'] as String, name: m['name'] as String, type: InvestmentType.values.byName(m['type'] as String),
      currency: m['currency'] as String, startDate: DateTime.parse(m['start_date'] as String), currentValue: Money.fromDb(m['current_value']),
      notes: (m['notes'] as String?) ?? '', createdAt: DateTime.parse(m['created_at'] as String), updatedAt: DateTime.parse(m['updated_at'] as String));
  Map<String, Object?> toMap() => {'id': id, 'user_id': userId, 'name': name, 'type': type.name, 'currency': currency, 'start_date': startDate.toIso8601String(),
        'current_value': Money.toDb(currentValue), 'notes': notes, 'created_at': createdAt.toIso8601String(), 'updated_at': updatedAt.toIso8601String()};
}

class InvestmentEntry {
  final String id;
  final String investmentId;
  final InvestmentEntryKind kind;
  final Decimal amount;
  final DateTime date;
  final String note;
  const InvestmentEntry({required this.id, required this.investmentId, required this.kind, required this.amount, required this.date, this.note = ''});
  factory InvestmentEntry.fromMap(Map<String, Object?> m) => InvestmentEntry(
      id: m['id'] as String, investmentId: m['investment_id'] as String, kind: InvestmentEntryKind.values.byName(m['kind'] as String),
      amount: Money.fromDb(m['amount']), date: DateTime.parse(m['date'] as String), note: (m['note'] as String?) ?? '');
}

/// Tracking-only performance: no trades are executed by the app.
class InvestmentPerformance {
  final Investment investment;
  final List<InvestmentEntry> entries;
  const InvestmentPerformance(this.investment, this.entries);
  Decimal _sum(InvestmentEntryKind k) => Money.sum(entries.where((e) => e.kind == k).map((e) => e.amount));
  Decimal get contributions => _sum(InvestmentEntryKind.contribution);
  Decimal get withdrawals => _sum(InvestmentEntryKind.withdrawal);
  Decimal get dividends => _sum(InvestmentEntryKind.dividend);
  Decimal get capital => contributions;
  /// Profit/loss = what you have + what you took out − what you put in.
  Decimal get profitLoss => investment.currentValue + withdrawals + dividends - contributions;
  Decimal get roi => Money.percent(profitLoss, contributions);
}
