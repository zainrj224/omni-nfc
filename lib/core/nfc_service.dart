import 'dart:async';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/platform_tags.dart';

import 'ndef_codec.dart';
import 'signer.dart';

class NfcFailure implements Exception {
  const NfcFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class WriteReport {
  WriteReport({required this.uid, required this.payloadHash, this.locked = false});
  final String uid;
  final String payloadHash;
  final bool locked;
}

class TagSnapshot {
  TagSnapshot({
    required this.uid,
    required this.technologies,
    required this.manufacturer,
    required this.writable,
    required this.records,
    required this.parsed,
    required this.signature,
    this.atqa,
    this.sak,
    this.maxSize,
    this.usedSize,
  });

  final String uid;
  final List<String> technologies;
  final String manufacturer;
  final String? atqa;
  final int? sak;
  final int? maxSize;
  final int? usedSize;
  final bool writable;
  final List<NdefRecord> records;
  final List<ParsedRecord> parsed;
  SignatureStatus signature;

  String get payloadText => parsed.map((p) => p.summary).join('\n');

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'technologies': technologies,
        'manufacturer': manufacturer,
        'atqa': atqa,
        'sak': sak,
        'maxSizeBytes': maxSize,
        'usedSizeBytes': usedSize,
        'writable': writable,
        'signature': signature.name,
        'records': [
          for (final p in parsed) {'type': p.label, 'mime': p.mime, 'value': p.summary}
        ],
      };

  String toCsv() {
    String q(String s) => '"${s.replaceAll('"', '""')}"';
    final b = StringBuffer('uid,index,type,value\n');
    for (var i = 0; i < parsed.length; i++) {
      b.writeln('${q(uid)},$i,${q(parsed[i].label)},${q(parsed[i].summary)}');
    }
    return b.toString();
  }
}

class NfcService {
  Completer<WriteReport>? _pending;

  Future<bool> isAvailable() => NfcManager.instance.isAvailable();

  // ---- Reading -----------------------------------------------------------

  void startRead({
    required PayloadSigner? signer,
    required void Function(TagSnapshot) onTag,
    required void Function(String) onError,
  }) {
    unawaited(NfcManager.instance.startSession(
      onDiscovered: (tag) async {
        try {
          onTag(snapshotOf(tag, signer));
        } catch (_) {
          onError('Unsupported or unreadable tag');
        }
      },
      onError: (e) async => onError(e.message),
    ));
  }

  static TagSnapshot snapshotOf(NfcTag tag, PayloadSigner? signer) {
    final data = tag.data;
    final id = _identifier(data);
    final uid = id == null ? 'unknown' : hex(id);
    final ndef = Ndef.from(tag);
    final records = ndef?.cachedMessage?.records ?? <NdefRecord>[];
    final nfca = data['nfca'];
    final atqa = nfca is Map && nfca['atqa'] is List ? hex(List<int>.from(nfca['atqa'] as List), sep: '') : null;
    final sak = nfca is Map ? nfca['sak'] as int? : null;

    SignatureStatus sig;
    if (records.isEmpty) {
      sig = SignatureStatus.none;
    } else if (signer == null) {
      sig = SignatureStatus.noKey;
    } else {
      sig = signer.verify(uid, records);
    }

    return TagSnapshot(
      uid: uid,
      technologies: data.keys.toList(),
      manufacturer: _manufacturer(id),
      atqa: atqa,
      sak: sak,
      maxSize: ndef?.maxSize,
      usedSize: ndef?.cachedMessage?.byteLength,
      writable: ndef?.isWritable ?? false,
      records: records,
      parsed: records.map(parseRecord).toList(),
      signature: sig,
    );
  }

  static Uint8List? _identifier(Map<String, dynamic> data) {
    for (final k in ['nfca', 'nfcb', 'nfcf', 'nfcv', 'mifareclassic', 'mifareultralight', 'mifare', 'iso15693']) {
      final t = data[k];
      if (t is Map && t['identifier'] is List) {
        return Uint8List.fromList(List<int>.from(t['identifier'] as List));
      }
    }
    return null;
  }

  static String uidOf(NfcTag tag) {
    final id = _identifier(tag.data);
    return id == null ? 'unknown' : hex(id);
  }

  static String _manufacturer(Uint8List? id) {
    if (id == null || id.isEmpty) return 'Unknown';
    return switch (id[0]) {
      0x04 => 'NXP',
      0x02 => 'STMicroelectronics',
      0x05 => 'Infineon',
      0x07 => 'Texas Instruments',
      _ => 'Unknown (0x${id[0].toRadixString(16).padLeft(2, '0')})',
    };
  }

  // ---- Writing -----------------------------------------------------------

  Future<WriteReport> write({
    required List<NdefRecord> records,
    PayloadSigner? signer,
    bool lock = false,
  }) =>
      _run((tag) async {
        final ndef = Ndef.from(tag);
        if (ndef == null) throw const NfcFailure('Tag is not NDEF-compatible. Use Format Tag first.');
        if (!ndef.isWritable) throw const NfcFailure('Tag is read-only or locked.');
        final uid = uidOf(tag);
        final all = [...records];
        if (signer != null) all.add(signer.signatureRecord(uid, records));
        final msg = NdefMessage(all);
        if (msg.byteLength > ndef.maxSize) {
          throw NfcFailure('Payload is ${msg.byteLength} B but the tag holds ${ndef.maxSize} B.');
        }
        await ndef.write(msg);
        final back = await ndef.read(); // read-back verification
        if (!_same(canonical(back.records, includeSignature: true), canonical(all, includeSignature: true))) {
          throw const NfcFailure('Read-back verification failed. Tag data does not match.');
        }
        var locked = false;
        if (lock) {
          await ndef.writeLock(); // irreversible
          locked = true;
        }
        return WriteReport(
          uid: uid,
          payloadHash: sha256.convert(canonical(records)).toString(),
          locked: locked,
        );
      });

  Future<WriteReport> format() => _run((tag) async {
        final empty = NdefMessage([
          NdefRecord(
            typeNameFormat: NdefTypeNameFormat.empty,
            type: Uint8List(0),
            identifier: Uint8List(0),
            payload: Uint8List(0),
          )
        ]);
        final ndef = Ndef.from(tag);
        if (ndef != null) {
          if (!ndef.isWritable) throw const NfcFailure('Tag is read-only or locked.');
          await ndef.write(empty);
        } else {
          final f = NdefFormatable.from(tag);
          if (f == null) throw const NfcFailure('This tag type cannot be formatted.');
          await f.format(empty);
        }
        return WriteReport(uid: uidOf(tag), payloadHash: sha256.convert(const <int>[]).toString());
      });

  Future<WriteReport> _run(Future<WriteReport> Function(NfcTag) body) {
    final c = Completer<WriteReport>();
    _pending = c;
    unawaited(NfcManager.instance.startSession(
      alertMessage: 'Hold your iPhone near the NFC tag',
      onDiscovered: (tag) async {
        try {
          final r = await body(tag);
          await NfcManager.instance.stopSession(alertMessage: 'Done');
          if (!c.isCompleted) c.complete(r);
        } on NfcFailure catch (e) {
          await NfcManager.instance.stopSession(errorMessage: e.message);
          if (!c.isCompleted) c.completeError(e);
        } catch (_) {
          // Typically a tag removed mid-write (IOException / TagLost).
          const f = NfcFailure('Tag moved away or the write failed. Hold still and retry.');
          await NfcManager.instance.stopSession(errorMessage: f.message);
          if (!c.isCompleted) c.completeError(f);
        }
      },
      onError: (e) async {
        if (!c.isCompleted) c.completeError(NfcFailure(e.message));
      },
    ));
    return c.future;
  }

  Future<void> cancel() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
    final c = _pending;
    if (c != null && !c.isCompleted) c.completeError(const NfcFailure('Cancelled'));
    _pending = null;
  }

  static bool _same(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
