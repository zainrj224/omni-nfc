import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:nfc_manager/nfc_manager.dart';

import 'ndef_codec.dart';

enum SignatureStatus { none, noKey, valid, invalid }

/// HMAC-SHA256 over (tag UID + canonical payload). Binds the payload to one tag UID,
/// so data copied onto a different tag fails verification.
/// Limit: tags with rewritable UIDs ("magic" cards) can still be cloned in full.
class PayloadSigner {
  PayloadSigner(String key) : _key = utf8.encode(key);
  final List<int> _key;

  Uint8List _mac(String uid, List<NdefRecord> records) {
    final msg = [...utf8.encode(uid), 0, ...canonical(records)];
    return Uint8List.fromList(Hmac(sha256, _key).convert(msg).bytes);
  }

  NdefRecord signatureRecord(String uid, List<NdefRecord> records) =>
      NdefRecord.createMime(sigMime, _mac(uid, records));

  SignatureStatus verify(String uid, List<NdefRecord> records) {
    final sig = records.where((r) =>
        r.typeNameFormat == NdefTypeNameFormat.media && String.fromCharCodes(r.type) == sigMime);
    if (sig.isEmpty) return SignatureStatus.none;
    final expected = _mac(uid, records);
    final got = sig.first.payload;
    if (got.length != expected.length) return SignatureStatus.invalid;
    var diff = 0; // constant-time compare
    for (var i = 0; i < got.length; i++) {
      diff |= got[i] ^ expected[i];
    }
    return diff == 0 ? SignatureStatus.valid : SignatureStatus.invalid;
  }
}
