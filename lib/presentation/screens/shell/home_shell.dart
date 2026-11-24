import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/entities/transaction.dart';
import '../accounts/accounts_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../more/more_screen.dart';
import '../reports/reports_screen.dart';
import '../transactions/transaction_form_screen.dart';
import '../transactions/transactions_screen.dart';
import '../transactions/transfer_form_screen.dart';
import '../assistant/assistant_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    const pages = [DashboardScreen(), TransactionsScreen(), AccountsScreen(), ReportsScreen(), MoreScreen()];
    return Scaffold(
      body: IndexedStack(index: index, children: pages),
      floatingActionButton: index <= 2
          ? FloatingActionButton(
              heroTag: 'add',
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              onPressed: () => showAddMenu(context),
              child: const Icon(Icons.add_rounded, size: 30),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.dashboard_outlined), selectedIcon: const Icon(Icons.dashboard_rounded), label: l.tr('nav_dashboard')),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), selectedIcon: const Icon(Icons.receipt_long_rounded), label: l.tr('nav_transactions')),
          NavigationDestination(icon: const Icon(Icons.account_balance_wallet_outlined), selectedIcon: const Icon(Icons.account_balance_wallet_rounded), label: l.tr('nav_accounts')),
          NavigationDestination(icon: const Icon(Icons.insert_chart_outlined_rounded), selectedIcon: const Icon(Icons.insert_chart_rounded), label: l.tr('nav_reports')),
          NavigationDestination(icon: const Icon(Icons.grid_view_outlined), selectedIcon: const Icon(Icons.grid_view_rounded), label: l.tr('nav_more')),
        ],
      ),
    );
  }
}

void showAddMenu(BuildContext context) => showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (c) {
        Widget tile(IconData i, Color col, String t, String sub, Widget page) => ListTile(
              leading: CircleAvatar(backgroundColor: col.withValues(alpha: 0.14), child: Icon(i, color: col)),
              title: Text(t, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(sub),
              onTap: () {
                Navigator.pop(c);
                Navigator.push(context, MaterialPageRoute(builder: (_) => page));
              },
            );
        return SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            tile(Icons.north_east_rounded, AppColors.expense, c.tr('add_expense'), c.tr('add_expense_sub'), const TransactionFormScreen(type: TxnType.expense)),
            tile(Icons.south_west_rounded, AppColors.income, c.tr('add_income'), c.tr('add_income_sub'), const TransactionFormScreen(type: TxnType.income)),
            tile(Icons.swap_horiz_rounded, AppColors.transfer, c.tr('add_transfer'), c.tr('add_transfer_sub'), const TransferFormScreen()),
            tile(Icons.auto_awesome_rounded, AppColors.gold, c.tr('quick_add'), c.tr('quick_add_sub'), const AssistantScreen()),
            const SizedBox(height: 8),
          ]),
        );
      },
    );
