import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _pass = TextEditingController();
  bool _hasSession = false;

  @override
  void initState() {
    super.initState();
    ref.read(authServiceProvider).storedSession().then((u) {
      if (mounted) setState(() => _hasSession = u != null);
    });
  }

  @override
  void dispose() {
    _email.dispose();
    _pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final failed = ref.watch(authStateProvider).hasError;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.nfc, size: 72),
                  const SizedBox(height: 8),
                  Text('OmniNFC Pro',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(labelText: 'Email'),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _pass,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    decoration: const InputDecoration(labelText: 'Password'),
                    onSubmitted: (_) => _submit(),
                  ),
                  if (failed)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('Sign-in failed. Check your credentials.',
                          style: TextStyle(color: Theme.of(context).colorScheme.error)),
                    ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _submit, child: const Text('Sign in')),
                  if (_hasSession) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => ref.read(authStateProvider.notifier).unlockWithBiometrics(),
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Unlock with biometrics'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Dev accounts: owner@demo.local / owner123, manager@demo.local / manager123, '
                    'operator@demo.local / operator123',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() =>
      ref.read(authStateProvider.notifier).login(_email.text.trim(), _pass.text);
}
