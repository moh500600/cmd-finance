import 'package:flutter/widgets.dart';

import '../../domain/entities/account.dart';
import 'strings.dart';

/// Arabic / English strings. Keys live in strings.dart ([ar, en] pairs).
class L10n {
  final String lang;
  const L10n(this.lang);
  bool get ar => lang == 'ar';

  static L10n of(BuildContext context) => L10n(Localizations.localeOf(context).languageCode);

  String tr(String key, [Map<String, String> args = const {}]) {
    final pair = kStrings[key];
    var s = pair == null ? key : (ar ? pair[0] : pair[1]);
    args.forEach((k, v) => s = s.replaceAll('{$k}', v));
    return s;
  }

  String category(Category? c) {
    if (c == null) return tr('uncategorized');
    if (c.key != null) return tr('cat_${c.key}');
    return c.name;
  }
}

extension L10nX on BuildContext {
  L10n get l => L10n.of(this);
  String tr(String key, [Map<String, String> args = const {}]) => L10n.of(this).tr(key, args);
}
