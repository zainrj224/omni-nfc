import 'dart:convert';
import 'dart:typed_data';

import 'package:nfc_manager/nfc_manager.dart';

String hex(List<int> b, {String sep = ':'}) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join(sep).toUpperCase();

const sigMime = 'application/vnd.omninfc.sig';

const _uriPrefixes = [
  '', 'http://www.', 'https://www.', 'http://', 'https://', 'tel:', 'mailto:',
  'ftp://anonymous:anonymous@', 'ftp://ftp.', 'ftps://', 'sftp://', 'smb://',
  'nfs://', 'ftp://', 'dav://', 'news:', 'telnet://', 'imap:', 'rtsp://',
  'urn:', 'pop:', 'sip:', 'sips:', 'tftp:', 'btspp://', 'btl2cap://',
  'btgoep://', 'tcpobex://', 'irdaobex://', 'file://', 'urn:epc:id:',
  'urn:epc:tag:', 'urn:epc:pat:', 'urn:epc:raw:', 'urn:epc:', 'urn:nfc:',
];

enum RecordKind { uri, text, json, vcard, signature, smartPoster, mime, other }

class ParsedRecord {
  ParsedRecord(this.kind, this.summary, {this.mime});
  final RecordKind kind;
  final String summary;
  final String? mime;

  String get label => switch (kind) {
        RecordKind.uri => 'URI',
        RecordKind.text => 'Text',
        RecordKind.json => 'JSON',
        RecordKind.vcard => 'vCard',
        RecordKind.signature => 'Signature',
        RecordKind.smartPoster => 'Smart Poster',
        RecordKind.mime => 'MIME',
        RecordKind.other => 'Other',
      };
}

ParsedRecord parseRecord(NdefRecord r) {
  final type = String.fromCharCodes(r.type);
  final p = r.payload;
  switch (r.typeNameFormat) {
    case NdefTypeNameFormat.nfcWellknown:
      if (type == 'U' && p.isNotEmpty) {
        final prefix = p[0] < _uriPrefixes.length ? _uriPrefixes[p[0]] : '';
        return ParsedRecord(RecordKind.uri, prefix + utf8.decode(p.sublist(1), allowMalformed: true));
      }
      if (type == 'T' && p.isNotEmpty) {
        final langLen = p[0] & 0x3F;
        final start = 1 + langLen;
        final txt = start <= p.length ? utf8.decode(p.sublist(start), allowMalformed: true) : '';
        return ParsedRecord(RecordKind.text, txt);
      }
      if (type == 'Sp') return ParsedRecord(RecordKind.smartPoster, '${p.length} bytes');
      return ParsedRecord(RecordKind.other, 'Well-known "$type", ${p.length} bytes');
    case NdefTypeNameFormat.media:
      if (type == sigMime) return ParsedRecord(RecordKind.signature, hex(p, sep: ''), mime: type);
      if (type == 'application/json') {
        return ParsedRecord(RecordKind.json, utf8.decode(p, allowMalformed: true), mime: type);
      }
      if (type == 'text/vcard' || type == 'text/x-vcard') {
        return ParsedRecord(RecordKind.vcard, utf8.decode(p, allowMalformed: true), mime: type);
      }
      return ParsedRecord(RecordKind.mime, '$type, ${p.length} bytes', mime: type);
    default:
      return ParsedRecord(RecordKind.other, '${r.typeNameFormat.name}, ${p.length} bytes');
  }
}

bool _isSig(NdefRecord r) =>
    r.typeNameFormat == NdefTypeNameFormat.media && String.fromCharCodes(r.type) == sigMime;

/// Deterministic byte encoding of records, used for hashing, signing and read-back checks.
Uint8List canonical(List<NdefRecord> records, {bool includeSignature = false}) {
  final b = BytesBuilder();
  for (final r in records) {
    if (!includeSignature && _isSig(r)) continue;
    b.addByte(r.typeNameFormat.index);
    b.add(_u32(r.type.length));
    b.add(r.type);
    b.add(_u32(r.payload.length));
    b.add(r.payload);
  }
  return b.toBytes();
}

Uint8List _u32(int n) => Uint8List(4)..buffer.asByteData().setUint32(0, n);

enum PayloadType { url, text, json }

class PayloadBuilder {
  /// Throws [FormatException] with a user-readable message on invalid input.
  static List<NdefRecord> build(PayloadType t, String raw) {
    final v = raw.trim();
    if (v.isEmpty) throw const FormatException('Payload is empty');
    switch (t) {
      case PayloadType.url:
        final u = Uri.tryParse(v);
        if (u == null || !u.hasScheme) {
          throw const FormatException('Enter a full URL, e.g. https://example.com/a');
        }
        return [NdefRecord.createUri(u)];
      case PayloadType.text:
        return [NdefRecord.createText(v)];
      case PayloadType.json:
        try {
          final compact = jsonEncode(jsonDecode(v));
          return [NdefRecord.createMime('application/json', Uint8List.fromList(utf8.encode(compact)))];
        } catch (_) {
          throw const FormatException('Invalid JSON');
        }
    }
  }
}
