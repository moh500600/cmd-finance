import 'package:sqflite/sqflite.dart';

import '../../core/errors/app_exception.dart';
import '../../core/security/password_hasher.dart';
import '../../core/utils/dates.dart';
import '../../core/utils/ids.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/user.dart';
import '../../domain/repositories/repositories.dart';

/// Built-in categories (translated in the UI by key; users can add their own).
const incomeCategoryKeys = ['salary', 'business', 'sales', 'freelance', 'rent_income', 'investments', 'gifts', 'other_income'];
const expenseCategoryKeys = ['food', 'transport', 'housing', 'utilities', 'internet', 'health', 'education', 'shopping', 'entertainment', 'travel', 'bills', 'fees', 'other_expense'];
const _palette = [0xFF0F766E, 0xFF2563EB, 0xFFF59E0B, 0xFF7C3AED, 0xFFDB2777, 0xFF059669, 0xFFEA580C, 0xFF0891B2, 0xFF65A30D, 0xFFDC2626, 0xFF4F46E5, 0xFF64748B, 0xFF9333EA];

/// Local accounts: PBKDF2-hashed password + one-time recovery code (hashed).
class AuthRepositoryImpl implements AuthRepository {
  final Database db;
  final PasswordHasher hasher;
  AuthRepositoryImpl(this.db, {this.hasher = const PasswordHasher()});

  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  Future<SignUpResult> signUp({required String name, required String email, required String password, required String baseCurrency}) async {
    final n = name.trim(), e = email.trim().toLowerCase();
    if (n.length < 2) throw const AppException('err_name_short');
    if (!_emailRe.hasMatch(e)) throw const AppException('err_email_invalid');
    if (password.length < 6) throw const AppException('err_password_short');
    final exists = await db.query('users', where: 'email = ?', whereArgs: [e]);
    if (exists.isNotEmpty) throw const AppException('err_email_taken');
    final id = newId();
    final salt = PasswordHasher.newSalt(), rsalt = PasswordHasher.newSalt();
    final code = PasswordHasher.newRecoveryCode();
    final now = nowUtc();
    await db.transaction((t) async {
      await t.insert('users', {
        'id': id, 'name': n, 'email': e, 'password_hash': hasher.hash(password, salt), 'salt': salt,
        'recovery_hash': hasher.hash(code, rsalt), 'recovery_salt': rsalt, 'base_currency': baseCurrency,
        'created_at': now, 'updated_at': now,
      });
      var i = 0;
      for (final k in incomeCategoryKeys) {
        await t.insert('categories', {'id': newId(), 'user_id': id, 'kind': CategoryKind.income.name, 'key': k, 'name': k, 'icon': 0, 'color': _palette[i++ % _palette.length], 'updated_at': now});
      }
      for (final k in expenseCategoryKeys) {
        await t.insert('categories', {'id': newId(), 'user_id': id, 'kind': CategoryKind.expense.name, 'key': k, 'name': k, 'icon': 0, 'color': _palette[i++ % _palette.length], 'updated_at': now});
      }
      await t.insert('audit_log', {'id': newId(), 'user_id': id, 'entity': 'users', 'entity_id': id, 'action': 'create', 'after_json': '{"email":"$e"}', 'at': now});
    });
    return SignUpResult((await getUser(id))!, code);
  }

  @override
  Future<AppUser> signIn(String email, String password) async {
    final r = await db.query('users', where: 'email = ?', whereArgs: [email.trim().toLowerCase()]);
    if (r.isEmpty || !hasher.verify(password, r.first['salt'] as String, r.first['password_hash'] as String)) {
      throw const AppException('err_bad_credentials');
    }
    return AppUser.fromMap(r.first);
  }

  @override
  Future<AppUser?> getUser(String id) async {
    final r = await db.query('users', where: 'id = ?', whereArgs: [id]);
    return r.isEmpty ? null : AppUser.fromMap(r.first);
  }

  @override
  Future<String> resetPassword({required String email, required String recoveryCode, required String newPassword}) async {
    final r = await db.query('users', where: 'email = ?', whereArgs: [email.trim().toLowerCase()]);
    final code = recoveryCode.trim().toUpperCase();
    if (r.isEmpty || !hasher.verify(code, r.first['recovery_salt'] as String, r.first['recovery_hash'] as String)) {
      throw const AppException('err_bad_recovery');
    }
    if (newPassword.length < 6) throw const AppException('err_password_short');
    final salt = PasswordHasher.newSalt(), rsalt = PasswordHasher.newSalt();
    final fresh = PasswordHasher.newRecoveryCode(); // codes are single-use
    await db.update('users', {
      'password_hash': hasher.hash(newPassword, salt), 'salt': salt, 'recovery_hash': hasher.hash(fresh, rsalt), 'recovery_salt': rsalt, 'updated_at': nowUtc(),
    }, where: 'id = ?', whereArgs: [r.first['id']]);
    await db.insert('audit_log', {'id': newId(), 'user_id': r.first['id'], 'entity': 'users', 'entity_id': r.first['id'], 'action': 'password_reset', 'at': nowUtc()});
    return fresh;
  }

  @override
  Future<void> changePassword(String uid, String oldPassword, String newPassword) async {
    final r = await db.query('users', where: 'id = ?', whereArgs: [uid]);
    if (r.isEmpty || !hasher.verify(oldPassword, r.first['salt'] as String, r.first['password_hash'] as String)) {
      throw const AppException('err_bad_credentials');
    }
    if (newPassword.length < 6) throw const AppException('err_password_short');
    final salt = PasswordHasher.newSalt();
    await db.update('users', {'password_hash': hasher.hash(newPassword, salt), 'salt': salt, 'updated_at': nowUtc()}, where: 'id = ?', whereArgs: [uid]);
    await db.insert('audit_log', {'id': newId(), 'user_id': uid, 'entity': 'users', 'entity_id': uid, 'action': 'password_change', 'at': nowUtc()});
  }

  @override
  Future<AppUser> updateProfile(String uid, {required String name, required String email, String? avatarPath}) async {
    final n = name.trim(), e = email.trim().toLowerCase();
    if (n.length < 2) throw const AppException('err_name_short');
    if (!_emailRe.hasMatch(e)) throw const AppException('err_email_invalid');
    final clash = await db.query('users', where: 'email = ? AND id <> ?', whereArgs: [e, uid]);
    if (clash.isNotEmpty) throw const AppException('err_email_taken');
    await db.update('users', {'name': n, 'email': e, 'avatar_path': avatarPath, 'updated_at': nowUtc()}, where: 'id = ?', whereArgs: [uid]);
    return (await getUser(uid))!;
  }

  @override
  Future<void> deleteAccount(String uid, String password) async {
    final r = await db.query('users', where: 'id = ?', whereArgs: [uid]);
    if (r.isEmpty || !hasher.verify(password, r.first['salt'] as String, r.first['password_hash'] as String)) {
      throw const AppException('err_bad_credentials');
    }
    await db.transaction((t) async {
      // child rows first (FKs between user tables are not all cascading)
      for (final table in const ['bill_payments', 'asset_values', 'investment_entries', 'audit_log', 'sessions', 'recurring_rules', 'budgets']) {
        await t.delete(table, where: 'user_id = ?', whereArgs: [uid]);
      }
      await t.update('transactions', {'parent_id': null}, where: 'user_id = ?', whereArgs: [uid]);
      for (final table in const ['transactions', 'bills', 'debts', 'savings_goals', 'assets', 'investments', 'categories', 'accounts', 'exchange_rates', 'users']) {
        await t.delete(table, where: table == 'users' ? 'id = ?' : 'user_id = ?', whereArgs: [uid]);
      }
    });
  }

  @override
  Future<SessionInfo> startSession(String uid, String device) async {
    final now = nowUtc();
    final id = newId();
    await db.insert('sessions', {'id': id, 'user_id': uid, 'device': device, 'created_at': now, 'last_seen_at': now});
    return SessionInfo.fromMap((await db.query('sessions', where: 'id = ?', whereArgs: [id])).first);
  }

  @override
  Future<List<SessionInfo>> sessions(String uid) async =>
      (await db.query('sessions', where: 'user_id = ?', whereArgs: [uid], orderBy: 'last_seen_at DESC')).map(SessionInfo.fromMap).toList();

  @override
  Future<void> revokeSession(String uid, String sessionId) async =>
      db.update('sessions', {'revoked_at': nowUtc()}, where: 'id = ? AND user_id = ?', whereArgs: [sessionId, uid]);

  @override
  Future<bool> isSessionActive(String sessionId) async {
    final r = await db.query('sessions', where: 'id = ? AND revoked_at IS NULL', whereArgs: [sessionId]);
    return r.isNotEmpty;
  }

  @override
  Future<void> touchSession(String sessionId) async => db.update('sessions', {'last_seen_at': nowUtc()}, where: 'id = ?', whereArgs: [sessionId]);
}
