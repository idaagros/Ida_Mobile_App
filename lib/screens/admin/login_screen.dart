// lib/screens/login_screen.dart
// Drop-in replacement — works with your existing backend (email-based login)
// Username field sends value as BOTH email and username so either backend works

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../localization/app_localizations.dart';
import '../localization/app_locale.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;

  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  static const idaGreen = Color(0xFF3B7A28);
  static const idaDark = Color(0xFF1E4012);

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final loc = AppLocalizations.of(context)!;
    final userInput = _userCtrl.text.trim();
    final password = _passCtrl.text;

    if (userInput.isEmpty || password.isEmpty) {
      _showError(loc.enterCredentialsError);
      return;
    }

    setState(() => _loading = true);

    try {
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/api/auth/login'),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({
          'email': userInput, // current backend expects 'email'
          'username': userInput, // new backend expects 'username'
          'password': password,
        }),
      );

      final result = jsonDecode(res.body);
      setState(() => _loading = false);

      if (result['token'] != null) {
        await ApiService.saveSession(result);
        if (mounted) Navigator.pushReplacementNamed(context, '/dashboard');
      } else {
        _showError(result['error'] ?? loc.invalidCredentialsError);
      }
    } catch (e) {
      setState(() => _loading = false);
      _showError(loc.cannotConnectError);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const Icon(Icons.error_outline, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(msg, style: const TextStyle(fontSize: 13))),
        ]),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: idaDark,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: Column(children: [
            // ── Brand header ───────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Column(children: [
                Image.asset('assets/images/idalogo.png', height: 68),
                const SizedBox(height: 10),
                Text(
                  loc.appTagline,
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 13, letterSpacing: 0.4),
                ),
                const SizedBox(height: 16),
                _languageToggle(),
              ]),
            ),

            // ── Login card ─────────────────────────────────────────
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                ),
                padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(loc.signIn,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: idaDark)),
                      const SizedBox(height: 4),
                      Text(loc.enterCredentials,
                          style: const TextStyle(fontSize: 13, color: Colors.grey)),
                      const SizedBox(height: 28),

                      // Username / email field
                      TextFormField(
                        controller: _userCtrl,
                        textInputAction: TextInputAction.next,
                        autocorrect: false,
                        keyboardType: TextInputType.emailAddress,
                        decoration: _inputDeco(
                          label: loc.usernameLabel,
                          icon: Icons.person_outline_rounded,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Password field
                      TextFormField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        textInputAction: TextInputAction.done,
                        onFieldSubmitted: (_) => _login(),
                        decoration: _inputDeco(
                          label: loc.passwordLabel,
                          icon: Icons.lock_outline_rounded,
                        ).copyWith(
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              size: 20,
                            ),
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),

                      // Sign in button
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _loading ? null : _login,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: idaGreen,
                            disabledBackgroundColor: idaGreen.withOpacity(0.6),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              : Text(loc.signIn,
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white)),
                        ),
                      ),

                      const SizedBox(height: 32),
                      Center(
                        child: Text(
                          '© ${DateTime.now().year} Ida AgriCo',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // Local-only until login (nothing to persist against yet) — once a
  // user signs in, their account's own preferred_language takes over
  // as the authoritative source (see ApiService.saveSession).
  Widget _languageToggle() {
    return ValueListenableBuilder<Locale>(
      valueListenable: appLocaleNotifier,
      builder: (context, locale, _) {
        final loc = AppLocalizations.of(context)!;
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            _langChip('EN', 'en', locale.languageCode == 'en'),
            _langChip('मर', 'mr', locale.languageCode == 'mr'),
          ]),
        );
      },
    );
  }

  Widget _langChip(String label, String code, bool selected) {
    return GestureDetector(
      onTap: () => AppLocale.apply(code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? idaGreen : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : Colors.white60,
                fontSize: 12.5,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  InputDecoration _inputDeco({required String label, required IconData icon}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE8D8))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDDE8D8))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF3B7A28), width: 1.8)),
        filled: true,
        fillColor: const Color(0xFFF7FAF5),
      );
}
