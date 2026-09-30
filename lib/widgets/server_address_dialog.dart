// lib/widgets/server_address_dialog.dart
//
// Change which server this phone talks to (e.g. when moving from
// duckdns to a Cloudflare domain). Opened from App settings -> Server
// address, and from a long-press on the (c) line at the bottom of the
// login screen (for a phone whose old address no longer works, so it
// can't log in to reach App settings).
//
// A new address is saved only after it answers as the Ida AgriCo
// server (GET /api/health), so a typing mistake can't cut the phone off.

import 'package:flutter/material.dart';
import '../config/app_config.dart';

const _green = Color(0xFF3B7A28);
const _dark = Color(0xFF1E4012);
const _red = Color(0xFFB91C1C);

// Returns true when the address was changed.
Future<bool> showServerAddressDialog(BuildContext context) async {
  final changed = await showDialog<bool>(
    context: context,
    builder: (_) => const _ServerAddressDialog(),
  );
  return changed == true;
}

class _ServerAddressDialog extends StatefulWidget {
  const _ServerAddressDialog();
  @override
  State<_ServerAddressDialog> createState() => _ServerAddressDialogState();
}

class _ServerAddressDialogState extends State<_ServerAddressDialog> {
  final _ctrl = TextEditingController(text: AppConfig.apiHost);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save(String? typed) async {
    // typed == null means "go back to the built-in address"
    final host = typed == null
        ? AppConfig.defaultApiHost
        : AppConfig.normalize(typed);
    if (host == null) {
      setState(() => _error = 'Type a web address, e.g. app.idaagrico.in');
      return;
    }
    if (host == AppConfig.apiHost) {
      Navigator.pop(context, false);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final problem = await AppConfig.test(host);
    if (!mounted) return;
    if (problem != null) {
      setState(() {
        _busy = false;
        _error = problem;
      });
      return;
    }
    await AppConfig.setHost(host);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: _green,
      content: Text('Now using ${AppConfig.displayHost}'),
    ));
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Server address',
          style: TextStyle(color: _dark, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppConfig.isCustomHost
                  ? 'This phone uses a changed address.\n'
                      'Built-in: ${AppConfig.defaultApiHost}'
                  : 'This phone uses the built-in address.',
              style: const TextStyle(fontSize: 12.5, color: Colors.black54),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              enabled: !_busy,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Address',
                hintText: 'https://app.idaagrico.in',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              onSubmitted: (v) => _save(v),
            ),
            const SizedBox(height: 8),
            const Text(
              'It is checked before saving. This changes this phone only.',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(fontSize: 12.5, color: _red)),
            ],
          ],
        ),
      ),
      actions: [
        if (AppConfig.isCustomHost)
          TextButton(
            onPressed: _busy ? null : () => _save(null),
            child: const Text('Use built-in'),
          ),
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _green),
          onPressed: _busy ? null : () => _save(_ctrl.text),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Test & save'),
        ),
      ],
    );
  }
}
