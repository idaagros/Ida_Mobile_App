import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../localization/app_localizations.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // Set when this phone still holds a sign-in, so the app can be opened
  // without signal (the server is only asked once a screen needs it; an
  // expired sign-in is handled by Api, which sends the person to Login).
  bool _hasSession = false;
  String _who = '';

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = (prefs.getString('token') ?? '').trim();
      if (token.isEmpty) return;
      final display = (prefs.getString('display_name') ?? '').trim();
      final user = (prefs.getString('username') ?? '').trim();
      if (!mounted) return;
      setState(() {
        _hasSession = true;
        _who = display.isNotEmpty ? display : user;
      });
    } catch (_) {
      // no saved sign-in readable: show the normal Sign in button
    }
  }

  void _openLogin() {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const LoginScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2D5A1B),
      body: SafeArea(
        child: Column(children: [
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Image.asset('assets/images/idalogo.png', height: 80),
                const SizedBox(height: 16),
                const Text(
                  'Daily Reporting &\nRegister System',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
              ),
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Welcome back',
                      style:
                          TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                      _hasSession
                          ? (_who.isNotEmpty ? _who : 'Signed in')
                          : 'Sign in to continue',
                      style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  const Spacer(),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _hasSession
                          ? () => Navigator.pushReplacementNamed(
                              context, '/dashboard')
                          : _openLogin,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B7A28),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                          _hasSession
                              ? (_who.isNotEmpty
                                  ? AppLocalizations.of(context)!
                                      .offWelcomeContinue(_who)
                                  : 'Continue')
                              : 'Sign in',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 16, color: Colors.white)),
                    ),
                  ),
                  if (_hasSession) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: _openLogin,
                        child: Text(
                            AppLocalizations.of(context)!.offWelcomeOther,
                            style: const TextStyle(
                                color: Color(0xFF3B7A28), fontSize: 14)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
