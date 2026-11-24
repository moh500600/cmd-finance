import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/security/password_hasher.dart';

class NotificationPrefs {
  final bool largeExpense, lowBalance, budget, bills, debts, goals, daily, weekly, monthly;
  final String largeExpenseThreshold; // base currency, decimal string ('' = off)
  final int dailyHour;
  const NotificationPrefs({this.largeExpense = true, this.lowBalance = true, this.budget = true, this.bills = true, this.debts = true,
      this.goals = true, this.daily = false, this.weekly = true, this.monthly = true, this.largeExpenseThreshold = '', this.dailyHour = 21});

  NotificationPrefs copyWith({bool? largeExpense, bool? lowBalance, bool? budget, bool? bills, bool? debts, bool? goals, bool? daily, bool? weekly,
          bool? monthly, String? largeExpenseThreshold, int? dailyHour}) =>
      NotificationPrefs(largeExpense: largeExpense ?? this.largeExpense, lowBalance: lowBalance ?? this.lowBalance, budget: budget ?? this.budget,
          bills: bills ?? this.bills, debts: debts ?? this.debts, goals: goals ?? this.goals, daily: daily ?? this.daily, weekly: weekly ?? this.weekly,
          monthly: monthly ?? this.monthly, largeExpenseThreshold: largeExpenseThreshold ?? this.largeExpenseThreshold, dailyHour: dailyHour ?? this.dailyHour);
}

class AppSettings {
  final String lang;
  final ThemeMode theme;
  final NotificationPrefs notifications;
  final bool lockEnabled;
  final bool biometric;
  final bool hideAmounts;
  const AppSettings({this.lang = 'ar', this.theme = ThemeMode.system, this.notifications = const NotificationPrefs(), this.lockEnabled = false,
      this.biometric = false, this.hideAmounts = false});
  AppSettings copyWith({String? lang, ThemeMode? theme, NotificationPrefs? notifications, bool? lockEnabled, bool? biometric, bool? hideAmounts}) =>
      AppSettings(lang: lang ?? this.lang, theme: theme ?? this.theme, notifications: notifications ?? this.notifications,
          lockEnabled: lockEnabled ?? this.lockEnabled, biometric: biometric ?? this.biometric, hideAmounts: hideAmounts ?? this.hideAmounts);
}

/// Device-level preferences (language, theme, alerts, app lock, session).
class SettingsRepository {
  final SharedPreferences p;
  SettingsRepository(this.p);

  AppSettings load() => AppSettings(
        lang: p.getString('lang') ?? 'ar',
        theme: ThemeMode.values[p.getInt('theme') ?? ThemeMode.system.index],
        lockEnabled: p.getString('pin_hash') != null,
        biometric: p.getBool('biometric') ?? false,
        hideAmounts: p.getBool('hide_amounts') ?? false,
        notifications: NotificationPrefs(
          largeExpense: p.getBool('n_large') ?? true, lowBalance: p.getBool('n_low') ?? true, budget: p.getBool('n_budget') ?? true,
          bills: p.getBool('n_bills') ?? true, debts: p.getBool('n_debts') ?? true, goals: p.getBool('n_goals') ?? true,
          daily: p.getBool('n_daily') ?? false, weekly: p.getBool('n_weekly') ?? true, monthly: p.getBool('n_monthly') ?? true,
          largeExpenseThreshold: p.getString('n_large_threshold') ?? '', dailyHour: p.getInt('n_daily_hour') ?? 21,
        ),
      );

  Future<void> save(AppSettings s) async {
    await p.setString('lang', s.lang);
    await p.setInt('theme', s.theme.index);
    await p.setBool('biometric', s.biometric);
    await p.setBool('hide_amounts', s.hideAmounts);
    final n = s.notifications;
    await p.setBool('n_large', n.largeExpense);
    await p.setBool('n_low', n.lowBalance);
    await p.setBool('n_budget', n.budget);
    await p.setBool('n_bills', n.bills);
    await p.setBool('n_debts', n.debts);
    await p.setBool('n_goals', n.goals);
    await p.setBool('n_daily', n.daily);
    await p.setBool('n_weekly', n.weekly);
    await p.setBool('n_monthly', n.monthly);
    await p.setString('n_large_threshold', n.largeExpenseThreshold);
    await p.setInt('n_daily_hour', n.dailyHour);
  }

  String? get sessionUserId => p.getString('session_uid');
  String? get sessionId => p.getString('session_id');
  Future<void> setSession(String? uid, String? sessionId) async {
    if (uid == null) {
      await p.remove('session_uid');
      await p.remove('session_id');
    } else {
      await p.setString('session_uid', uid);
      await p.setString('session_id', sessionId!);
    }
  }

  // ---- app lock (PIN is PBKDF2-hashed; never stored in clear)
  Future<void> setPin(String? pin) async {
    if (pin == null) {
      await p.remove('pin_hash');
      await p.remove('pin_salt');
      await p.setBool('biometric', false);
      return;
    }
    final salt = PasswordHasher.newSalt();
    await p.setString('pin_salt', salt);
    await p.setString('pin_hash', const PasswordHasher(iterations: 5000).hash(pin, salt));
  }

  bool verifyPin(String pin) {
    final h = p.getString('pin_hash'), s = p.getString('pin_salt');
    if (h == null || s == null) return true;
    return const PasswordHasher(iterations: 5000).verify(pin, s, h);
  }
}
