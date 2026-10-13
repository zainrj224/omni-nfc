import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:uuid/uuid.dart';

enum Role {
  owner('Owner'),
  technicalManager('Technical Manager'),
  operator('Operator');

  const Role(this.label);
  final String label;

  /// Maps the JWT `role` claim. Unknown values fall back to the least-privileged role.
  static Role fromClaim(Object? v) {
    switch (v) {
      case 'owner':
        return Role.owner;
      case 'technical_manager':
        return Role.technicalManager;
      default:
        return Role.operator;
    }
  }
}

class AppUser {
  AppUser({required this.id, required this.email, required this.role, required this.token});
  final String id;
  final String email;
  final Role role;
  final String token;

  factory AppUser.fromToken(String token) {
    final c = JwtDecoder.decode(token);
    return AppUser(
      id: (c['sub'] ?? 'unknown').toString(),
      email: (c['email'] ?? c['sub'] ?? '').toString(),
      role: Role.fromClaim(c['role']),
      token: token,
    );
  }
}

class AuditEntry {
  AuditEntry({
    required this.id,
    required this.timestamp,
    required this.userId,
    required this.tagUid,
    required this.action,
    required this.payloadHash,
    this.lat,
    this.lng,
    this.synced = false,
  });

  final String id;
  final DateTime timestamp;
  final String userId;
  final String tagUid;
  final String action; // write | write+lock | format
  final String payloadHash;
  final double? lat; // optional GPS, not collected by default
  final double? lng;
  bool synced;

  factory AuditEntry.create({
    required String userId,
    required String tagUid,
    required String action,
    required String payloadHash,
  }) =>
      AuditEntry(
        id: const Uuid().v4(),
        timestamp: DateTime.now().toUtc(),
        userId: userId,
        tagUid: tagUid,
        action: action,
        payloadHash: payloadHash,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'userId': userId,
        'tagUid': tagUid,
        'action': action,
        'payloadHash': payloadHash,
        'lat': lat,
        'lng': lng,
        'synced': synced,
      };

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        id: j['id'] as String,
        timestamp: DateTime.parse(j['timestamp'] as String),
        userId: j['userId'] as String,
        tagUid: j['tagUid'] as String,
        action: j['action'] as String,
        payloadHash: j['payloadHash'] as String,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        synced: j['synced'] as bool? ?? false,
      );
}

/// Reusable data profile for offline tag programming.
class TagProfile {
  TagProfile({required this.id, required this.name, required this.type, required this.value});
  final String id;
  final String name;
  final String type; // PayloadType.name
  final String value;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'type': type, 'value': value};
  factory TagProfile.fromJson(Map<String, dynamic> j) => TagProfile(
        id: j['id'] as String,
        name: j['name'] as String,
        type: j['type'] as String,
        value: j['value'] as String,
      );
}
