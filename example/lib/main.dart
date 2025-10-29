import 'dart:async';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:thingsboard_client/thingsboard_client.dart';

void main() {
  runApp(const ThingsboardExampleApp());
}

class ThingsboardExampleApp extends StatelessWidget {
  const ThingsboardExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ThingsBoard Client Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const ThingsboardHomePage(),
    );
  }
}

class ThingsboardHomePage extends StatefulWidget {
  const ThingsboardHomePage({super.key});

  @override
  State<ThingsboardHomePage> createState() => _ThingsboardHomePageState();
}

class _ThingsboardHomePageState extends State<ThingsboardHomePage> {
  final _endpointController = TextEditingController(
    text: 'http://localhost:8080',
  );
  final _emailController = TextEditingController(
    text: 'tenant@thingsboard.org',
  );
  final _passwordController = TextEditingController(text: 'tenant');

  ThingsboardClient? _client;
  bool _isBusy = false;
  String? _status;

  @override
  void dispose() {
    _endpointController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    final client = _client;
    if (client != null) {
      unawaited(client.logout());
    }
    super.dispose();
  }

  Future<void> _attemptLogin() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _status = null;
      _isBusy = true;
    });

    final endpoint = _endpointController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final client = ThingsboardClient(endpoint, computeFunc: compute);
    _client = client;

    try {
      await client.init();
      await client.login(LoginRequest(email, password));
      final user = client.getAuthUser();
      final resolvedStatus = () {
        if (user == null) {
          return 'Authenticated but no user details returned.';
        }
        final first = user.firstName?.trim() ?? '';
        final last = user.lastName?.trim() ?? '';
        final displayName = [first, last]
            .where((value) => value.isNotEmpty)
            .join(' ')
            .trim();
        final identifier = displayName.isNotEmpty
            ? displayName
            : (user.userId ?? 'unknown user');
        final role = user.authority.toShortString();
        return 'Authenticated as $identifier [$role]';
      }();
      if (!mounted) return;
      setState(() {
        _status = resolvedStatus;
      });
    } on ThingsboardError catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'ThingsBoard error: ${error.message ?? error.toString()}';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = 'Unexpected error: $error';
      });
    } finally {
      try {
        await client.logout();
      } catch (_) {
        // Ignore logout errors; typically means the login step failed.
      }
      if (mounted) {
        setState(() {
          _isBusy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ThingsBoard Client Demo')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Configure a ThingsBoard server endpoint and credentials, '
                'then tap Connect to exercise the package. '
                'The legacy console samples remain under lib/legacy.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _endpointController,
                decoration: const InputDecoration(
                  labelText: 'API endpoint',
                  hintText: 'https://your-thingsboard-instance/api',
                ),
                keyboardType: TextInputType.url,
                enabled: !_isBusy,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                enabled: !_isBusy,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
                enabled: !_isBusy,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _isBusy ? null : _attemptLogin,
                icon: _isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.login),
                label: Text(_isBusy ? 'Connecting…' : 'Connect'),
              ),
              const SizedBox(height: 24),
              if (_status != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  child: Text(_status!, style: theme.textTheme.bodyMedium),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
