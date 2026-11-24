import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../core/errors/app_exception.dart';
import '../../core/l10n/l10n.dart';
import '../../core/money/money.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/currency.dart';
import '../providers/providers.dart';
import 'visuals.dart';

/// Money text: never rounds through double; hides digits in privacy mode.
class MoneyText extends ConsumerWidget {
  final Decimal amount;
  final String? currency;
  final TextStyle? style;
  final bool colored;
  final bool signed;
  const MoneyText(this.amount, {super.key, this.currency, this.style, this.colored = false, this.signed = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hide = ref.watch(settingsProvider.select((s) => s.hideAmounts));
    final text = hide ? '•••• ${currency ?? ''}'.trim() : Money.format(amount, currency: currency, showSign: signed);
    final color = colored ? (amount.sign < 0 ? AppColors.expense : amount.sign > 0 ? AppColors.income : null) : null;
    return Text(text, style: (style ?? const TextStyle()).copyWith(color: color ?? style?.color, fontFeatures: const [FontFeature.tabularFigures()]),
        textDirection: TextDirection.ltr, overflow: TextOverflow.ellipsis);
  }
}

class SectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.trailing});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          ?trailing,
        ]),
      );
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;
  const EmptyState(this.icon, this.text, {super.key, this.action});
  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: c.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: c.primary),
          ),
          const SizedBox(height: 14),
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: c.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 14), action!],
        ]),
      ),
    );
  }
}

class AsyncBody<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final Widget Function(T data) builder;
  const AsyncBody(this.value, this.builder, {super.key});
  @override
  Widget build(BuildContext context) => value.when(
        data: builder,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(errorText(context, e), textAlign: TextAlign.center))),
      );
}

String errorText(BuildContext context, Object e) {
  final l = context.l;
  if (e is MissingRateException) return l.tr('err_missing_rate', {'from': e.from, 'to': e.to});
  if (e is AppException) return l.tr(e.code, e.args);
  return '${l.tr('err_unexpected')}\n$e';
}

void showSnack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating, backgroundColor: error ? AppColors.expense : null));
}

/// Runs a write and shows a translated error (and the "add rate" path for a missing rate).
Future<T?> guard<T>(BuildContext context, Future<T> Function() body, {String? success}) async {
  try {
    final r = await body();
    if (success != null && context.mounted) showSnack(context, success);
    return r;
  } on MissingRateException catch (e) {
    if (context.mounted) await promptMissingRate(context, e);
  } catch (e) {
    if (context.mounted) showSnack(context, errorText(context, e), error: true);
  }
  return null;
}

/// Honest missing-rate flow: explain, then let the user enter the rate.
Future<void> promptMissingRate(BuildContext context, MissingRateException e) async {
  final add = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const Icon(Icons.currency_exchange_rounded, color: AppColors.warning),
      title: Text(c.tr('missing_rate_title')),
      content: Text(c.tr('err_missing_rate', {'from': e.from, 'to': e.to})),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.tr('cancel'))),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(c.tr('add_rate'))),
      ],
    ),
  );
  if (add == true && context.mounted) {
    await showRateDialog(context, from: e.from, to: e.to, date: e.date);
  }
}

Future<void> showRateDialog(BuildContext context, {String? from, String? to, DateTime? date}) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => RateSheet(from: from, to: to, date: date),
    );

class RateSheet extends ConsumerStatefulWidget {
  final String? from, to;
  final DateTime? date;
  const RateSheet({super.key, this.from, this.to, this.date});
  @override
  ConsumerState<RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends ConsumerState<RateSheet> {
  final _form = GlobalKey<FormState>();
  late String? from = widget.from, to = widget.to;
  final rate = TextEditingController(), source = TextEditingController();
  late DateTime date = widget.date ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    final ccys = ref.watch(currenciesProvider).value ?? const <Currency>[];
    return SheetFrame(
      title: l.tr('add_rate'),
      child: Form(
        key: _form,
        child: Column(children: [
          Row(children: [
            Expanded(child: CurrencyField(value: from, currencies: ccys, label: l.tr('from'), onChanged: (v) => setState(() => from = v))),
            const SizedBox(width: 8),
            Expanded(child: CurrencyField(value: to, currencies: ccys, label: l.tr('to'), onChanged: (v) => setState(() => to = v))),
          ]),
          const SizedBox(height: 12),
          AmountField(controller: rate, label: from == null || to == null ? l.tr('rate') : '1 $from = ? $to', allowZero: false, maxScale: 10),
          const SizedBox(height: 12),
          TextFormField(controller: source, decoration: InputDecoration(labelText: l.tr('rate_source'), hintText: l.tr('rate_source_hint')),
              validator: (v) => (v ?? '').trim().isEmpty ? l.tr('required') : null),
          const SizedBox(height: 12),
          DateField(label: l.tr('rate_date'), value: date, onChanged: (d) => setState(() => date = d)),
          const SizedBox(height: 8),
          Text(l.tr('rate_manual_note'), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.check_rounded),
            label: Text(l.tr('save')),
            onPressed: () async {
              if (!_form.currentState!.validate() || from == null || to == null) return;
              final ok = await guard(context, () => ref.read(actionsProvider).run((u) => ref.read(currencyRepositoryProvider)
                  .addRate(u, from: from!, to: to!, rate: Money.parse(rate.text), source: source.text, date: date)));
              if (ok != null && context.mounted) Navigator.pop(context);
            },
          ),
        ]),
      ),
    );
  }
}

/// Bottom-sheet frame with handle, title and keyboard padding.
class SheetFrame extends StatelessWidget {
  final String title;
  final Widget child;
  const SheetFrame({super.key, required this.title, required this.child});
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              child,
            ]),
          ),
        ),
      );
}

/// Decimal-validated amount input (accepts Arabic digits).
class AmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? suffix;
  final bool allowZero;
  final bool required;
  final int maxScale;
  final ValueChanged<String>? onChanged;
  const AmountField({super.key, required this.controller, required this.label, this.suffix, this.allowZero = false, this.required = true, this.maxScale = 4, this.onChanged});

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩.,٫٬]'))],
        textDirection: TextDirection.ltr,
        onChanged: onChanged,
        decoration: InputDecoration(labelText: label, suffixText: suffix, prefixIcon: const Icon(Icons.numbers_rounded)),
        validator: (v) {
          if ((v ?? '').trim().isEmpty) return required ? context.tr('required') : null;
          final d = Money.tryParse(v);
          if (d == null) return context.tr('err_amount_invalid');
          if (d.sign < 0 || (!allowZero && d.sign == 0)) return context.tr('err_amount_positive');
          if (d.scale > maxScale) return context.tr('err_amount_scale');
          return null;
        },
      );
}

class CurrencyField extends StatelessWidget {
  final String? value;
  final List<Currency> currencies;
  final String label;
  final ValueChanged<String?> onChanged;
  final bool enabled;
  const CurrencyField({super.key, required this.value, required this.currencies, required this.label, required this.onChanged, this.enabled = true});
  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        initialValue: currencies.any((c) => c.code == value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [for (final c in currencies) DropdownMenuItem(value: c.code, child: Text('${c.code} · ${c.name(context.l.ar)}', overflow: TextOverflow.ellipsis))],
        onChanged: enabled ? onChanged : null,
        validator: (v) => v == null ? context.tr('required') : null,
      );
}

class AccountField extends StatelessWidget {
  final String? value;
  final List<Account> accounts;
  final String label;
  final ValueChanged<String?> onChanged;
  final bool required;
  const AccountField({super.key, required this.value, required this.accounts, required this.label, required this.onChanged, this.required = true});
  @override
  Widget build(BuildContext context) {
    final active = accounts.where((a) => a.isActive || a.id == value).toList();
    return DropdownButtonFormField<String?>(
      initialValue: active.any((a) => a.id == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.account_balance_wallet_outlined)),
      items: [
        if (!required) DropdownMenuItem<String?>(value: null, child: Text(context.tr('none'))),
        for (final a in active)
          DropdownMenuItem(value: a.id, child: Row(children: [Icon(accountIcon(a.type), size: 18), const SizedBox(width: 8), Expanded(child: Text('${a.name} (${a.currency})', overflow: TextOverflow.ellipsis))])),
      ],
      onChanged: onChanged,
      validator: (v) => required && v == null ? context.tr('required') : null,
    );
  }
}

class CategoryField extends StatelessWidget {
  final String? value;
  final List<Category> categories;
  final ValueChanged<String?> onChanged;
  final bool allowNone;
  const CategoryField({super.key, required this.value, required this.categories, required this.onChanged, this.allowNone = false});
  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return DropdownButtonFormField<String?>(
      initialValue: categories.any((c) => c.id == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: l.tr('category'), prefixIcon: const Icon(Icons.category_outlined)),
      items: [
        if (allowNone) DropdownMenuItem<String?>(value: null, child: Text(l.tr('all_categories'))),
        for (final c in categories)
          DropdownMenuItem(value: c.id, child: Row(children: [Icon(categoryIcon(c), size: 18, color: Color(c.color)), const SizedBox(width: 8), Expanded(child: Text(l.category(c), overflow: TextOverflow.ellipsis))])),
      ],
      onChanged: onChanged,
      validator: (v) => !allowNone && v == null ? l.tr('required') : null,
    );
  }
}

class DateField extends StatelessWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final bool withTime;
  final VoidCallback? onClear;
  const DateField({super.key, required this.label, required this.value, required this.onChanged, this.withTime = false, this.onClear});
  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat(withTime ? 'yyyy/MM/dd  HH:mm' : 'yyyy/MM/dd', context.l.lang);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final d = await showDatePicker(context: context, initialDate: value ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2100));
        if (d == null || !context.mounted) return;
        var out = DateTime(d.year, d.month, d.day, value?.hour ?? 12, value?.minute ?? 0);
        if (withTime) {
          final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(value ?? DateTime.now()));
          if (t != null) out = DateTime(d.year, d.month, d.day, t.hour, t.minute);
        }
        onChanged(out);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.event_rounded),
            suffixIcon: onClear != null && value != null ? IconButton(icon: const Icon(Icons.clear), onPressed: onClear) : null),
        child: Text(value == null ? '—' : fmt.format(value!)),
      ),
    );
  }
}

Future<bool> confirm(BuildContext context, String title, String body, {String? ok, bool danger = false}) async =>
    await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.tr('cancel'))),
          FilledButton(
              style: danger ? FilledButton.styleFrom(backgroundColor: AppColors.expense) : null,
              onPressed: () => Navigator.pop(c, true),
              child: Text(ok ?? c.tr('confirm'))),
        ],
      ),
    ) ??
    false;

/// Percentage bar (Decimal percent, clamped for display).
class PercentBar extends StatelessWidget {
  final Decimal percent;
  final Color? color;
  const PercentBar(this.percent, {super.key, this.color});
  @override
  Widget build(BuildContext context) {
    final v = (percent.toDouble() / 100).clamp(0.0, 1.0);
    final c = color ?? (percent > Decimal.fromInt(100) ? AppColors.expense : percent >= Decimal.fromInt(80) ? AppColors.warning : AppColors.income);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: LinearProgressIndicator(value: v, minHeight: 8, color: c, backgroundColor: c.withValues(alpha: 0.15)),
    );
  }
}

class InfoBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback? onTap;
  const InfoBanner(this.icon, this.text, {super.key, this.color = AppColors.warning, this.onTap});
  @override
  Widget build(BuildContext context) => Material(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [Icon(icon, color: color, size: 20), const SizedBox(width: 10), Expanded(child: Text(text, style: const TextStyle(fontSize: 13)))]),
          ),
        ),
      );
}

class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBadge(this.icon, this.color, {super.key, this.size = 42});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(size / 3)),
        child: Icon(icon, color: color, size: size * 0.52),
      );
}

String fmtDate(BuildContext context, DateTime d, {bool time = false}) => DateFormat(time ? 'd MMM yyyy، HH:mm' : 'd MMM yyyy', context.l.lang).format(d);

T enumByName<T extends Enum>(List<T> values, String name) => values.firstWhere((e) => e.name == name);
