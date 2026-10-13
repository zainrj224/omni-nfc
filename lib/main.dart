import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'app.dart';
import 'core/storage.dart';
import 'providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  final audit = await AuditRepository.open();
  final profiles = await ProfileRepository.open();
  runApp(ProviderScope(
    overrides: [
      auditRepoProvider.overrideWithValue(audit),
      profileRepoProvider.overrideWithValue(profiles),
    ],
    child: const OmniNfcApp(),
  ));
}
