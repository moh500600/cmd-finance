import 'package:decimal/decimal.dart';

import '../../core/money/money.dart';
import '../entities/transaction.dart';
import 'assistant_engine.dart';
import 'text_norm.dart';

/// Parses «صرفت 5000 ريال يمني غداء» / "spent 20 usd taxi yesterday" into a draft.
class QuickAddParser {
  static const _expenseVerbs = ['صرفت', 'دفعت', 'اشتريت', 'سددت', 'شريت', 'spent', 'paid', 'bought', 'spend', 'pay'];
  static const _incomeVerbs = ['استلمت', 'قبضت', 'وصلني', 'جاني', 'كسبت', 'ربحت', 'دخلي', 'received', 'earned', 'got', 'income'];

  static const categoryWords = <String, List<String>>{
    'food': ['غداء', 'غدا', 'عشاء', 'عشا', 'فطور', 'مطعم', 'اكل', 'قهوه', 'بقاله', 'خبز', 'lunch', 'dinner', 'breakfast', 'food', 'restaurant', 'coffee', 'grocer'],
    'transport': ['بنزين', 'تاكسي', 'مواصلات', 'باص', 'اجره', 'وقود', 'taxi', 'fuel', 'gas', 'bus', 'uber', 'transport'],
    'housing': ['ايجار البيت', 'سكن', 'شقه', 'rent', 'housing', 'apartment'],
    'utilities': ['كهرباء', 'ماء', 'مياه', 'electric', 'water'],
    'internet': ['انترنت', 'نت', 'رصيد', 'اتصالات', 'جوال', 'internet', 'phone', 'mobile'],
    'health': ['دواء', 'صيدليه', 'دكتور', 'مستشفى', 'علاج', 'medicine', 'pharmacy', 'doctor', 'hospital'],
    'education': ['مدرسه', 'جامعه', 'كتب', 'دوره', 'رسوم دراسيه', 'school', 'course', 'books', 'tuition'],
    'shopping': ['ملابس', 'تسوق', 'سوق', 'جزمه', 'clothes', 'shopping', 'shoes'],
    'entertainment': ['سينما', 'العاب', 'نزهه', 'ترفيه', 'cinema', 'games', 'fun', 'movie'],
    'travel': ['سفر', 'تذكره', 'فندق', 'طيران', 'travel', 'flight', 'hotel', 'ticket'],
    'bills': ['فاتوره', 'اشتراك', 'bill', 'subscription'],
    'salary': ['راتب', 'معاش', 'salary', 'payroll'],
    'freelance': ['مشروع', 'عميل', 'فريلانس', 'freelance', 'client', 'project'],
    'sales': ['مبيعات', 'بيع', 'sales', 'sold'],
    'gifts': ['هديه', 'عيديه', 'gift'],
  };

  static String? currencyOf(String n) {
    if (RegExp(r'(ريال يمني|ر ي|يمني|\byer\b)').hasMatch(n)) return 'YER';
    if (RegExp(r'(ريال سعودي|سعودي|\bsar\b|ر س)').hasMatch(n)) return 'SAR';
    if (RegExp(r'(دولار|\busd\b|\$|dollar)').hasMatch(n)) return 'USD';
    if (RegExp(r'(يورو|\beur\b|€|euro)').hasMatch(n)) return 'EUR';
    final m = RegExp(r'\b([a-z]{3})\b').allMatches(n).map((e) => e.group(1)!.toUpperCase());
    for (final c in m) {
      if (!const {'THE', 'AND', 'FOR', 'GOT', 'PAY', 'BUS', 'GAS', 'FUN'}.contains(c)) return c;
    }
    return null;
  }

  static QuickAddDraft? parse(String input, {required DateTime now}) {
    final n = TextNorm.normalize(input);
    final words = n.split(' ');
    TxnType? type;
    if (words.any((w) => _expenseVerbs.contains(w))) type = TxnType.expense;
    if (type == null && words.any((w) => _incomeVerbs.contains(w))) type = TxnType.income;
    if (type == null) return null;
    final m = RegExp(r'(\d+(?:\.\d+)?)\s*(الف|الاف|k|الفين)?').firstMatch(n);
    if (m == null) return null;
    var amount = Money.parse(m.group(1)!);
    if (m.group(2) != null) amount = amount * Decimal.fromInt(1000);
    if (amount.sign <= 0) return null;
    String? cat;
    for (final e in categoryWords.entries) {
      if (e.value.any((w) => n.contains(w))) {
        final isIncomeCat = const {'salary', 'freelance', 'sales', 'gifts'}.contains(e.key);
        if (isIncomeCat == (type == TxnType.income)) {
          cat = e.key;
          break;
        }
      }
    }
    var date = now;
    if (n.contains('امس') || n.contains('yesterday')) date = now.subtract(const Duration(days: 1));
    if (n.contains('اول امس')) date = now.subtract(const Duration(days: 2));
    // title: original text minus verb/amount/currency words
    final drop = {..._expenseVerbs, ..._incomeVerbs, 'ريال', 'يمني', 'سعودي', 'دولار', 'يورو', 'yer', 'sar', 'usd', 'eur', 'امس', 'اليوم', 'yesterday', 'today', 'على', 'في', 'on', 'for', 'الف', 'k'};
    final title = words.where((w) => !drop.contains(w) && !RegExp(r'^\d').hasMatch(w)).join(' ').trim();
    return QuickAddDraft(type: type, amount: amount, currency: currencyOf(n), categoryKey: cat ?? (type == TxnType.income ? 'other_income' : 'other_expense'),
        title: title, date: date);
  }
}
