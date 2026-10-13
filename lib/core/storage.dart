import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import 'auth_service.dart';
import 'models.dart';

/// Offline-first audit log. Entries are queued locally and uploaded when online.
class AuditRepository {
  AuditRepository(this._box);
  final Box<String> _box;

  static Future<AuditRepository> open() async =>
      AuditRepository(await Hive.openBox<String>('audit'));

  ValueListenable<Box<String>> get listenable => _box.listenable();

  Future<void> add(AuditEntry e) => _box.put(e.id, jsonEncode(e.toJson()));

  List<AuditEntry> all() {
    final l = _box.values
        .map((s) => AuditEntry.fromJson(jsonDecode(s) as Map<String, dynamic>))
        .toList();
    l.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return l;
  }

  List<AuditEntry> pending() => all().where((e) => !e.synced).toList();

  /// Uploads unsynced entries; returns how many were sent.
  Future<int> sync(AuthApi api, String token) async {
    final p = pending();
    if (p.isEmpty) return 0;
    await api.uploadAudit(token, p.map((e) => e.toJson()).toList());
    for (final e in p) {
      e.synced = true;
      await _box.put(e.id, jsonEncode(e.toJson()));
    }
    return p.length;
  }
}

/// Locally cached tag profiles so technicians can program tags with no connectivity.
class ProfileRepository {
  ProfileRepository(this._box);
  final Box<String> _box;

  static Future<ProfileRepository> open() async =>
      ProfileRepository(await Hive.openBox<String>('profiles'));

  ValueListenable<Box<String>> get listenable => _box.listenable();

  List<TagProfile> all() => _box.values
      .map((s) => TagProfile.fromJson(jsonDecode(s) as Map<String, dynamic>))
      .toList()
    ..sort((a, b) => a.name.compareTo(b.name));

  Future<void> save(String name, String type, String value) {
    final p = TagProfile(id: const Uuid().v4(), name: name, type: type, value: value);
    return _box.put(p.id, jsonEncode(p.toJson()));
  }

  Future<void> delete(String id) => _box.delete(id);
}
