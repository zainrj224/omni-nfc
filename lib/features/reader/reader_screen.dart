import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/nfc_service.dart';
import '../../core/permissions.dart';
import '../../core/signer.dart';
import '../../providers.dart';
import '../writer/writer_screen.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({super.key});
  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  TagSnapshot? _snap;
  String? _error;
  bool? _nfcOk;
  late final NfcService _nfc = ref.read(nfcServiceProvider);

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _nfc.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final ok = await _nfc.isAvailable();
    if (!mounted) return;
    setState(() => _nfcOk = ok);
    if (!ok) return;
    final signer = await ref.read(signerProvider.future);
    _nfc.startRead(
      signer: signer,
      onTag: (s) {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.click);
        if (mounted) setState(() {
          _snap = s;
          _error = null;
        });
      },
      onError: (m) {
        if (mounted) setState(() => _error = m);
      },
    );
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$what copied')));
  }

  Future<void> _verify() async {
    final s = _snap;
    if (s == null) return;
    final signer = await ref.read(signerProvider.future);
    setState(() => s.signature = s.records.isEmpty
        ? SignatureStatus.none
        : signer == null
            ? SignatureStatus.noKey
            : signer.verify(s.uid, s.records));
  }

  Future<void> _edit() async {
    final s = _snap;
    await _nfc.cancel();
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WriterScreen(
          prefill: s?.parsed.isNotEmpty == true ? s!.parsed.first : null,
        ),
      ),
    );
    if (mounted) _start();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    final canEdit = user != null && can(user.role, Permission.writeTag);
    final s = _snap;

    return Scaffold(
      appBar: AppBar(title: const Text('Scan tag')),
      body: _nfcOk == false
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('NFC is unavailable or turned off. Enable NFC in system settings.',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 18)),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (s == null)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Column(children: [
                        Icon(Icons.contactless, size: 72),
                        SizedBox(height: 12),
                        Text('Hold a tag against the back of the phone',
                            textAlign: TextAlign.center, style: TextStyle(fontSize: 20)),
                      ]),
                    ),
                  ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ),
                if (s != null) ...[
                  _Section('Chip', [
                    _Row('UID', s.uid),
                    _Row('Manufacturer', s.manufacturer),
                    _Row('Technologies', s.technologies.join(', ')),
                    if (s.atqa != null) _Row('ATQA / SAK', '${s.atqa} / ${s.sak?.toRadixString(16) ?? '-'}'),
                    _Row('Memory', s.maxSize == null ? 'n/a' : '${s.usedSize ?? 0} / ${s.maxSize} bytes'),
                    _Row('Access', s.writable ? 'Read-write' : 'Read-only'),
                    _Row('Signature', switch (s.signature) {
                      SignatureStatus.valid => 'Valid',
                      SignatureStatus.invalid => 'INVALID (tampered or cloned)',
                      SignatureStatus.noKey => 'Present or unknown (no key set on this device)',
                      SignatureStatus.none => 'None',
                    }),
                  ]),
                  _Section('Records (${s.parsed.length})', [
                    if (s.parsed.isEmpty) const ListTile(title: Text('Tag is empty')),
                    for (final p in s.parsed)
                      ListTile(
                        title: Text(p.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: SelectableText(p.summary),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    OutlinedButton(onPressed: () => _copy(s.payloadText, 'Payload'), child: const Text('Copy payload')),
                    OutlinedButton(
                        onPressed: () => _copy(const JsonEncoder.withIndent('  ').convert(s.toJson()), 'JSON'),
                        child: const Text('Export JSON')),
                    OutlinedButton(onPressed: () => _copy(s.toCsv(), 'CSV'), child: const Text('Export CSV')),
                    OutlinedButton(onPressed: _verify, child: const Text('Verify signature')),
                  ]),
                  if (canEdit) ...[
                    const SizedBox(height: 12),
                    FilledButton.icon(onPressed: _edit, icon: const Icon(Icons.edit), label: const Text('Edit tag')),
                  ],
                ],
              ],
            ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, this.children);
  final String title;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
            ...children,
          ]),
        ),
      );
}

class _Row extends StatelessWidget {
  const _Row(this.k, this.v);
  final String k;
  final String v;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 120, child: Text(k, style: const TextStyle(fontWeight: FontWeight.w600))),
          Expanded(child: SelectableText(v)),
        ]),
      );
}
