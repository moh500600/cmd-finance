import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/platform/desktop_files.dart';
import '../../../core/platform/platform_support.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/money/money.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/entities/transaction.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../core/theme/app_theme.dart';
import '../../../data/services/import_service.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import 'currencies_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final s = ref.watch(settingsProvider);
    final user = ref.watch(sessionProvider)!;
    final sn = ref.read(settingsProvider.notifier);
    Widget nav(IconData i, String k, Widget page, {String? sub}) => ListTile(
        leading: Icon(i), title: Text(l.tr(k)), subtitle: sub == null ? null : Text(sub), trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)));
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('menu_settings'))),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 32), children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(backgroundColor: AppColors.primary, child: Text(user.name.isEmpty ? '?' : user.name.characters.first, style: const TextStyle(color: Colors.white))),
            title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(user.email),
            trailing: const Icon(Icons.edit_rounded),
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
          ),
        ),
        SectionTitle(l.tr('general')),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.language_rounded),
              title: Text(l.tr('language')),
              trailing: SegmentedButton<String>(
                segments: const [ButtonSegment(value: 'ar', label: Text('عربي')), ButtonSegment(value: 'en', label: Text('EN'))],
                selected: {s.lang},
                onSelectionChanged: (v) => sn.update((x) => x.copyWith(lang: v.first)),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode_outlined),
              title: Text(l.tr('theme')),
              trailing: DropdownButton<ThemeMode>(
                value: s.theme,
                underline: const SizedBox(),
                items: [for (final m in ThemeMode.values) DropdownMenuItem(value: m, child: Text(l.tr('theme_${m.name}')))],
                onChanged: (v) => sn.update((x) => x.copyWith(theme: v)),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.visibility_off_outlined),
              title: Text(l.tr('hide_amounts')),
              value: s.hideAmounts,
              onChanged: (v) => sn.update((x) => x.copyWith(hideAmounts: v)),
            ),
            nav(Icons.currency_exchange_rounded, 'menu_currencies', const CurrenciesScreen(), sub: '${l.tr('base_currency')}: ${user.baseCurrency}'),
          ]),
        ),
        SectionTitle(l.tr('notifications')),
        Card(child: nav(Icons.notifications_active_outlined, 'notification_settings', const NotificationSettingsScreen())),
        SectionTitle(l.tr('privacy_security')),
        Card(
          child: Column(children: [
            nav(Icons.lock_outline_rounded, 'app_lock', const SecurityScreen(), sub: l.tr(s.lockEnabled ? 'enabled' : 'disabled')),
            nav(Icons.password_rounded, 'change_password', const ChangePasswordScreen()),
            nav(Icons.devices_rounded, 'sessions', const SessionsScreen()),
          ]),
        ),
        SectionTitle(l.tr('data')),
        Card(
          child: Column(children: [
            nav(Icons.backup_rounded, 'backup_restore', const DataScreen()),
            nav(Icons.group_outlined, 'sharing', const SharingScreen()),
          ]),
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          icon: const Icon(Icons.logout_rounded),
          label: Text(l.tr('sign_out')),
          onPressed: () async {
            if (await confirm(context, l.tr('sign_out'), l.tr('sign_out_note'))) {
              await ref.read(sessionProvider.notifier).signOut();
              if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
            }
          },
        ),
        const SizedBox(height: 8),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: AppColors.expense),
          icon: const Icon(Icons.delete_forever_rounded),
          label: Text(l.tr('delete_account')),
          onPressed: () => _deleteAccount(context, ref),
        ),
        const SizedBox(height: 12),
        Center(child: Text('${l.tr('app_name')} · v1.0.0', style: Theme.of(context).textTheme.bodySmall)),
      ]),
    );
  }

  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    final pw = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.tr('delete_account')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(l.tr('delete_account_note')),
          const SizedBox(height: 12),
          TextField(controller: pw, obscureText: true, decoration: InputDecoration(labelText: l.tr('password'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(l.tr('cancel'))),
          FilledButton(style: FilledButton.styleFrom(backgroundColor: AppColors.expense), onPressed: () => Navigator.pop(c, true), child: Text(l.tr('delete_forever'))),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final done = await guard(context, () async {
      await ref.read(authRepositoryProvider).deleteAccount(ref.read(sessionProvider)!.id, pw.text);
      await ref.read(settingsRepositoryProvider).setPin(null);
      await ref.read(sessionProvider.notifier).signOut();
      return true;
    });
    if (done == true && context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }
}

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final u = ref.read(sessionProvider)!;
  late final name = TextEditingController(text: u.name), email = TextEditingController(text: u.email);
  final form = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('profile'))),
      body: Form(
        key: form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: name, decoration: InputDecoration(labelText: l.tr('full_name')), validator: (v) => (v ?? '').trim().isEmpty ? l.tr('required') : null),
          const SizedBox(height: 10),
          TextFormField(controller: email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: l.tr('email')),
              validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v ?? '') ? null : l.tr('err_email')),
          const SizedBox(height: 10),
          ListTile(contentPadding: EdgeInsets.zero, title: Text(l.tr('member_since')), trailing: Text(fmtDate(context, u.createdAt.toLocal()))),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              final nu = await guard(context, () => ref.read(authRepositoryProvider).updateProfile(u.id, name: name.text, email: email.text), success: l.tr('saved'));
              if (nu != null) {
                ref.read(sessionProvider.notifier).refresh(nu);
                if (context.mounted) Navigator.pop(context);
              }
            },
            child: Text(l.tr('save')),
          ),
        ]),
      ),
    );
  }
}

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final old = TextEditingController(), pw = TextEditingController(), pw2 = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('change_password'))),
      body: Form(
        key: form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          TextFormField(controller: old, obscureText: true, decoration: InputDecoration(labelText: l.tr('current_password'))),
          const SizedBox(height: 10),
          TextFormField(controller: pw, obscureText: true, decoration: InputDecoration(labelText: l.tr('new_password')), validator: (v) => (v ?? '').length < 8 ? l.tr('err_password_short') : null),
          const SizedBox(height: 10),
          TextFormField(controller: pw2, obscureText: true, decoration: InputDecoration(labelText: l.tr('confirm_password')), validator: (v) => v != pw.text ? l.tr('err_password_match') : null),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              final ok = await guard(context, () => ref.read(authRepositoryProvider).changePassword(ref.read(sessionProvider)!.id, old.text, pw.text).then((_) => true), success: l.tr('password_changed'));
              if (ok == true && context.mounted) Navigator.pop(context);
            },
            child: Text(l.tr('save')),
          ),
        ]),
      ),
    );
  }
}

class SessionsScreen extends ConsumerWidget {
  const SessionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final current = ref.read(settingsRepositoryProvider).sessionId;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('sessions'))),
      body: AsyncBody(ref.watch(sessionsProvider), (list) => ListView(padding: const EdgeInsets.all(16), children: [
            InfoBanner(Icons.info_outline_rounded, l.tr('sessions_note'), color: AppColors.transfer),
            const SizedBox(height: 10),
            Card(
              child: Column(children: [
                for (final s in list)
                  ListTile(
                    leading: Icon(s.id == current ? Icons.smartphone_rounded : Icons.devices_other_rounded, color: s.active ? AppColors.primary : Colors.grey),
                    title: Text(s.device + (s.id == current ? ' · ${l.tr('this_device')}' : '')),
                    subtitle: Text('${l.tr('last_seen')}: ${fmtDate(context, s.lastSeenAt.toLocal(), time: true)}${s.active ? '' : ' · ${l.tr('revoked')}'}'),
                    trailing: s.active && s.id != current
                        ? TextButton(
                            onPressed: () => guard(context, () => ref.read(actionsProvider).run((u) => ref.read(authRepositoryProvider).revokeSession(u, s.id))),
                            child: Text(l.tr('revoke')))
                        : null,
                  ),
              ]),
            ),
          ])),
    );
  }
}

class SecurityScreen extends ConsumerWidget {
  const SecurityScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final s = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('app_lock'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: Column(children: [
            SwitchListTile(
              secondary: const Icon(Icons.pin_rounded),
              title: Text(l.tr('pin_lock')),
              subtitle: Text(l.tr('pin_lock_note')),
              value: s.lockEnabled,
              onChanged: (v) async {
                if (v) {
                  final pin = await _askPin(context);
                  if (pin == null) return;
                  await ref.read(settingsRepositoryProvider).setPin(pin);
                } else {
                  await ref.read(settingsRepositoryProvider).setPin(null);
                }
                ref.read(settingsProvider.notifier).reload();
                if (context.mounted) showSnack(context, l.tr('saved'));
              },
            ),
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint_rounded),
              title: Text(l.tr('biometric')),
              subtitle: Text(l.tr(!PlatformSupport.biometrics
                  ? 'biometric_desktop_note'
                  : s.lockEnabled
                      ? 'biometric_note'
                      : 'biometric_needs_pin')),
              value: s.biometric && PlatformSupport.biometrics,
              // No biometric backend on this OS (e.g. Linux): the PIN lock still works.
              onChanged: !s.lockEnabled || !PlatformSupport.biometrics
                  ? null
                  : (v) async {
                      if (v) {
                        try {
                          final auth = LocalAuthentication();
                          if (!await auth.isDeviceSupported()) {
                            if (context.mounted) showSnack(context, l.tr('biometric_unavailable'), error: true);
                            return;
                          }
                          if (!context.mounted) return;
                          if (!await auth.authenticate(localizedReason: l.tr('unlock_reason'))) return;
                        } on PlatformException catch (_) {
                          if (context.mounted) showSnack(context, l.tr('biometric_unavailable'), error: true);
                          return;
                        }
                      }
                      await ref.read(settingsProvider.notifier).update((x) => x.copyWith(biometric: v));
                    },
            ),
          ]),
        ),
      ]),
    );
  }

  Future<String?> _askPin(BuildContext context) async {
    final l = context.l;
    final a = TextEditingController(), b = TextEditingController();
    String? err;
    return showDialog<String>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: Text(l.tr('set_pin')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: a, obscureText: true, keyboardType: TextInputType.number, maxLength: 6, decoration: InputDecoration(labelText: l.tr('pin_4_6'))),
            TextField(controller: b, obscureText: true, keyboardType: TextInputType.number, maxLength: 6, decoration: InputDecoration(labelText: l.tr('confirm_pin'), errorText: err)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: Text(l.tr('cancel'))),
            FilledButton(
              onPressed: () {
                final p = Money.normalizeDigits(a.text);
                if (!RegExp(r'^\d{4,6}$').hasMatch(p)) return set(() => err = l.tr('err_pin'));
                if (p != Money.normalizeDigits(b.text)) return set(() => err = l.tr('err_pin_match'));
                Navigator.pop(c, p);
              },
              child: Text(l.tr('save')),
            ),
          ],
        ),
      ),
    );
  }
}

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final n = ref.watch(settingsProvider).notifications;
    final base = ref.watch(sessionProvider)!.baseCurrency;
    Future<void> set(dynamic Function(dynamic) f) async {
      await ref.read(settingsProvider.notifier).update((x) => x.copyWith(notifications: f(x.notifications)));
      await ref.read(notificationServiceProvider).requestPermissions();
      await ref.read(actionsProvider).rescheduleReminders();
    }

    Widget sw(String k, bool v, dynamic Function(dynamic, bool) f) => SwitchListTile(title: Text(l.tr(k)), value: v, onChanged: (x) => set((p) => f(p, x)));
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('notification_settings'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SectionTitle(l.tr('instant_alerts')),
        Card(
          child: Column(children: [
            sw('n_large_expense', n.largeExpense, (p, x) => p.copyWith(largeExpense: x)),
            if (n.largeExpense)
              ListTile(
                title: Text(l.tr('large_expense_threshold')),
                subtitle: Text(n.largeExpenseThreshold.isEmpty ? l.tr('auto_threshold') : Money.format(Money.parse(n.largeExpenseThreshold), currency: base)),
                trailing: const Icon(Icons.edit_rounded),
                onTap: () async {
                  final c = TextEditingController(text: n.largeExpenseThreshold);
                  final v = await showDialog<String>(
                    context: context,
                    builder: (d) => AlertDialog(
                      title: Text(l.tr('large_expense_threshold')),
                      content: TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: InputDecoration(suffixText: base, helperText: l.tr('auto_threshold'))),
                      actions: [TextButton(onPressed: () => Navigator.pop(d, ''), child: Text(l.tr('auto'))), FilledButton(onPressed: () => Navigator.pop(d, c.text), child: Text(l.tr('save')))],
                    ),
                  );
                  if (v == null) return;
                  final parsed = Money.tryParse(v);
                  await set((p) => p.copyWith(largeExpenseThreshold: parsed == null ? '' : parsed.toString()));
                },
              ),
            sw('n_low_balance', n.lowBalance, (p, x) => p.copyWith(lowBalance: x)),
            sw('n_budget', n.budget, (p, x) => p.copyWith(budget: x)),
            sw('n_goals', n.goals, (p, x) => p.copyWith(goals: x)),
          ]),
        ),
        SectionTitle(l.tr('reminders')),
        Card(
          child: Column(children: [
            sw('n_bills', n.bills, (p, x) => p.copyWith(bills: x)),
            sw('n_debts', n.debts, (p, x) => p.copyWith(debts: x)),
          ]),
        ),
        SectionTitle(l.tr('summaries')),
        Card(
          child: Column(children: [
            sw('n_daily', n.daily, (p, x) => p.copyWith(daily: x)),
            if (n.daily)
              ListTile(
                title: Text(l.tr('daily_time')),
                trailing: Text('${n.dailyHour.toString().padLeft(2, '0')}:00', textDirection: TextDirection.ltr),
                onTap: () async {
                  final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: n.dailyHour, minute: 0));
                  if (t != null) await set((p) => p.copyWith(dailyHour: t.hour));
                },
              ),
            sw('n_weekly', n.weekly, (p, x) => p.copyWith(weekly: x)),
            sw('n_monthly', n.monthly, (p, x) => p.copyWith(monthly: x)),
          ]),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          icon: const Icon(Icons.notifications_rounded),
          label: Text(l.tr('test_notification')),
          onPressed: () async {
            await ref.read(notificationServiceProvider).requestPermissions();
            await ref.read(notificationServiceProvider).showNow(999, l.tr('app_name'), l.tr('test_notification_body'));
          },
        ),
      ]),
    );
  }
}

class DataScreen extends ConsumerWidget {
  const DataScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('backup_restore'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        InfoBanner(Icons.shield_outlined, l.tr('backup_note'), color: AppColors.transfer),
        const SizedBox(height: 10),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.download_rounded, color: AppColors.primary),
              title: Text(l.tr('create_backup')),
              subtitle: Text(l.tr('create_backup_sub')),
              onTap: () => guard(context, () async {
                final data = await ref.read(backupRepositoryProvider).export(ref.read(sessionProvider)!.id);
                final f = await ref.read(exportServiceProvider).backupJson(const JsonEncoder.withIndent(' ').convert(data));
                if (!context.mounted) return;
                await shareOrSaveFile(context, f, text: l.tr('app_name'));
              }),
            ),
            ListTile(
              leading: const Icon(Icons.restore_rounded, color: AppColors.warning),
              title: Text(l.tr('restore_backup')),
              subtitle: Text(l.tr('restore_backup_sub')),
              onTap: () async {
                final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
                if (f == null || !context.mounted) return;
                final bytes = await f.xFile.readAsBytes();
                if (!context.mounted) return;
                if (!await confirm(context, l.tr('restore_backup'), l.tr('restore_confirm'), danger: true) || !context.mounted) return;
                await guard(context, () => ref.read(actionsProvider).run((u) => ref.read(backupRepositoryProvider).restore(u, jsonDecode(utf8.decode(bytes)) as Map<String, Object?>)),
                    success: l.tr('restore_done'));
              },
            ),
          ]),
        ),
        SectionTitle(l.tr('import_export')),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.upload_file_rounded, color: AppColors.income),
              title: Text(l.tr('import_csv_excel')),
              subtitle: Text(l.tr('import_columns', {'cols': ImportService.columns.join(', ')})),
              onTap: () => _import(context, ref),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: Text(l.tr('import_template')),
              onTap: () => guard(context, () async {
                final f = await ref.read(exportServiceProvider).table('finance_pro_import_template', [
                  ImportService.columns,
                  ['2026-11-01', 'expense', '5000', ref.read(sessionProvider)!.baseCurrency, l.tr('acct_cash'), l.tr('cat_food'), l.tr('lunch'), ''],
                ], excel: false);
                if (!context.mounted) return;
                await shareOrSaveFile(context, f);
              }),
            ),
          ]),
        ),
      ]),
    );
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    final l = context.l;
    final f = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['csv', 'xlsx']);
    if (f == null || !context.mounted) return;
    final bytes = await f.xFile.readAsBytes();
    if (!context.mounted) return;
    final res = await guard(context, () async {
      final rows = f.extension?.toLowerCase().replaceAll('.', '') == 'xlsx' ? ImportService.parseExcel(bytes) : ImportService.parseCsv(bytes);
      return ref.read(actionsProvider).run((u) => ref.read(importServiceProvider).importRows(u, rows, l.category));
    });
    if (res == null || !context.mounted) return;
    await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l.tr('import_result')),
        content: SingleChildScrollView(
          child: Text([
            l.tr('imported_n', {'n': '${res.imported}'}),
            l.tr('skipped_n', {'n': '${res.skipped}'}),
            if (res.errors.isNotEmpty) '${l.tr('errors')}:\n${res.errors.take(30).join('\n')}',
          ].join('\n')),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: Text(l.tr('ok')))],
      ),
    );
  }
}

/// Sharing without a server: export your transactions as a CSV file and send it,
/// the other person imports the same file.
class SharingScreen extends ConsumerWidget {
  const SharingScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('sharing'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        InfoBanner(Icons.share_outlined, l.tr('sharing_file_note'), color: AppColors.transfer),
        const SizedBox(height: 10),
        Card(
          child: Column(children: [
            ListTile(
              leading: const Icon(Icons.ios_share_rounded, color: AppColors.primary),
              title: Text(l.tr('share_export_txn')),
              onTap: () => guard(context, () async {
                final uid = ref.read(sessionProvider)!.id;
                final list = await ref.read(transactionRepositoryProvider).query(uid, const TxnQuery(sort: 'date_asc'));
                final accs = {for (final a in await ref.read(accountRepositoryProvider).accounts(uid)) a.id: a.name};
                final cats = {for (final c in await ref.read(accountRepositoryProvider).categories(uid)) c.id: c};
                final rows = <List<String>>[ImportService.columns];
                for (final t in list) {
                  if (t.type != TxnType.income && t.type != TxnType.expense) continue;
                  final c = cats[t.categoryId];
                  rows.add([isoDay(t.txnDate), t.type.name, t.amount.toString(), t.currency, accs[t.accountId] ?? '', c == null ? '' : l.category(c), t.title, t.notes]);
                }
                final f = await ref.read(exportServiceProvider).table('cmd_finance_transactions', rows, excel: false);
                if (!context.mounted) return;
                await shareOrSaveFile(context, f);
              }),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file_rounded, color: AppColors.income),
              title: Text(l.tr('import_csv_excel')),
              subtitle: Text(l.tr('share_import_sub')),
              onTap: () => const DataScreen()._import(context, ref),
            ),
          ]),
        ),
      ]),
    );
  }
}
