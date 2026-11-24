import 'package:sqflite/sqflite.dart';

/// Local relational database — the source of truth on the phone.
///
/// Money columns are TEXT holding canonical decimal strings (parsed into
/// Decimal); there is no REAL column for money anywhere. Every table is
/// scoped by user_id and is created locally on the device.
class AppDatabase {
  static const version = 1;

  static Future<Database> open(DatabaseFactory factory, String path) => factory.openDatabase(path,
      options: OpenDatabaseOptions(
        version: version,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, v) async {
          final b = db.batch();
          for (final s in schema) {
            b.execute(s);
          }
          await b.commit(noResult: true);
          await seedCurrencies(db);
        },
      ));

  static const schema = <String>[
    '''CREATE TABLE users(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, email TEXT NOT NULL UNIQUE COLLATE NOCASE,
      password_hash TEXT NOT NULL, salt TEXT NOT NULL, recovery_hash TEXT NOT NULL, recovery_salt TEXT NOT NULL,
      base_currency TEXT NOT NULL, avatar_path TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    '''CREATE TABLE sessions(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, device TEXT NOT NULL,
      created_at TEXT NOT NULL, last_seen_at TEXT NOT NULL, revoked_at TEXT)''',
    '''CREATE TABLE currencies(
      code TEXT PRIMARY KEY, name_ar TEXT NOT NULL, name_en TEXT NOT NULL, symbol TEXT NOT NULL,
      decimals INTEGER NOT NULL DEFAULT 2, builtin INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE exchange_rates(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      from_ccy TEXT NOT NULL REFERENCES currencies(code), to_ccy TEXT NOT NULL REFERENCES currencies(code),
      rate TEXT NOT NULL, source TEXT NOT NULL, rate_date TEXT NOT NULL, created_at TEXT NOT NULL,
      CHECK (from_ccy <> to_ccy))''',
    'CREATE INDEX ix_rates ON exchange_rates(user_id, from_ccy, to_ccy, rate_date)',
    '''CREATE TABLE accounts(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, name TEXT NOT NULL,
      type TEXT NOT NULL, currency TEXT NOT NULL REFERENCES currencies(code), opening_balance TEXT NOT NULL,
      balance TEXT NOT NULL, description TEXT NOT NULL DEFAULT '', is_active INTEGER NOT NULL DEFAULT 1,
      color INTEGER NOT NULL, low_balance_alert TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    '''CREATE TABLE categories(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, kind TEXT NOT NULL,
      key TEXT, name TEXT NOT NULL, icon INTEGER NOT NULL, color INTEGER NOT NULL, archived INTEGER NOT NULL DEFAULT 0,
      updated_at TEXT)''',
    '''CREATE TABLE transactions(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, type TEXT NOT NULL,
      account_id TEXT REFERENCES accounts(id), to_account_id TEXT REFERENCES accounts(id),
      category_id TEXT REFERENCES categories(id), amount TEXT NOT NULL, currency TEXT NOT NULL,
      account_amount TEXT, account_rate_id TEXT REFERENCES exchange_rates(id),
      to_amount TEXT, to_currency TEXT, fx_rate TEXT, fee TEXT NOT NULL DEFAULT '0',
      parent_id TEXT REFERENCES transactions(id), base_amount TEXT NOT NULL, base_currency TEXT NOT NULL,
      base_rate_id TEXT REFERENCES exchange_rates(id), base_rate TEXT,
      title TEXT NOT NULL DEFAULT '', notes TEXT NOT NULL DEFAULT '', txn_date TEXT NOT NULL,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'posted',
      voided_at TEXT, void_reason TEXT, idempotency_key TEXT NOT NULL, recurring_id TEXT,
      ref_type TEXT, ref_id TEXT, attachments TEXT,
      UNIQUE(user_id, idempotency_key))''',
    'CREATE INDEX ix_txn_user_date ON transactions(user_id, txn_date)',
    'CREATE INDEX ix_txn_account ON transactions(account_id)',
    'CREATE INDEX ix_txn_ref ON transactions(ref_type, ref_id)',
    '''CREATE TABLE recurring_rules(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, scheduled_once INTEGER NOT NULL,
      frequency TEXT NOT NULL, next_date TEXT NOT NULL, end_date TEXT, active INTEGER NOT NULL DEFAULT 1,
      template TEXT NOT NULL, last_error TEXT, created_at TEXT NOT NULL, updated_at TEXT)''',
    '''CREATE TABLE budgets(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, name TEXT NOT NULL,
      category_id TEXT REFERENCES categories(id), period TEXT NOT NULL, limit_amount TEXT NOT NULL, currency TEXT NOT NULL,
      alert_percent INTEGER NOT NULL DEFAULT 80, active INTEGER NOT NULL DEFAULT 1, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    '''CREATE TABLE debts(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, direction TEXT NOT NULL,
      party TEXT NOT NULL, principal TEXT NOT NULL, currency TEXT NOT NULL, interest_rate TEXT NOT NULL DEFAULT '0',
      start_date TEXT NOT NULL, due_date TEXT, installments INTEGER NOT NULL DEFAULT 1, installment_frequency TEXT NOT NULL,
      notes TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'open', account_id TEXT REFERENCES accounts(id),
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    '''CREATE TABLE savings_goals(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, name TEXT NOT NULL,
      target TEXT NOT NULL, currency TEXT NOT NULL, initial_amount TEXT NOT NULL DEFAULT '0', deadline TEXT,
      color INTEGER NOT NULL, notes TEXT NOT NULL DEFAULT '', achieved_at TEXT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    '''CREATE TABLE bills(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, name TEXT NOT NULL, kind TEXT NOT NULL,
      amount TEXT NOT NULL, currency TEXT NOT NULL, due_date TEXT NOT NULL, recurrence TEXT NOT NULL,
      remind_days_before INTEGER NOT NULL DEFAULT 3, account_id TEXT REFERENCES accounts(id), category_id TEXT REFERENCES categories(id),
      active INTEGER NOT NULL DEFAULT 1, notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    '''CREATE TABLE bill_payments(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      bill_id TEXT NOT NULL REFERENCES bills(id) ON DELETE CASCADE, due_date TEXT NOT NULL, paid_at TEXT NOT NULL,
      amount TEXT NOT NULL, currency TEXT NOT NULL, txn_id TEXT NOT NULL REFERENCES transactions(id), voided INTEGER NOT NULL DEFAULT 0)''',
    '''CREATE TABLE assets(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, name TEXT NOT NULL, type TEXT NOT NULL,
      purchase_value TEXT NOT NULL, current_value TEXT NOT NULL, currency TEXT NOT NULL, purchase_date TEXT, documents TEXT,
      notes TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    '''CREATE TABLE asset_values(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      asset_id TEXT NOT NULL REFERENCES assets(id) ON DELETE CASCADE, value TEXT NOT NULL, date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '')''',
    '''CREATE TABLE investments(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE, name TEXT NOT NULL, type TEXT NOT NULL,
      currency TEXT NOT NULL, start_date TEXT NOT NULL, current_value TEXT NOT NULL, notes TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''',
    '''CREATE TABLE investment_entries(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      investment_id TEXT NOT NULL REFERENCES investments(id) ON DELETE CASCADE, kind TEXT NOT NULL, amount TEXT NOT NULL,
      date TEXT NOT NULL, note TEXT NOT NULL DEFAULT '')''',
    '''CREATE TABLE audit_log(
      id TEXT PRIMARY KEY, user_id TEXT NOT NULL, entity TEXT NOT NULL, entity_id TEXT NOT NULL, action TEXT NOT NULL,
      before_json TEXT, after_json TEXT, at TEXT NOT NULL)''',
    'CREATE INDEX ix_audit ON audit_log(user_id, entity, entity_id)',
  ];

  /// Currencies are reference data (codes and names only — NO rates).
  static Future<void> seedCurrencies(DatabaseExecutor db) async {
    const rows = [
      ['YER', 'ريال يمني', 'Yemeni Rial', '﷼', 0],
      ['SAR', 'ريال سعودي', 'Saudi Riyal', 'ر.س', 2],
      ['USD', 'دولار أمريكي', 'US Dollar', r'$', 2],
      ['EUR', 'يورو', 'Euro', '€', 2],
    ];
    for (final r in rows) {
      await db.insert('currencies', {'code': r[0], 'name_ar': r[1], 'name_en': r[2], 'symbol': r[3], 'decimals': r[4], 'builtin': 1},
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Tables holding per-user data (order = safe insert order for restore).
  static const userTables = [
    'exchange_rates', 'accounts', 'categories', 'transactions', 'recurring_rules', 'budgets', 'debts', 'savings_goals',
    'bills', 'bill_payments', 'assets', 'asset_values', 'investments', 'investment_entries', 'audit_log',
  ];
}
