import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/entities/account.dart';
import '../../domain/entities/holdings.dart';
import '../../domain/entities/planning.dart';
import '../../domain/entities/transaction.dart';

const categoryIcons = <String, IconData>{
  'salary': Icons.work_rounded, 'business': Icons.storefront_rounded, 'sales': Icons.point_of_sale_rounded, 'freelance': Icons.laptop_mac_rounded,
  'rent_income': Icons.apartment_rounded, 'investments': Icons.trending_up_rounded, 'gifts': Icons.card_giftcard_rounded, 'other_income': Icons.add_card_rounded,
  'food': Icons.restaurant_rounded, 'transport': Icons.directions_car_rounded, 'housing': Icons.home_rounded, 'utilities': Icons.bolt_rounded,
  'internet': Icons.wifi_rounded, 'health': Icons.local_hospital_rounded, 'education': Icons.school_rounded, 'shopping': Icons.shopping_bag_rounded,
  'entertainment': Icons.movie_rounded, 'travel': Icons.flight_rounded, 'bills': Icons.receipt_long_rounded, 'fees': Icons.percent_rounded,
  'other_expense': Icons.more_horiz_rounded,
};

/// Icons a user can pick for custom categories (stored by index).
const customCategoryIcons = <IconData>[
  Icons.label_rounded, Icons.pets_rounded, Icons.child_care_rounded, Icons.sports_soccer_rounded, Icons.local_cafe_rounded, Icons.build_rounded,
  Icons.mosque_rounded, Icons.volunteer_activism_rounded, Icons.phone_iphone_rounded, Icons.checkroom_rounded, Icons.local_gas_station_rounded, Icons.savings_rounded,
];

IconData categoryIcon(Category? c) {
  if (c == null) return Icons.help_outline_rounded;
  if (c.key != null) return categoryIcons[c.key] ?? Icons.label_rounded;
  return customCategoryIcons[c.icon.clamp(0, customCategoryIcons.length - 1)];
}

IconData accountIcon(AccountType t) => switch (t) {
      AccountType.cash => Icons.payments_rounded,
      AccountType.bank => Icons.account_balance_rounded,
      AccountType.ewallet => Icons.account_balance_wallet_rounded,
      AccountType.digitalWallet => Icons.qr_code_2_rounded,
      AccountType.savings => Icons.savings_rounded,
      AccountType.investment => Icons.show_chart_rounded,
    };

IconData txnIcon(TxnType t) => switch (t) {
      TxnType.income => Icons.south_west_rounded,
      TxnType.expense => Icons.north_east_rounded,
      TxnType.transfer => Icons.swap_horiz_rounded,
      TxnType.debtPayment || TxnType.debtCollection || TxnType.loanGiven || TxnType.loanReceived => Icons.handshake_rounded,
      TxnType.savingsDeposit || TxnType.savingsWithdraw => Icons.savings_rounded,
    };

Color txnColor(TxnType t) => switch (t.sign) { 1 => AppColors.income, -1 => AppColors.expense, _ => AppColors.transfer };

IconData billIcon(BillKind k) => switch (k) {
      BillKind.electricity => Icons.bolt_rounded,
      BillKind.water => Icons.water_drop_rounded,
      BillKind.internet => Icons.wifi_rounded,
      BillKind.rent => Icons.home_rounded,
      BillKind.subscription => Icons.subscriptions_rounded,
      BillKind.installment => Icons.credit_score_rounded,
      BillKind.other => Icons.receipt_rounded,
    };

IconData assetIcon(AssetType t) => switch (t) {
      AssetType.realEstate => Icons.apartment_rounded,
      AssetType.vehicle => Icons.directions_car_rounded,
      AssetType.device => Icons.devices_rounded,
      AssetType.gold => Icons.diamond_rounded,
      AssetType.business => Icons.store_rounded,
      AssetType.investment => Icons.trending_up_rounded,
      AssetType.other => Icons.category_rounded,
    };
