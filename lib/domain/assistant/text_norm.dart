import '../../core/money/money.dart';

class TextNorm {
  /// Lower-case, Arabic letter normalisation (أ/إ/آ→ا, ة→ه, ى→ي), no tashkeel,
  /// Arabic-Indic digits → ASCII, punctuation → space.
  static String normalize(String s) {
    var t = Money.normalizeDigits(s.toLowerCase());
    t = t.replaceAll(RegExp('[\u064B-\u0652\u0640]'), '');
    t = t.replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ة', 'ه').replaceAll('ى', 'ي').replaceAll('؟', ' ').replaceAll('٫', '.');
    t = t.replaceAll(RegExp(r'(?<=\d),(?=\d)'), '');
    t = t.replaceAll(RegExp(r'[^\w\u0600-\u06FF\.\$€ ]'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
