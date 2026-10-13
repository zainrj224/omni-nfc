import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:local_auth/local_auth.dart';

import 'models.dart';

abstract class AuthApi {
  Future<String> login(String email, String password);
  Future<void> uploadAudit(String token, List<Map<String, dynamic>> entries);
}

/// Real backend client. Expected endpoints:
///   POST /auth/login        {email, password}      -> {token}
///   POST /audit/batch       {entries:[...]}        (Bearer token)
class HttpAuthApi implements AuthApi {
  HttpAuthApi(this.baseUrl);
  final String baseUrl;

  @override
  Future<String> login(String email, String password) async {
    final r = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    if (r.statusCode != 200) throw Exception('Invalid credentials');
    return (jsonDecode(r.body) as Map<String, dynamic>)['token'] as String;
  }

  @override
  Future<void> uploadAudit(String token, List<Map<String, dynamic>> entries) async {
    final r = await http.post(
      Uri.parse('$baseUrl/audit/batch'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'entries': entries}),
    );
    if (r.statusCode >= 300) throw Exception('Audit upload failed (${r.statusCode})');
  }
}

/// DEV ONLY: issues unsigned tokens locally so the app runs without a backend.
/// Build with --dart-define=DEV_AUTH=false to use HttpAuthApi.
class DevAuthApi implements AuthApi {
  static const _accounts = <String, List<String>>{
    'owner@demo.local': ['owner123', 'owner'],
    'manager@demo.local': ['manager123', 'technical_manager'],
    'operator@demo.local': ['operator123', 'operator'],
  };

  String _b64(Map<String, dynamic> m) =>
      base64Url.encode(utf8.encode(jsonEncode(m))).replaceAll('=', '');

  @override
  Future<String> login(String email, String password) async {
    final a = _accounts[email.trim().toLowerCase()];
    if (a == null || a[0] != password) throw Exception('Invalid credentials');
    final exp = DateTime.now().add(const Duration(hours: 12)).millisecondsSinceEpoch ~/ 1000;
    return '${_b64({'alg': 'none', 'typ': 'JWT'})}.'
        '${_b64({'sub': email, 'email': email, 'role': a[1], 'exp': exp})}.dev';
  }

  @override
  Future<void> uploadAudit(String token, List<Map<String, dynamic>> entries) async {}
}

class AuthService {
  AuthService(this._api, {FlutterSecureStorage? storage, LocalAuthentication? localAuth})
      : _storage = storage ?? const FlutterSecureStorage(),
        _local = localAuth ?? LocalAuthentication();

  final AuthApi _api;
  final FlutterSecureStorage _storage;
  final LocalAuthentication _local;
  static const _tokenKey = 'jwt';

  Future<AppUser> login(String email, String password) async {
    final token = await _api.login(email, password);
    await _storage.write(key: _tokenKey, value: token);
    return AppUser.fromToken(token);
  }

  Future<AppUser?> storedSession() async {
    final t = await _storage.read(key: _tokenKey);
    if (t == null || JwtDecoder.isExpired(t)) return null;
    return AppUser.fromToken(t);
  }

  Future<bool> biometricsAvailable() async {
    try {
      return await _local.canCheckBiometrics && await _local.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateBiometric() async {
    try {
      return await _local.authenticate(
        localizedReason: 'Unlock OmniNFC Pro',
        options: const AuthenticationOptions(biometricOnly: true),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> logout() => _storage.delete(key: _tokenKey);

  // Org signing key lives in secure storage; Owner sets it.
  Future<String?> readSigningKey() => _storage.read(key: 'org_signing_key');
  Future<void> writeSigningKey(String k) => _storage.write(key: 'org_signing_key', value: k);
}
