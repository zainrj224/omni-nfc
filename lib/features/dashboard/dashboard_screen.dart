import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permissions.dart';
import '../../providers.dart';
import '../audit/audit_screen.dart';
import '../reader/reader_screen.dart';
import '../writer/writer_screen.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});
  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  StreamSubscription<List<ConnectivityResult>>? _sub;

  @override
  void initState() {
    super.initState();
    _sync();
    _sub = Connectivity().onConnectivityChanged.listen((r) {
      if (!r.contains(ConnectivityResult.none)) _sync();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  /// Background sync queue: flush unsynced audit entries when connectivity returns.
  Future<void> _sync() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    try {
      await ref.read(auditRepoProvider).sync(ref.read(apiProvider), user.token);
    } catch (_) {/* stay queued; retry on next connectivity change */}
  }

  Future<void> _editKey() async {
    final svc = ref.read(authServiceProvider);
    final ctl = TextEditingController(text: await svc.readSigningKey() ?? '');
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Organization signing key'),
        content: TextField(
          controller: ctl,
          obscureText: true,
          decoration: const InputDecoration(helperText: 'Used to sign and verify tag payloads (HMAC-SHA256)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(100, 48)),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      await svc.writeSigningKey(ctl.text.trim());
      ref.invalidate(signerProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();
    final r = user.role;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OmniNFC Pro'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            iconSize: 28,
            onPressed: () => ref.read(authStateProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.badge, size: 32),
              title: Text(user.email),
              subtitle: Text(r.label),
            ),
          ),
          const SizedBox(height: 8),
          if (can(r, Permission.readTag))
            _Tile(Icons.nfc, 'Scan tag', 'Read and inspect NDEF records', () => _push(const ReaderScreen())),
          if (can(r, Permission.writeTag))
            _Tile(Icons.flash_on, 'Quick edit tag', 'Tap a tag, change it, save it back',
                () => _push(const WriterScreen(autoLoad: true))),
          if (can(r, Permission.writeTag))
            _Tile(Icons.edit, 'Write tag', 'Build a payload and program a tag', () => _push(const WriterScreen())),
          if (can(r, Permission.viewAuditLog))
            _Tile(Icons.history, 'Audit log', 'Every write, lock and format', () => _push(const AuditScreen())),
          if (can(r, Permission.manageSigningKey))
            _Tile(Icons.key, 'Signing key', 'Set the organization HMAC key', _editKey),
        ],
      ),
    );
  }

  void _push(Widget w) => Navigator.push(context, MaterialPageRoute(builder: (_) => w));
}

class _Tile extends StatelessWidget {
  const _Tile(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          leading: Icon(icon, size: 40),
          title: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right, size: 32),
          onTap: onTap,
        ),
      );
}
