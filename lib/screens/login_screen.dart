// lib/screens/login_screen.dart
// Drop-in replacement — works with your existing backend (email-based login)
// Username field sends value as BOTH email and username so either backend works

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../localization/app_localizations.dart';
import 'face_login_screen.dart';

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
  // Password form starts collapsed - face login is the primary,
  // default path (confirmed directly: "no typing needed at all" for
  // the typical user). Tapping "Sign in with password instead"
  // reveals it, for the fallback cases where someone genuinely needs
  // it (a device without face enrollment yet, or repeated face-match
  // failures).
  bool _showPasswordForm = false;

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
                  key: ValueKey('tagline_${loc.appTagline}'),
                  style: const TextStyle(
                      color: Colors.white60, fontSize: 13, letterSpacing: 0.4),
                ),
                const SizedBox(height: 10),
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
                          key: ValueKey('signin_title_${loc.signIn}'),
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: idaDark)),
                      const SizedBox(height: 4),
                      Text('Look at the camera to sign in',
                          key: const ValueKey('signin_subtitle_face_first'),
                          style: const TextStyle(
                              fontSize: 13, color: Colors.grey)),
                      const SizedBox(height: 28),

                      // Face login — the primary, default path. No
                      // typing required, confirmed directly as the
                      // priority for village managers who find typing
                      // a username/password difficult.
                      SizedBox(
                        width: double.infinity,
                        height: 56,
                        child: ElevatedButton.icon(
                          onPressed: _loading
                              ? null
                              : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const FaceLoginScreen()),
                                  ),
                          icon: const Icon(Icons.face_outlined,
                              color: Colors.white, size: 24),
                          label: const Text('Sign In With Face',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: idaGreen,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                            elevation: 0,
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                      Center(
                        child: TextButton(
                          onPressed: () => setState(
                              () => _showPasswordForm = !_showPasswordForm),
                          child: Text(
                            _showPasswordForm
                                ? 'Hide password sign in'
                                : 'Sign in with password instead',
                            style: const TextStyle(
                                fontSize: 13,
                                color: idaDark,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),

                      if (_showPasswordForm) ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: Divider(color: Colors.grey.shade300)),
                        ]),
                        const SizedBox(height: 20),

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
                        const SizedBox(height: 20),

                        // Sign in button
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _loading ? null : _login,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: idaGreen,
                              disabledBackgroundColor:
                                  idaGreen.withOpacity(0.6),
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
                                    key: ValueKey('signin_btn_${loc.signIn}'),
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white)),
                          ),
                        ),
                      ],

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
