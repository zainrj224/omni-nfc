import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth_service.dart';
import 'core/models.dart';
import 'core/nfc_service.dart';
import 'core/signer.dart';
import 'core/storage.dart';

const _devAuth = bool.fromEnvironment('DEV_AUTH', defaultValue: true);
const _apiBase = String.fromEnvironment('API_BASE', defaultValue: 'https://api.example.com');

final apiProvider = Provider<AuthApi>((ref) => _devAuth ? DevAuthApi() : HttpAuthApi(_apiBase));
final authServiceProvider = Provider<AuthService>((ref) => AuthService(ref.watch(apiProvider)));
final nfcServiceProvider = Provider<NfcService>((ref) => NfcService());

// Overridden in main() with opened Hive boxes.
final auditRepoProvider = Provider<AuditRepository>((ref) => throw UnimplementedError());
final profileRepoProvider = Provider<ProfileRepository>((ref) => throw UnimplementedError());

/// Null until an Owner sets an org signing key.
final signerProvider = FutureProvider<PayloadSigner?>((ref) async {
  final k = await ref.watch(authServiceProvider).readSigningKey();
  return (k == null || k.isEmpty) ? null : PayloadSigner(k);
});

class AuthController extends StateNotifier<AsyncValue<AppUser?>> {
  AuthController(this._svc) : super(const AsyncValue.loading()) {
    _restore();
  }
  final AuthService _svc;

  Future<void> _restore() async {
    try {
      final u = await _svc.storedSession();
      if (u != null && await _svc.biometricsAvailable()) {
        // Stored session exists: require biometrics before entering the app.
        state = (await _svc.authenticateBiometric())
            ? AsyncValue.data(u)
            : const AsyncValue.data(null);
      } else {
        state = AsyncValue.data(u);
      }
    } catch (e, s) {
      state = AsyncValue.error(e, s);
    }
  }

  Future<void> login(String email, String password) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _svc.login(email, password));
  }

  Future<void> unlockWithBiometrics() async {
    final u = await _svc.storedSession();
    if (u != null && await _svc.authenticateBiometric()) state = AsyncValue.data(u);
  }

  Future<void> logout() async {
    await _svc.logout();
    state = const AsyncValue.data(null);
  }
}

final authStateProvider = StateNotifierProvider<AuthController, AsyncValue<AppUser?>>(
  (ref) => AuthController(ref.watch(authServiceProvider)),
);
