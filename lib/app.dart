import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'presentation/providers/providers.dart';
import 'presentation/screens/auth/auth_screen.dart';
import 'presentation/screens/auth/lock_screen.dart';
import 'presentation/screens/shell/home_shell.dart';

class FinanceProApp extends ConsumerStatefulWidget {
  const FinanceProApp({super.key});
  @override
  ConsumerState<FinanceProApp> createState() => _FinanceProAppState();
}

class _FinanceProAppState extends ConsumerState<FinanceProApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await ref.read(notificationServiceProvider).init();
      if (ref.read(sessionProvider) != null) await ref.read(actionsProvider).startup();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) ref.read(lockProvider.notifier).lock();
    if (state == AppLifecycleState.resumed && ref.read(sessionProvider) != null) ref.read(actionsProvider).startup();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    final user = ref.watch(sessionProvider);
    final locked = ref.watch(lockProvider);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: s.lang == 'ar' ? 'CMD Finance' : 'CMD Finance',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: s.theme,
      locale: Locale(s.lang),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: user == null ? const AuthScreen() : (locked ? const LockScreen() : const HomeShell()),
    );
  }
}
