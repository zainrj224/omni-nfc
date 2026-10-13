import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nfc_manager/nfc_manager.dart' show NdefRecord;

import '../../core/models.dart';
import '../../core/ndef_codec.dart';
import '../../core/nfc_service.dart';
import '../../core/permissions.dart';
import '../../providers.dart';

class WriterScreen extends ConsumerStatefulWidget {
  const WriterScreen({super.key, this.prefill});
  final ParsedRecord? prefill;
  @override
  ConsumerState<WriterScreen> createState() => _WriterScreenState();
}

class _WriterScreenState extends ConsumerState<WriterScreen> {
  PayloadType _type = PayloadType.url;
  final _value = TextEditingController();
  final _profileName = TextEditingController();
  bool _sign = false;
  bool _lock = false;
  bool _busy = false;
  String? _status;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    final p = widget.prefill;
    if (p != null) {
      switch (p.kind) {
        case RecordKind.uri:
          _type = PayloadType.url;
          _value.text = p.summary;
        case RecordKind.text:
          _type = PayloadType.text;
          _value.text = p.summary;
        case RecordKind.json:
          _type = PayloadType.json;
          _value.text = p.summary;
        default:
      }
    }
  }

  @override
  void dispose() {
    ref.read(nfcServiceProvider).cancel();
    _value.dispose();
    _profileName.dispose();
    super.dispose();
  }

  Future<bool> _confirmLock() async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Permanently lock this tag?'),
          content: const Text('The tag becomes read-only forever. This cannot be undone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Lock after write'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _run(Future<WriteReport> Function() op, AppUser user, String Function(WriteReport) action) async {
    setState(() {
      _busy = true;
      _ok = false;
      _status = 'Hold the tag against the back of the phone...';
    });
    try {
      final r = await op();
      await ref.read(auditRepoProvider).add(AuditEntry.create(
            userId: user.id,
            tagUid: r.uid,
            action: action(r),
            payloadHash: r.payloadHash,
          ));
      HapticFeedback.heavyImpact();
      if (mounted) setState(() {
        _ok = true;
        _status = 'Done and verified. UID ${r.uid}${r.locked ? ' (locked)' : ''}';
      });
    } on NfcFailure catch (e) {
      if (mounted) setState(() => _status = e.message);
    } catch (e) {
      if (mounted) setState(() => _status = 'Failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepareWrite(AppUser user) async {
    final List<NdefRecord> records;
    try {
      records = PayloadBuilder.build(_type, _value.text);
    } on FormatException catch (e) {
      setState(() {
        _ok = false;
        _status = e.message;
      });
      return;
    }
    final lock = _lock && can(user.role, Permission.lockTag);
    if (lock && !await _confirmLock()) return;
    final signer = _sign ? await ref.read(signerProvider.future) : null;
    if (_sign && signer == null) {
      setState(() {
        _ok = false;
        _status = 'No signing key on this device. An Owner must set one first.';
      });
      return;
    }
    await _run(
      () => ref.read(nfcServiceProvider).write(records: records, signer: signer, lock: lock),
      user,
      (r) => r.locked ? 'write+lock' : 'write',
    );
  }

  Future<void> _format(AppUser user) =>
      _run(() => ref.read(nfcServiceProvider).format(), user, (_) => 'format');

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null || !can(user.role, Permission.writeTag)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Write tag')),
        body: const Center(child: Text('Access denied for your role.', style: TextStyle(fontSize: 18))),
      );
    }
    final profiles = ref.read(profileRepoProvider);
    final hasKey = ref.watch(signerProvider).valueOrNull != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Write tag')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<PayloadType>(
            segments: const [
              ButtonSegment(value: PayloadType.url, label: Text('URL'), icon: Icon(Icons.link)),
              ButtonSegment(value: PayloadType.text, label: Text('Text'), icon: Icon(Icons.notes)),
              ButtonSegment(value: PayloadType.json, label: Text('JSON'), icon: Icon(Icons.data_object)),
            ],
            selected: {_type},
            onSelectionChanged: _busy ? null : (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _value,
            enabled: !_busy,
            minLines: _type == PayloadType.json ? 6 : 2,
            maxLines: 10,
            decoration: InputDecoration(
              labelText: switch (_type) {
                PayloadType.url => 'URL',
                PayloadType.text => 'Text / serial number',
                PayloadType.json => 'JSON payload',
              },
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder(
            valueListenable: profiles.listenable,
            builder: (_, __, ___) {
              final list = profiles.all();
              if (list.isEmpty) return const SizedBox.shrink();
              return DropdownButtonFormField<TagProfile>(
                decoration: const InputDecoration(labelText: 'Load saved profile'),
                items: [for (final p in list) DropdownMenuItem(value: p, child: Text(p.name))],
                onChanged: _busy
                    ? null
                    : (p) {
                        if (p == null) return;
                        setState(() {
                          _type = PayloadType.values.byName(p.type);
                          _value.text = p.value;
                        });
                      },
              );
            },
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _profileName,
                decoration: const InputDecoration(labelText: 'Save as profile (offline)'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              iconSize: 28,
              onPressed: () async {
                if (_profileName.text.trim().isEmpty || _value.text.trim().isEmpty) return;
                await profiles.save(_profileName.text.trim(), _type.name, _value.text.trim());
                _profileName.clear();
              },
              icon: const Icon(Icons.save),
            ),
          ]),
          SwitchListTile(
            title: const Text('Sign payload (HMAC, bound to tag UID)'),
            subtitle: Text(hasKey ? 'Org key available' : 'No key set on this device'),
            value: _sign,
            onChanged: _busy ? null : (v) => setState(() => _sign = v),
          ),
          if (can(user.role, Permission.lockTag))
            SwitchListTile(
              title: const Text('Permanently lock after write'),
              subtitle: const Text('Irreversible. Makes the tag read-only.'),
              value: _lock,
              onChanged: _busy ? null : (v) => setState(() => _lock = v),
            ),
          const SizedBox(height: 8),
          if (_status != null)
            Card(
              color: _ok ? Colors.green.withAlpha(50) : null,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  if (_busy) const Padding(padding: EdgeInsets.only(right: 12), child: CircularProgressIndicator()),
                  Expanded(child: Text(_status!, style: const TextStyle(fontSize: 16))),
                ]),
              ),
            ),
          const SizedBox(height: 8),
          if (_busy)
            OutlinedButton(onPressed: () => ref.read(nfcServiceProvider).cancel(), child: const Text('Cancel'))
          else ...[
            FilledButton.icon(
              onPressed: () => _prepareWrite(user),
              icon: const Icon(Icons.nfc),
              label: const Text('Prepare write'),
            ),
            if (can(user.role, Permission.formatTag)) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: () => _format(user), child: const Text('Format / erase tag')),
            ],
          ],
        ],
      ),
    );
  }
}
