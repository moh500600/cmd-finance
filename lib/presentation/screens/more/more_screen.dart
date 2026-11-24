import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../accounts/accounts_screen.dart';
import '../assistant/assistant_screen.dart';
import '../planning/assets_screen.dart';
import '../planning/bills_screen.dart';
import '../planning/budgets_screen.dart';
import '../planning/debts_screen.dart';
import '../planning/investments_screen.dart';
import '../planning/savings_screen.dart';
import '../settings/categories_screen.dart';
import '../settings/currencies_screen.dart';
import '../settings/recurring_screen.dart';
import '../settings/settings_screen.dart';
import '../transactions/transactions_screen.dart';
import '../transactions/transfer_form_screen.dart';

Widget routeTarget(String route) => switch (route) {
      'budgets' => const BudgetsScreen(),
      'debts' => const DebtsScreen(),
      'savings' => const SavingsScreen(),
      'bills' => const BillsScreen(),
      'assets' => const AssetsScreen(),
      'investments' => const InvestmentsScreen(),
      'currencies' => const CurrenciesScreen(),
      'recurring' => const RecurringScreen(),
      'accounts' => const AccountsScreen(),
      'categories' => const CategoriesScreen(),
      'assistant' => const AssistantScreen(),
      'settings' => const SettingsScreen(),
      'transfer' => const TransferFormScreen(),
      _ => const TransactionsScreen(),
    };

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l;
    final items = <(String, IconData, Color)>[
      ('assistant', Icons.auto_awesome_rounded, AppColors.gold),
      ('transfer', Icons.swap_horiz_rounded, AppColors.transfer),
      ('budgets', Icons.pie_chart_rounded, AppColors.primary),
      ('debts', Icons.handshake_rounded, AppColors.expense),
      ('savings', Icons.savings_rounded, AppColors.income),
      ('bills', Icons.receipt_long_rounded, AppColors.warning),
      ('assets', Icons.apartment_rounded, const Color(0xFF7C3AED)),
      ('investments', Icons.trending_up_rounded, const Color(0xFF0891B2)),
      ('currencies', Icons.currency_exchange_rounded, const Color(0xFF65A30D)),
      ('recurring', Icons.event_repeat_rounded, const Color(0xFFDB2777)),
      ('categories', Icons.category_rounded, const Color(0xFF4F46E5)),
      ('settings', Icons.settings_rounded, const Color(0xFF64748B)),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l.tr('nav_more'))),
      body: LayoutBuilder(builder: (context, c) {
        final cols = c.maxWidth > 600 ? 4 : 3;
        return GridView.count(
          padding: const EdgeInsets.all(16),
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.95,
          children: [
            for (final (key, icon, color) in items)
              Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => routeTarget(key))),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(16)),
                      child: Icon(icon, color: color, size: 28),
                    ),
                    const SizedBox(height: 8),
                    Text(l.tr('menu_$key'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ]),
                ),
              ),
          ],
        );
      }),
    );
  }
}
