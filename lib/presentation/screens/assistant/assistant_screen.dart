import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/assistant/assistant_engine.dart';
import '../../../domain/entities/account.dart';
import '../../../domain/entities/transaction.dart';
import '../../../core/utils/ids.dart';
import '../../providers/providers.dart';
import '../../widgets/common.dart';
import '../transactions/transaction_form_screen.dart';

class _Msg {
  final bool me;
  final String text;
  final QuickAddDraft? draft;
  final List<String> suggestions;
  const _Msg(this.me, this.text, {this.draft, this.suggestions = const []});
}

/// Financial assistant (rule-based v1, on your real data, no internet/keys).
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});
  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final input = TextEditingController();
  final msgs = <_Msg>[];
  bool busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _send(context.l.ar ? 'مساعدة' : 'help', echo: false));
  }

  Future<void> _send(String text, {bool echo = true}) async {
    if (text.trim().isEmpty) return;
    final l = context.l;
    setState(() {
      if (echo) msgs.add(_Msg(true, text));
      busy = true;
    });
    input.clear();
    try {
      final snap = await ref.read(snapshotProvider.future);
      final r = await ref.read(assistantEngineProvider).respond(text, AssistantContext(snapshot: snap, ar: l.ar, categoryName: l.category));
      setState(() => msgs.add(_Msg(false, r.text, draft: r.draft, suggestions: r.suggestions)));
    } catch (e) {
      if (mounted) setState(() => msgs.add(_Msg(false, errorText(context, e))));
    }
    if (mounted) setState(() => busy = false);
  }

  Future<void> _confirmDraft(QuickAddDraft d) async {
    final cats = await ref.read(categoriesProvider.future);
    final accs = (await ref.read(accountsProvider.future)).where((a) => a.isActive).toList();
    final cat = cats.where((c) => c.key == d.categoryKey).firstOrNull;
    final acc = accs.where((a) => a.currency == d.currency).firstOrNull ?? accs.firstOrNull;
    if (!mounted) return;
    final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => TransactionFormScreen(
                type: d.type,
                prefill: TxnDraft(type: d.type, accountId: acc?.id, amount: d.amount, currency: d.currency ?? acc?.currency ?? ref.read(sessionProvider)!.baseCurrency,
                    categoryId: cat?.kind == (d.type == TxnType.income ? CategoryKind.income : CategoryKind.expense) ? cat?.id : null,
                    title: d.title, txnDate: d.date, idempotencyKey: newIdempotencyKey()))));
    if (saved == true && mounted) setState(() => msgs.add(_Msg(false, context.tr('assistant_saved'))));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    return Scaffold(
      appBar: AppBar(title: Row(children: [const Icon(Icons.auto_awesome_rounded, color: AppColors.gold), const SizedBox(width: 8), Text(l.tr('menu_assistant'))])),
      body: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 4), child: InfoBanner(Icons.lock_outline_rounded, l.tr('assistant_privacy'), color: AppColors.transfer)),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: msgs.length,
            itemBuilder: (c, i) {
              final m = msgs[i];
              return Align(
                alignment: m.me ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(12),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.84),
                  decoration: BoxDecoration(
                    color: m.me ? AppColors.primary : Theme.of(context).colorScheme.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(16),
                    border: m.me ? null : Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.text, style: TextStyle(color: m.me ? Colors.white : null, height: 1.5)),
                    if (m.draft != null) ...[
                      const SizedBox(height: 8),
                      FilledButton.icon(onPressed: () => _confirmDraft(m.draft!), icon: const Icon(Icons.check_rounded), label: Text(l.tr('review_confirm'))),
                    ],
                    if (m.suggestions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(spacing: 6, runSpacing: 6, children: [for (final s in m.suggestions) ActionChip(label: Text(s, style: const TextStyle(fontSize: 12)), onPressed: () => _send(s))]),
                    ],
                  ]),
                ),
              );
            },
          ),
        ),
        if (busy) const LinearProgressIndicator(minHeight: 2),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: input,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.send,
                  onSubmitted: _send,
                  decoration: InputDecoration(hintText: l.tr('assistant_hint')),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(icon: const Icon(Icons.send_rounded), onPressed: () => _send(input.text)),
            ]),
          ),
        ),
      ]),
    );
  }
}
