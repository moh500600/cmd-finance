import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/account.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/visuals.dart';

/// Built-in + custom categories. Custom ones can be renamed/archived (never
/// hard-deleted, so old transactions keep their category).
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: Text(l.tr('menu_categories')), bottom: TabBar(tabs: [Tab(text: l.tr('expenses')), Tab(text: l.tr('income'))])),
        body: AsyncBody(ref.watch(categoriesProvider), (cats) => TabBarView(children: [
              for (final kind in [CategoryKind.expense, CategoryKind.income])
                ListView(padding: const EdgeInsets.only(bottom: 90), children: [
                  for (final c in cats.where((c) => c.kind == kind))
                    ListTile(
                      leading: IconBadge(categoryIcon(c), Color(c.color)),
                      title: Text(l.category(c)),
                      subtitle: Text(c.builtin ? l.tr('builtin') : l.tr('custom')),
                      trailing: c.builtin
                          ? null
                          : Row(mainAxisSize: MainAxisSize.min, children: [
                              IconButton(icon: const Icon(Icons.edit_outlined), onPressed: () => showCategoryEditor(context, ref, kind, existing: c)),
                              IconButton(
                                icon: const Icon(Icons.archive_outlined),
                                onPressed: () async {
                                  if (await confirm(context, l.tr('archive'), l.tr('archive_category_note'))) {
                                    if (context.mounted) await guard(context, () => ref.read(actionsProvider).run((u) => ref.read(accountRepositoryProvider).archiveCategory(u, c.id)));
                                  }
                                },
                              ),
                            ]),
                    ),
                ]),
            ])),
        floatingActionButton: Builder(
          builder: (ctx) => FloatingActionButton.extended(
            icon: const Icon(Icons.add),
            label: Text(l.tr('add_category')),
            onPressed: () => showCategoryEditor(ctx, ref, DefaultTabController.of(ctx).index == 0 ? CategoryKind.expense : CategoryKind.income),
          ),
        ),
      ),
    );
  }
}

/// Returns the saved category id.
Future<String?> showCategoryEditor(BuildContext context, WidgetRef ref, CategoryKind kind, {Category? existing}) async {
  final name = TextEditingController(text: existing?.name ?? '');
  var icon = existing?.icon ?? 0;
  var color = existing?.color ?? AppColors.chart[3].toARGB32();
  final l = context.l;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (c) => StatefulBuilder(
      builder: (c, set) => SheetFrame(
        title: l.tr(existing == null ? 'add_category' : 'edit_category'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: name, decoration: InputDecoration(labelText: l.tr('name'))),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < customCategoryIcons.length; i++)
              ChoiceChip(label: Icon(customCategoryIcons[i], size: 20), selected: icon == i, onSelected: (_) => set(() => icon = i)),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            for (final col in AppColors.chart.take(10))
              GestureDetector(
                onTap: () => set(() => color = col.toARGB32()),
                child: CircleAvatar(radius: 14, backgroundColor: col, child: color == col.toARGB32() ? const Icon(Icons.check, size: 14, color: Colors.white) : null),
              ),
          ]),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => Navigator.pop(c, name.text.trim().isNotEmpty), child: Text(l.tr('save'))),
        ]),
      ),
    ),
  );
  if (ok != true || !context.mounted) return null;
  final cat = await guard(context, () => ref.read(actionsProvider).run((u) => ref.read(accountRepositoryProvider).saveCategory(u, id: existing?.id, kind: kind, name: name.text, icon: icon, color: color)));
  return cat?.id;
}
