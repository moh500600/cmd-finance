import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/l10n/l10n.dart';
import '../../../core/platform/platform_support.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/providers.dart';

/// App lock: PIN (hashed) with optional fingerprint/face unlock.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});
  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String pin = '';
  bool wrong = false;

  @override
  void initState() {
    super.initState();
    if (ref.read(settingsProvider).biometric && PlatformSupport.biometrics) WidgetsBinding.instance.addPostFrameCallback((_) => _bio());
  }

  Future<void> _bio() async {
    if (!PlatformSupport.biometrics) return;
    try {
      final ok = await LocalAuthentication().authenticate(localizedReason: context.tr('unlock_reason'));
      if (ok) ref.read(lockProvider.notifier).unlock();
    } catch (_) {}
  }

  void _tap(String d) {
    if (pin.length >= 6) return;
    setState(() {
      pin += d;
      wrong = false;
    });
    if (pin.length >= 4 && ref.read(settingsRepositoryProvider).verifyPin(pin)) {
      ref.read(lockProvider.notifier).unlock();
    } else if (pin.length == 6) {
      setState(() {
        pin = '';
        wrong = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l;
    // Biometrics (fingerprint/face, Windows Hello) where the OS has them; the PIN always works.
    final bio = ref.watch(settingsProvider).biometric && PlatformSupport.biometrics;
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          const Spacer(),
          const Icon(Icons.lock_rounded, size: 54, color: AppColors.primary),
          const SizedBox(height: 12),
          Text(l.tr('enter_pin'), style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 0; i < 6; i++)
              Container(margin: const EdgeInsets.all(6), width: 14, height: 14,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: i < pin.length ? AppColors.primary : Colors.grey.withValues(alpha: 0.3))),
          ]),
          if (wrong) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l.tr('wrong_pin'), style: const TextStyle(color: AppColors.expense))),
          const Spacer(),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Wrap(alignment: WrapAlignment.center, children: [
              for (final d in ['1', '2', '3', '4', '5', '6', '7', '8', '9'])
                _key(d, () => _tap(d)),
              _keyIcon(bio ? Icons.fingerprint_rounded : null, bio ? _bio : null),
              _key('0', () => _tap('0')),
              _keyIcon(Icons.backspace_outlined, () => setState(() => pin = pin.isEmpty ? '' : pin.substring(0, pin.length - 1))),
            ]),
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: () => ref.read(sessionProvider.notifier).signOut().then((_) => ref.read(lockProvider.notifier).unlock()), child: Text(l.tr('logout'))),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  Widget _key(String d, VoidCallback onTap) => SizedBox(
      width: 110, height: 72, child: TextButton(onPressed: onTap, child: Text(d, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600))));
  Widget _keyIcon(IconData? i, VoidCallback? onTap) => SizedBox(width: 110, height: 72, child: i == null ? null : IconButton(onPressed: onTap, icon: Icon(i, size: 28)));
}
