import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/entities/currency.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';

/// Base currency, currencies list and the full manual exchange-rate history.
class CurrenciesScreen extends ConsumerWidget {
  const CurrenciesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final user = ref.watch(sessionProvider)!;
    final ccys = ref.watch(currenciesProvider).value ?? const <Currency>[];
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('menu_currencies'))),
      floatingActionButton: FloatingActionButton.extended(icon: const Icon(Icons.add_chart_rounded), label: Text(l.tr('add_rate')), onPressed: () => showRateDialog(context)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        InfoBanner(Icons.info_outline_rounded, l.tr('rates_policy'), color: AppColors.transfer),
        SectionTitle(l.tr('base_currency')),
        Card(
          child: ListTile(
            leading: const Icon(Icons.flag_circle_rounded, color: AppColors.primary, size: 32),
            title: Text('${user.baseCurrency} · ${ccys.where((c) => c.code == user.baseCurrency).firstOrNull?.name(l.ar) ?? ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(l.tr('base_currency_help')),
            trailing: TextButton(onPressed: () => _changeBase(context, ref, ccys), child: Text(l.tr('change'))),
          ),
        ),
        SectionTitle(l.tr('currencies'), trailing: TextButton.icon(icon: const Icon(Icons.add), label: Text(l.tr('add_currency')), onPressed: () => _addCurrency(context, ref))),
        Card(
          child: Column(children: [
            for (final c in ccys)
              ListTile(dense: true, leading: CircleAvatar(radius: 16, child: Text(c.symbol, style: const TextStyle(fontSize: 12))), title: Text('${c.code} · ${c.name(l.ar)}'),
                  subtitle: Text('${l.tr('decimals')}: ${c.decimals}${c.builtin ? '' : ' · ${l.tr('custom')}'}')),
          ]),
        ),
        SectionTitle(l.tr('rate_history')),
        AsyncBody(ref.watch(ratesProvider), (rates) => Card(
              child: rates.isEmpty
                  ? Padding(padding: const EdgeInsets.all(20), child: Text(l.tr('no_rates'), textAlign: TextAlign.center))
                  : Column(children: [
                      for (final r in rates)
                        ListTile(
                          leading: const Icon(Icons.currency_exchange_rounded),
                          title: Text('1 ${r.from} = ${r.rate} ${r.to}', textDirection: TextDirection.ltr, style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text('${isoDay(r.rateDate)} · ${r.source}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              if (!await confirm(context, l.tr('delete'), l.tr('delete_rate_note'), danger: true) || !context.mounted) return;
                              await guard(context, () => ref.read(actionsProvider).run((u) => ref.read(currencyRepositoryProvider).deleteRate(u, r.id)));
                            },
                          ),
                        ),
                    ]),
            )),
      ]),
    );
  }

  Future<void> _changeBase(BuildContext context, WidgetRef ref, List<Currency> ccys) async {
    final l = context.l;
    final code = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(title: Text(l.tr('base_currency')), children: [
        for (final x in ccys) SimpleDialogOption(onPressed: () => Navigator.pop(c, x.code), child: Text('${x.code} · ${x.name(l.ar)}')),
      ]),
    );
    if (code == null || !context.mounted) return;
    if (!await confirm(context, l.tr('change_base'), l.tr('change_base_note', {'ccy': code}))) return;
    if (!context.mounted) return;
    final ok = await guard(context, () async {
      await ref.read(currencyRepositoryProvider).changeBaseCurrency(ref.read(sessionProvider)!.id, code);
      final u = await ref.read(authRepositoryProvider).getUser(ref.read(sessionProvider)!.id);
      ref.read(sessionProvider.notifier).refresh(u!);
      ref.read(revisionProvider.notifier).bump();
      return true;
    }, success: l.tr('saved'));
    if (ok == null) return;
  }

  void _addCurrency(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final code = TextEditingController(), ar = TextEditingController(), en = TextEditingController(), sym = TextEditingController(), dec = TextEditingController(text: '2');
    final form = GlobalKey<FormState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SheetFrame(
        title: l.tr('add_currency'),
        child: Form(
          key: form,
          child: Column(children: [
            TextFormField(controller: code, textCapitalization: TextCapitalization.characters, maxLength: 3, decoration: InputDecoration(labelText: l.tr('iso_code'), hintText: 'AED'),
                validator: (v) => RegExp(r'^[A-Za-z]{3}$').hasMatch(v ?? '') ? null : l.tr('err_currency_code')),
            TextFormField(controller: ar, decoration: InputDecoration(labelText: l.tr('name_ar')), validator: (v) => (v ?? '').isEmpty ? l.tr('required') : null),
            const SizedBox(height: 10),
            TextFormField(controller: en, decoration: InputDecoration(labelText: l.tr('name_en')), validator: (v) => (v ?? '').isEmpty ? l.tr('required') : null),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextFormField(controller: sym, decoration: InputDecoration(labelText: l.tr('symbol')))),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(controller: dec, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l.tr('decimals')))),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                final ok = await guard(c, () => ref.read(actionsProvider).run((u) => ref.read(currencyRepositoryProvider).addCurrency(Currency(code: code.text.toUpperCase(),
                    nameAr: ar.text, nameEn: en.text, symbol: sym.text.isEmpty ? code.text.toUpperCase() : sym.text, decimals: int.tryParse(dec.text) ?? 2))).then((_) => true));
                if (ok == true && c.mounted) Navigator.pop(c);
              },
              child: Text(l.tr('save')),
            ),
          ]),
        ),
      ),
    );
  }
}
