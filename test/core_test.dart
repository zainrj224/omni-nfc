import 'package:flutter_test/flutter_test.dart';
import 'package:omninfc_pro/core/models.dart';
import 'package:omninfc_pro/core/ndef_codec.dart';
import 'package:omninfc_pro/core/permissions.dart';
import 'package:omninfc_pro/core/signer.dart';

void main() {
  test('permission matrix', () {
    expect(can(Role.operator, Permission.readTag), isTrue);
    expect(can(Role.operator, Permission.writeTag), isFalse);
    expect(can(Role.technicalManager, Permission.lockTag), isTrue);
    expect(can(Role.technicalManager, Permission.viewAuditLog), isFalse);
    expect(can(Role.owner, Permission.manageSigningKey), isTrue);
  });

  test('unknown role claim falls back to operator', () {
    expect(Role.fromClaim('root'), Role.operator);
    expect(Role.fromClaim(null), Role.operator);
  });

  test('payload builder validates', () {
    expect(() => PayloadBuilder.build(PayloadType.url, 'nope'), throwsFormatException);
    expect(() => PayloadBuilder.build(PayloadType.json, '{bad'), throwsFormatException);
    expect(PayloadBuilder.build(PayloadType.text, 'SN-001'), hasLength(1));
  });

  test('signature binds payload to UID', () {
    final s = PayloadSigner('k');
    final recs = PayloadBuilder.build(PayloadType.url, 'https://example.com/a');
    final signed = [...recs, s.signatureRecord('04:AA', recs)];
    expect(s.verify('04:AA', signed), SignatureStatus.valid);
    expect(s.verify('04:BB', signed), SignatureStatus.invalid);
    expect(PayloadSigner('other').verify('04:AA', signed), SignatureStatus.invalid);
    expect(s.verify('04:AA', recs), SignatureStatus.none);
  });
}
