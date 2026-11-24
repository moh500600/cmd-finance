import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../../../core/l10n/l10n.dart';
import '../../../core/money/money.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/dates.dart';
import '../../../domain/entities/currency.dart';
import '../../../domain/entities/holdings.dart';
import '../../providers/providers.dart';
import '../../widgets/charts.dart';
import '../../widgets/common.dart';
import '../../widgets/visuals.dart';

class AssetsScreen extends ConsumerWidget {
  const AssetsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('menu_assets'))),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => showAssetForm(context, ref), icon: const Icon(Icons.add), label: Text(l.tr('add_asset'))),
      body: AsyncBody(ref.watch(snapshotProvider), (s) {
        if (s.assets.isEmpty) return EmptyState(Icons.apartment_rounded, l.tr('no_assets'));
        final total = s.assetsTotal;
        return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
          Card(
            color: const Color(0xFF7C3AED),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l.tr('total_assets_value'), style: const TextStyle(color: Colors.white70)),
                MoneyText(total.total, currency: s.base, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                if (!total.complete) Text(l.tr('excludes_no_rate', {'ccy': total.missing.join(', ')}), style: const TextStyle(color: Colors.amberAccent, fontSize: 12)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          Card(
            child: Column(children: [
              for (final a in s.assets)
                ListTile(
                  leading: IconBadge(assetIcon(a.item.type), const Color(0xFF7C3AED)),
                  title: Text(a.item.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${l.tr('asset_${a.item.type.name}')} · ${a.item.changePercent.sign >= 0 ? '+' : ''}${a.item.changePercent}%'),
                  trailing: MoneyText(a.item.currentValue, currency: a.currency, style: const TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AssetDetailScreen(id: a.item.id))),
                ),
            ]),
          ),
        ]);
      }),
    );
  }
}

void showAssetForm(BuildContext context, WidgetRef ref, {Asset? existing}) {
  final l = context.l;
  final name = TextEditingController(text: existing?.name ?? '');
  final purchase = TextEditingController(text: existing?.purchaseValue.toString() ?? '');
  final current = TextEditingController(text: existing?.currentValue.toString() ?? '');
  final notes = TextEditingController(text: existing?.notes ?? '');
  var type = existing?.type ?? AssetType.realEstate;
  String? currency = existing?.currency ?? ref.read(sessionProvider)!.baseCurrency;
  DateTime? date = existing?.purchaseDate;
  final docs = [...?existing?.documents];
  final form = GlobalKey<FormState>();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SheetFrame(
        title: l.tr(existing == null ? 'add_asset' : 'edit_asset'),
        child: Form(
          key: form,
          child: Column(children: [
            TextFormField(controller: name, decoration: InputDecoration(labelText: l.tr('name')), validator: (v) => (v ?? '').trim().isEmpty ? l.tr('required') : null),
            const SizedBox(height: 10),
            DropdownButtonFormField<AssetType>(
              initialValue: type,
              decoration: InputDecoration(labelText: l.tr('type')),
              items: [for (final t in AssetType.values) DropdownMenuItem(value: t, child: Row(children: [Icon(assetIcon(t), size: 18), const SizedBox(width: 8), Text(l.tr('asset_${t.name}'))]))],
              onChanged: (v) => set(() => type = v!),
            ),
            const SizedBox(height: 10),
            CurrencyField(value: currency, currencies: ref.read(currenciesProvider).value ?? const <Currency>[], label: l.tr('currency'), onChanged: (v) => set(() => currency = v)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: AmountField(controller: purchase, label: l.tr('purchase_value'), allowZero: true)),
              const SizedBox(width: 8),
              Expanded(child: AmountField(controller: current, label: l.tr('current_value'), allowZero: true)),
            ]),
            const SizedBox(height: 10),
            DateField(label: l.tr('purchase_date'), value: date, onChanged: (d) => set(() => date = d), onClear: () => set(() => date = null)),
            const SizedBox(height: 10),
            TextFormField(controller: notes, decoration: InputDecoration(labelText: l.tr('notes')), maxLines: 2),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in docs) InputChip(label: Text(p.basename(d)), onDeleted: () => set(() => docs.remove(d))),
              ActionChip(
                avatar: const Icon(Icons.upload_file_rounded, size: 18),
                label: Text(l.tr('ownership_docs')),
                onPressed: () async {
                  final f = await FilePicker.pickFile();
                  if (f == null) return;
                  final path = await ref.read(fileStorageProvider).saveBytes(await f.xFile.readAsBytes(), f.name, folder: 'documents');
                  set(() => docs.add(path));
                },
              ),
            ]),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (!form.currentState!.validate() || currency == null) return;
                final ok = await guard(c, () => ref.read(actionsProvider).run((u) => ref.read(assetRepositoryProvider).saveAsset(u, id: existing?.id, name: name.text, type: type,
                    purchaseValue: Money.parse(purchase.text), currentValue: Money.parse(current.text), currency: currency!, purchaseDate: date, documents: docs, notes: notes.text)));
                if (ok != null && c.mounted) Navigator.pop(c);
              },
              child: Text(l.tr('save')),
            ),
          ]),
        ),
      ),
    ),
  );
}

class AssetDetailScreen extends ConsumerWidget {
  final String id;
  const AssetDetailScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final a = (ref.watch(assetsProvider).value ?? const <Asset>[]).where((x) => x.id == id).firstOrNull;
    if (a == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    ref.watch(revisionProvider);
    return Scaffold(
      appBar: AppBar(title: Text(a.name), actions: [
        IconButton(icon: const Icon(Icons.edit_rounded), onPressed: () => showAssetForm(context, ref, existing: a)),
        IconButton(
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () async {
            if (!await confirm(context, l.tr('delete'), l.tr('delete_asset_note'), danger: true) || !context.mounted) return;
            final ok = await guard(context, () => ref.read(actionsProvider).run((u) => ref.read(assetRepositoryProvider).deleteAsset(u, id)).then((_) => true));
            if (ok == true && context.mounted) Navigator.pop(context);
          },
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(icon: const Icon(Icons.trending_up_rounded), label: Text(l.tr('update_value')), onPressed: () => _revalue(context, ref, a)),
      body: FutureBuilder(
        future: ref.read(assetRepositoryProvider).history(ref.read(sessionProvider)!.id, id),
        builder: (context, s) {
          final h = s.data ?? const <ValuePoint>[];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  _kv(context, l.tr('type'), l.tr('asset_${a.type.name}')),
                  _kv(context, l.tr('purchase_value'), Money.format(a.purchaseValue, currency: a.currency)),
                  _kv(context, l.tr('current_value'), Money.format(a.currentValue, currency: a.currency)),
                  _kv(context, l.tr('change'), '${Money.format(a.change, currency: a.currency, showSign: true)} (${a.changePercent}%)'),
                  if (a.purchaseDate != null) _kv(context, l.tr('purchase_date'), isoDay(a.purchaseDate!)),
                  if (a.notes.isNotEmpty) _kv(context, l.tr('notes'), a.notes),
                ]),
              ),
            ),
            if (a.documents.isNotEmpty) ...[
              SectionTitle(l.tr('ownership_docs')),
              Card(child: Column(children: [for (final d in a.documents) ListTile(leading: const Icon(Icons.description_rounded), title: Text(p.basename(d)), onTap: () => OpenFilex.open(d))])),
            ],
            if (h.length > 1) ...[
              const SizedBox(height: 12),
              ChartCard(title: l.tr('value_history'), child: TrendLine(labels: [for (final x in h) '${x.date.day}/${x.date.month}'], values: [for (final x in h) x.value], color: const Color(0xFF7C3AED))),
            ],
            SectionTitle(l.tr('value_history')),
            Card(
              child: Column(children: [
                for (final x in h.reversed)
                  ListTile(dense: true, leading: const Icon(Icons.timeline_rounded), title: MoneyText(x.value, currency: a.currency), subtitle: Text('${isoDay(x.date)} ${x.note}')),
              ]),
            ),
          ]);
        },
      ),
    );
  }

  Widget _kv(BuildContext c, String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [Expanded(child: Text(k, style: TextStyle(color: Theme.of(c).colorScheme.onSurfaceVariant))), Flexible(child: Text(v, style: const TextStyle(fontWeight: FontWeight.w600)))]));

  void _revalue(BuildContext context, WidgetRef ref, Asset a) {
    final l = context.l;
    final value = TextEditingController(text: a.currentValue.toString());
    final note = TextEditingController();
    final form = GlobalKey<FormState>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => SheetFrame(
        title: l.tr('update_value'),
        child: Form(
          key: form,
          child: Column(children: [
            AmountField(controller: value, label: l.tr('current_value'), suffix: a.currency, allowZero: true),
            const SizedBox(height: 10),
            TextFormField(controller: note, decoration: InputDecoration(labelText: l.tr('notes'))),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () async {
                if (!form.currentState!.validate()) return;
                final ok = await guard(c, () => ref.read(actionsProvider).run((u) => ref.read(assetRepositoryProvider).addValue(u, a.id, Money.parse(value.text), DateTime.now(), note: note.text)).then((_) => true));
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
