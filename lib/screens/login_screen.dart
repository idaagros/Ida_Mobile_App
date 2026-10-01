// lib/screens/login_screen.dart
// Drop-in replacement — works with your existing backend (email-based login)
// Username field sends value as BOTH email and username so either backend works

import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../localization/app_localizations.dart';
import 'face_login_screen.dart';
import '../config/app_config.dart';
import '../widgets/server_address_dialog.dart';

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
    // Oct 2026 (group F): lighter look to match the website's sign in.
    // Face first; username and password open below it on request.
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F1),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [Color(0xFFEEF5E8), Color(0xFFF4F5F1)],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Image.asset('assets/images/idalogo.png', height: 72),
                      const SizedBox(height: 8),
                      Text(
                        loc.appTagline,
                        key: ValueKey('tagline_${loc.appTagline}'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF5F6A58), fontSize: 13, letterSpacing: 0.3),
                      ),
                      const SizedBox(height: 28),
                      Text(loc.signIn,
                          key: ValueKey('signin_title_${loc.signIn}'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1A2812))),
                      const SizedBox(height: 4),
                      const Text('Look at the camera to sign in',
                          key: ValueKey('signin_subtitle_face_first'),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: Color(0xFF5F6A58))),
                      const SizedBox(height: 26),

                      // Face login — the primary, default path. No typing
                      // needed, the priority for village managers who find
                      // typing a username/password difficult.
                      SizedBox(
                        height: 58,
                        child: ElevatedButton.icon(
                          onPressed: _loading
                              ? null
                              : () => Navigator.push(context, MaterialPageRoute(builder: (_) => const FaceLoginScreen())),
                          icon: const Icon(Icons.face_outlined, color: Colors.white, size: 26),
                          label: const Text('Sign in with face',
                              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: idaGreen,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 50,
                        child: OutlinedButton(
                          onPressed: () => setState(() => _showPasswordForm = !_showPasswordForm),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2B3A24),
                            side: const BorderSide(color: Color(0xFFD5DCCD)),
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(_showPasswordForm ? 'Hide username and password' : 'Use username and password',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        ),
                      ),

                      if (_showPasswordForm) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: const Color(0xFFE2E6DC)),
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            TextFormField(
                              controller: _userCtrl,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              keyboardType: TextInputType.emailAddress,
                              decoration: _inputDeco(label: loc.usernameLabel, icon: Icons.person_outline_rounded),
                            ),
                            const SizedBox(height: 14),
                            TextFormField(
                              controller: _passCtrl,
                              obscureText: _obscure,
                              textInputAction: TextInputAction.done,
                              onFieldSubmitted: (_) => _login(),
                              decoration: _inputDeco(label: loc.passwordLabel, icon: Icons.lock_outline_rounded).copyWith(
                                suffixIcon: IconButton(
                                  tooltip: _obscure ? 'Show password' : 'Hide password',
                                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20),
                                  onPressed: () => setState(() => _obscure = !_obscure),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 50,
                              child: ElevatedButton(
                                onPressed: _loading ? null : _login,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: idaGreen,
                                  disabledBackgroundColor: idaGreen.withValues(alpha: 0.6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                child: _loading
                                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                    : Text(loc.signIn,
                                        key: ValueKey('signin_btn_${loc.signIn}'),
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                              ),
                            ),
                          ]),
                        ),
                      ],

                      const SizedBox(height: 18),
                      const Text('Forgot your password? Ask your admin to set a new one.',
                          textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, color: Color(0xFF5F6A58))),
                      const SizedBox(height: 24),
                      // Long-press opens "Server address" - for a phone
                      // whose old server address no longer works (it can't
                      // sign in to reach App settings).
                      Center(
                        child: GestureDetector(
                          onLongPress: () async {
                            final changed = await showServerAddressDialog(context);
                            if (changed && mounted) setState(() {});
                          },
                          child: Column(children: [
                            Text('© ${DateTime.now().year} Ida AgriCo', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            if (AppConfig.isCustomHost)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('Server: ${AppConfig.displayHost}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
        fillColor: Colors.white,
      );
}
