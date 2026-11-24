import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';

enum AccountType { cash, bank, ewallet, digitalWallet, savings, investment }

class Account {
  final String id;
  final String userId;
  final String name;
  final AccountType type;
  final String currency;
  final Decimal openingBalance;
  final Decimal balance;
  final String description;
  final bool isActive;
  final int color;
  final Decimal? lowBalanceAlert;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Account({required this.id, required this.userId, required this.name, required this.type, required this.currency,
      required this.openingBalance, required this.balance, this.description = '', this.isActive = true, this.color = 0xFF0F766E,
      this.lowBalanceAlert, required this.createdAt, required this.updatedAt});

  Account copyWith({String? name, AccountType? type, String? description, bool? isActive, int? color, Decimal? openingBalance, Decimal? balance, Decimal? lowBalanceAlert, bool clearLow = false, DateTime? updatedAt}) =>
      Account(id: id, userId: userId, name: name ?? this.name, type: type ?? this.type, currency: currency,
          openingBalance: openingBalance ?? this.openingBalance, balance: balance ?? this.balance,
          description: description ?? this.description, isActive: isActive ?? this.isActive, color: color ?? this.color,
          lowBalanceAlert: clearLow ? null : (lowBalanceAlert ?? this.lowBalanceAlert), createdAt: createdAt, updatedAt: updatedAt ?? this.updatedAt);

  factory Account.fromMap(Map<String, Object?> m) => Account(
      id: m['id'] as String, userId: m['user_id'] as String, name: m['name'] as String,
      type: AccountType.values.byName(m['type'] as String), currency: m['currency'] as String,
      openingBalance: Money.fromDb(m['opening_balance']), balance: Money.fromDb(m['balance']),
      description: (m['description'] as String?) ?? '', isActive: (m['is_active'] as int) == 1, color: m['color'] as int,
      lowBalanceAlert: Money.fromDbNullable(m['low_balance_alert']),
      createdAt: DateTime.parse(m['created_at'] as String), updatedAt: DateTime.parse(m['updated_at'] as String));

  Map<String, Object?> toMap() => {
        'id': id, 'user_id': userId, 'name': name, 'type': type.name, 'currency': currency,
        'opening_balance': Money.toDb(openingBalance), 'balance': Money.toDb(balance), 'description': description,
        'is_active': isActive ? 1 : 0, 'color': color, 'low_balance_alert': lowBalanceAlert == null ? null : Money.toDb(lowBalanceAlert!),
        'created_at': createdAt.toIso8601String(), 'updated_at': updatedAt.toIso8601String(),
      };
}

enum CategoryKind { income, expense }

class Category {
  final String id;
  final String userId;
  final CategoryKind kind;
  final String? key; // builtin key, translated in UI
  final String name; // custom name (or English fallback)
  final int icon;
  final int color;
  final bool archived;
  const Category({required this.id, required this.userId, required this.kind, this.key, required this.name, required this.icon, required this.color, this.archived = false});
  bool get builtin => key != null;

  factory Category.fromMap(Map<String, Object?> m) => Category(
      id: m['id'] as String, userId: m['user_id'] as String, kind: CategoryKind.values.byName(m['kind'] as String),
      key: m['key'] as String?, name: m['name'] as String, icon: m['icon'] as int, color: m['color'] as int,
      archived: (m['archived'] as int? ?? 0) == 1);

  Map<String, Object?> toMap() => {'id': id, 'user_id': userId, 'kind': kind.name, 'key': key, 'name': name, 'icon': icon, 'color': color, 'archived': archived ? 1 : 0};
}
