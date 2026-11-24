import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

/// Sign in / create account / reset password with the recovery code.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

enum _Mode { login, signup, reset }

class _AuthScreenState extends ConsumerState<AuthScreen> {
  _Mode mode = _Mode.login;
  final _form = GlobalKey<FormState>();
  final name = TextEditingController(), email = TextEditingController(), pass = TextEditingController(), code = TextEditingController();
  String base = 'YER';
  bool busy = false, obscure = true;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => busy = true);
    final auth = ref.read(authRepositoryProvider);
    final l = context.l;
    await guard(context, () async {
      switch (mode) {
        case _Mode.login:
          final u = await auth.signIn(email.text, pass.text);
          await ref.read(sessionProvider.notifier).signIn(u);
          await ref.read(actionsProvider).startup();
        case _Mode.signup:
          final r = await auth.signUp(name: name.text, email: email.text, password: pass.text, baseCurrency: base);
          if (mounted) await _showCode(l.tr('recovery_code_title'), r.recoveryCode);
          await ref.read(sessionProvider.notifier).signIn(r.user);
        case _Mode.reset:
          final fresh = await auth.resetPassword(email: email.text, recoveryCode: code.text, newPassword: pass.text);
          if (mounted) await _showCode(l.tr('new_recovery_code'), fresh);
          setState(() => mode = _Mode.login);
      }
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> _showCode(String title, String code) => showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => AlertDialog(
          icon: const Icon(Icons.key_rounded, color: AppColors.gold),
          title: Text(title),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(c.tr('recovery_code_body')),
            const SizedBox(height: 14),
            SelectableText(code, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 2), textDirection: TextDirection.ltr),
          ]),
          actions: [
            TextButton(onPressed: () => Clipboard.setData(ClipboardData(text: code)), child: Text(c.tr('copy'))),
            FilledButton(onPressed: () => Navigator.pop(c), child: Text(c.tr('saved_it'))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      icon: const Icon(Icons.translate_rounded),
                      label: Text(settings.lang == 'ar' ? 'English' : 'العربية'),
                      onPressed: () => ref.read(settingsProvider.notifier).update((s) => s.copyWith(lang: s.lang == 'ar' ? 'en' : 'ar')),
                    ),
                  ),
                  Container(
                    height: 84,
                    width: 84,
                    alignment: Alignment.center,
                    margin: const EdgeInsets.symmetric(horizontal: 120),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [AppColors.primary, AppColors.primaryDark], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 44),
                  ),
                  const SizedBox(height: 16),
                  Text(l.tr('app_name'), textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  Text(l.tr('app_tagline'), textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  SegmentedButton<_Mode>(
                    segments: [
                      ButtonSegment(value: _Mode.login, label: Text(l.tr('login'))),
                      ButtonSegment(value: _Mode.signup, label: Text(l.tr('signup'))),
                    ],
                    selected: {mode == _Mode.reset ? _Mode.login : mode},
                    onSelectionChanged: (s) => setState(() => mode = s.first),
                  ),
                  const SizedBox(height: 18),
                  if (mode == _Mode.signup) ...[
                    TextFormField(controller: name, decoration: InputDecoration(labelText: l.tr('name'), prefixIcon: const Icon(Icons.person_outline)),
                        validator: (v) => (v ?? '').trim().length < 2 ? l.tr('err_name_short') : null),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(controller: email, keyboardType: TextInputType.emailAddress, textDirection: TextDirection.ltr,
                      decoration: InputDecoration(labelText: l.tr('email'), prefixIcon: const Icon(Icons.alternate_email_rounded)),
                      validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : l.tr('err_email_invalid')),
                  const SizedBox(height: 12),
                  if (mode == _Mode.reset) ...[
                    TextFormField(controller: code, textDirection: TextDirection.ltr, textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(labelText: l.tr('recovery_code'), prefixIcon: const Icon(Icons.key_rounded)),
                        validator: (v) => (v ?? '').trim().length < 12 ? l.tr('required') : null),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: pass,
                    obscureText: obscure,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: mode == _Mode.reset ? l.tr('new_password') : l.tr('password'),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined), onPressed: () => setState(() => obscure = !obscure)),
                    ),
                    validator: (v) => (v ?? '').length < 6 ? l.tr('err_password_short') : null,
                  ),
                  if (mode == _Mode.signup) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: base,
                      decoration: InputDecoration(labelText: l.tr('base_currency'), prefixIcon: const Icon(Icons.currency_exchange_rounded), helperText: l.tr('base_currency_help')),
                      items: [for (final c in const ['YER', 'SAR', 'USD', 'EUR']) DropdownMenuItem(value: c, child: Text('$c · ${l.tr('ccy_$c')}'))],
                      onChanged: (v) => setState(() => base = v!),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy ? null : _submit,
                    child: busy
                        ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(switch (mode) { _Mode.login => l.tr('login'), _Mode.signup => l.tr('create_account'), _Mode.reset => l.tr('reset_password') }),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => mode = mode == _Mode.reset ? _Mode.login : _Mode.reset),
                    child: Text(mode == _Mode.reset ? l.tr('back_to_login') : l.tr('forgot_password')),
                  ),
                  const SizedBox(height: 8),
                  Text(l.tr('local_account_note'), textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
