import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../services/auth_service.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _authService = AuthService();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  Future<void> _handleLogin() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      await _authService.login(email: _emailController.text.trim(), password: _passwordController.text);
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _friendlyError(e.code));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final user = await _authService.signInWithGoogle();
      final googleAccount = _authService.currentUser;

      if (user == null && googleAccount != null && mounted) {
        // Signed in with Google but never registered — finish setup.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => RegisterScreen(
            prefilledName: googleAccount.displayName,
            prefilledEmail: googleAccount.email,
            isGoogleSignup: true,
          )),
        );
      }
      // If user != null: existing account, AuthGate routes them in
      // automatically. If both are null: they cancelled the picker.
    } catch (e) {
      setState(() => _errorMessage = 'Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found': return 'No account found with this email.';
      case 'wrong-password': return 'Incorrect password. Please try again.';
      case 'invalid-email': return 'Please enter a valid email address.';
      default: return 'Something went wrong. Please try again.';
    }
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.gold),
      suffixIcon: label == 'Password'
          ? IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textOnNavyMuted),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Container(
                height: 76, width: 76, alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.navyCard, borderRadius: BorderRadius.circular(18)),
                child: const Icon(Icons.route_rounded, color: AppColors.gold, size: 38),
              ),
              const SizedBox(height: 16),
              const Text('WayMate', textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(height: 4),
              const Text('Safe journeys, together', textAlign: TextAlign.center, style: AppTextStyles.subheading),
              const SizedBox(height: 32),

              NavyCard(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Welcome Back', style: AppTextStyles.heading, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    TextField(controller: _emailController, keyboardType: TextInputType.emailAddress, style: AppTextStyles.body, decoration: _fieldDecoration('Email', Icons.email_outlined)),
                    const SizedBox(height: 16),
                    TextField(controller: _passwordController, obscureText: _obscurePassword, style: AppTextStyles.body, decoration: _fieldDecoration('Password', Icons.lock_outline)),
                    const SizedBox(height: 20),
                    if (_errorMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(_errorMessage!, style: const TextStyle(color: AppColors.sos, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
                      ),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _handleLogin,
                      child: _isLoading
                          ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.navyDark))
                          : const Text('Log In'),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      const Expanded(child: Divider(color: AppColors.navyBorder)),
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('or', style: TextStyle(color: AppColors.textOnNavyMuted))),
                      const Expanded(child: Divider(color: AppColors.navyBorder)),
                    ]),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _handleGoogleSignIn,
                      icon: const Icon(Icons.g_mobiledata, size: 26),
                      label: const Text('Continue with Google'),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account?", style: TextStyle(color: AppColors.textOnNavySecondary)),
                        TextButton(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const RegisterScreen())),
                          child: const Text('Register', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}