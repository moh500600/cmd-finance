import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'core/platform/database_bootstrap.dart';
import 'data/db/app_database.dart';
import 'data/repositories/auth_repository_impl.dart';
import 'data/services/settings_repository.dart';
import 'domain/entities/user.dart';
import 'presentation/providers/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ar');
  await initializeDateFormatting('en');
  final prefs = await SharedPreferences.getInstance();
  // sqflite on Android/iOS, sqflite_common_ffi on Windows/Linux (same schema).
  final dbLocation = await resolveDatabase('finance_pro.db');
  final db = await AppDatabase.open(dbLocation.factory, dbLocation.path);

  // Restore the session only if it was not revoked (Settings → Sessions).
  AppUser? user;
  final settings = SettingsRepository(prefs);
  final uid = settings.sessionUserId, sid = settings.sessionId;
  if (uid != null && sid != null) {
    final auth = AuthRepositoryImpl(db);
    if (await auth.isSessionActive(sid)) {
      user = await auth.getUser(uid);
      if (user != null) await auth.touchSession(sid);
    }
    if (user == null) await settings.setSession(null, null);
  }

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPrefsProvider.overrideWithValue(prefs),
      initialUserProvider.overrideWithValue(user),
    ],
    child: const FinanceProApp(),
  ));
}
