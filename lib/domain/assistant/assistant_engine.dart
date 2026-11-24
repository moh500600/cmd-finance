import 'package:decimal/decimal.dart';

import '../entities/account.dart';
import '../entities/transaction.dart';
import '../services/snapshot.dart';

/// Proposed transaction parsed from free text; the UI asks the user to confirm.
class QuickAddDraft {
  final TxnType type;
  final Decimal amount;
  final String? currency; // null -> UI asks / uses account currency
  final String? categoryKey;
  final String title;
  final DateTime date;
  const QuickAddDraft({required this.type, required this.amount, this.currency, this.categoryKey, required this.title, required this.date});
}

class AssistantReply {
  final String text;
  final QuickAddDraft? draft;
  final List<String> suggestions;
  const AssistantReply(this.text, {this.draft, this.suggestions = const []});
}

class AssistantContext {
  final FinanceSnapshot snapshot;
  final bool ar;
  final String Function(Category? c) categoryName;
  const AssistantContext({required this.snapshot, required this.ar, required this.categoryName});
}

/// Swap point for an LLM later: implement this interface (e.g. call an API with
/// the user's consent) and override assistantEngineProvider. No keys are shipped.
abstract class AssistantEngine {
  Future<AssistantReply> respond(String message, AssistantContext ctx);
}
