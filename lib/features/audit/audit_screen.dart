import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/permissions.dart';
import '../../providers.dart';

class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authStateProvider).valueOrNull;
    if (user == null || !can(user.role, Permission.viewAuditLog)) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audit log')),
        body: const Center(child: Text('Access denied for your role.', style: TextStyle(fontSize: 18))),
      );
    }
    final repo = ref.watch(auditRepoProvider);
    final fmt = DateFormat('yyyy-MM-dd HH:mm:ss');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit log'),
        actions: [
          IconButton(
            tooltip: 'Copy CSV',
            onPressed: () {
              final b = StringBuffer('timestamp,user,uid,action,payload_sha256,synced\n');
              for (final e in repo.all()) {
                b.writeln('${e.timestamp.toIso8601String()},${e.userId},${e.tagUid},${e.action},${e.payloadHash},${e.synced}');
              }
              Clipboard.setData(ClipboardData(text: b.toString()));
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copied')));
            },
            icon: const Icon(Icons.copy_all),
          ),
          IconButton(
            tooltip: 'Sync now',
            onPressed: () async {
              final m = ScaffoldMessenger.of(context);
              try {
                final n = await repo.sync(ref.read(apiProvider), user.token);
                m.showSnackBar(SnackBar(content: Text('Synced $n entries')));
              } catch (_) {
                m.showSnackBar(const SnackBar(content: Text('Offline. Entries stay queued.')));
              }
            },
            icon: const Icon(Icons.sync),
          ),
        ],
      ),
      body: ValueListenableBuilder(
        valueListenable: repo.listenable,
        builder: (_, __, ___) {
          final items = repo.all();
          if (items.isEmpty) return const Center(child: Text('No operations logged yet.'));
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final e = items[i];
              return ListTile(
                leading: Icon(e.synced ? Icons.cloud_done : Icons.cloud_off),
                title: Text('${e.action.toUpperCase()}  ${e.tagUid}'),
                subtitle: Text('${fmt.format(e.timestamp.toLocal())}\n${e.userId}\nSHA-256 ${e.payloadHash.substring(0, 16)}...'),
                isThreeLine: true,
              );
            },
          );
        },
      ),
    );
  }
}
