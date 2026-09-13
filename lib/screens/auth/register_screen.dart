import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../services/auth_service.dart';
import '../../services/group_service.dart';

class RegisterScreen extends StatefulWidget {
  final String? prefilledName;
  final String? prefilledEmail;
  final bool isGoogleSignup;

  const RegisterScreen({
    this.prefilledName,
    this.prefilledEmail,
    this.isGoogleSignup = false,
    super.key,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _groupService = GroupService();

  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _groupCodeController = TextEditingController();

  String _role = 'tourist';
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  final _emailRegex = RegExp(r'^[\w.+-]+@gmail\.com$');

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.prefilledName ?? '');
    _emailController = TextEditingController(text: widget.prefilledEmail ?? '');
  }

  String? _validateName(String? v) => (v == null || v.trim().isEmpty) ? 'Please enter your name' : null;

  String? _validatePhone(String? v) {
    if (v == null || v.trim().isEmpty) return 'Please enter your phone number';
    if (v.trim().length != 10 || !RegExp(r'^[0-9]{10}$').hasMatch(v.trim())) return 'Must be exactly 10 digits';
    return null;
  }

  String? _validateEmergencyContact(String? v) {
    if (v == null || v.trim().isEmpty) return 'Please enter an emergency contact number';
    if (v.trim().length != 10 || !RegExp(r'^[0-9]{10}$').hasMatch(v.trim())) return 'Must be exactly 10 digits';
    return null;
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'Please enter your email';
    if (!_emailRegex.hasMatch(v.trim().toLowerCase())) return 'Please enter a valid Gmail address';
    return null;
  }

  String? _validatePassword(String? v) {
    if (widget.isGoogleSignup) return null; // no password needed for Google signup
    if (v == null || v.isEmpty) return 'Please enter a password';
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  Future<void> _scanQrCode() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const _QrScanScreen()),
    );
    if (result != null) {
      setState(() => _groupCodeController.text = result.toUpperCase());
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final newUser = widget.isGoogleSignup
          ? await _authService.completeGoogleProfile(
              uid: _authService.currentUser!.uid,
              name: _nameController.text.trim(),
              phone: _phoneController.text.trim(),
              role: _role,
              emergencyContactPhone: _emergencyContactController.text.trim(),
            )
          : await _authService.register(
              email: _emailController.text.trim(),
              password: _passwordController.text,
              name: _nameController.text.trim(),
              phone: _phoneController.text.trim(),
              role: _role,
              emergencyContactPhone: _emergencyContactController.text.trim(),
            );

      if (_role == 'guide') {
        await _groupService.createGroupForGuide(guideId: newUser.uid, groupName: "${newUser.name}'s Group");
      } else {
        final code = _groupCodeController.text.trim().toUpperCase();
        if (code.isNotEmpty) {
          final joined = await _groupService.joinGroup(uid: newUser.uid, groupCode: code);
          if (!joined && mounted) setState(() => _errorMessage = 'Account created, but that group code was not found.');
        }
      }

      // For Google signup, AuthGate will automatically detect the new
      // profile and route in — no manual pop needed, since there's no
      // "previous screen" to go back to in that flow.
      if (!widget.isGoogleSignup && mounted) Navigator.of(context).pop();
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _friendlyError(e.code));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'email-already-in-use': return 'An account with this email already exists.';
      case 'weak-password': return 'Password should be at least 6 characters.';
      case 'invalid-email': return 'Please enter a valid email address.';
      default: return 'Something went wrong. Please try again.';
    }
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(labelText: label, prefixIcon: Icon(icon, color: AppColors.gold));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!widget.isGoogleSignup)
                  Row(children: [IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.arrow_back, color: Colors.white))]),
                Text(
                  widget.isGoogleSignup ? 'Almost done!' : 'Join WayMate',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.isGoogleSignup ? 'Just a few more details to finish setting up' : 'Create your account to get started',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.subheading,
                ),
                const SizedBox(height: 20),

                NavyCard(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('I am a:', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: _RoleButton(label: 'Tourist', icon: Icons.hiking, selected: _role == 'tourist', onTap: () => setState(() => _role = 'tourist'))),
                        const SizedBox(width: 10),
                        Expanded(child: _RoleButton(label: 'Guide', icon: Icons.groups, selected: _role == 'guide', onTap: () => setState(() => _role = 'guide'))),
                      ]),
                      const SizedBox(height: 20),

                      TextFormField(controller: _nameController, style: AppTextStyles.body, decoration: _fieldDecoration('Full Name', Icons.person_outline), validator: _validateName),
                      const SizedBox(height: 14),
                      TextFormField(controller: _phoneController, keyboardType: TextInputType.phone, maxLength: 10, style: AppTextStyles.body, decoration: _fieldDecoration('Phone Number', Icons.phone_outlined).copyWith(counterText: ''), validator: _validatePhone),
                      const SizedBox(height: 14),
                      TextFormField(controller: _emergencyContactController, keyboardType: TextInputType.phone, maxLength: 10, style: AppTextStyles.body, decoration: _fieldDecoration('Emergency Contact', Icons.family_restroom).copyWith(counterText: ''), validator: _validateEmergencyContact),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: AppTextStyles.body,
                        enabled: !widget.isGoogleSignup,
                        decoration: _fieldDecoration('Email', Icons.email_outlined),
                        validator: _validateEmail,
                      ),
                      if (!widget.isGoogleSignup) ...[
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _passwordController, obscureText: _obscurePassword, style: AppTextStyles.body,
                          decoration: _fieldDecoration('Password', Icons.lock_outline).copyWith(
                            suffixIcon: IconButton(icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: AppColors.textOnNavyMuted), onPressed: () => setState(() => _obscurePassword = !_obscurePassword)),
                          ),
                          validator: _validatePassword,
                        ),
                      ],
                      const SizedBox(height: 14),

                      if (_role == 'tourist')
                        Row(children: [
                          Expanded(child: TextFormField(controller: _groupCodeController, textCapitalization: TextCapitalization.characters, style: AppTextStyles.body, decoration: _fieldDecoration('Group Code (optional)', Icons.groups_outlined))),
                          const SizedBox(width: 8),
                          Container(
                            height: 52, width: 52,
                            decoration: BoxDecoration(color: AppColors.navyCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.navyBorder)),
                            child: IconButton(icon: const Icon(Icons.qr_code_scanner, color: AppColors.gold), onPressed: _scanQrCode),
                          ),
                        ]),
                      const SizedBox(height: 14),

                      if (_errorMessage != null)
                        Padding(padding: const EdgeInsets.only(bottom: 14), child: Text(_errorMessage!, style: const TextStyle(color: AppColors.sos, fontWeight: FontWeight.w600), textAlign: TextAlign.center)),

                      ElevatedButton(
                        onPressed: _isLoading ? null : _handleRegister,
                        child: _isLoading ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.navyDark)) : const Text('Create Account'),
                      ),
                      if (!widget.isGoogleSignup) ...[
                        const SizedBox(height: 10),
                        Center(child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Already have an account? Log In', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold)))),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  final String label; final IconData icon; final bool selected; final VoidCallback onTap;
  const _RoleButton({required this.label, required this.icon, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 64, alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.gold : AppColors.navy,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.gold, width: selected ? 0 : 1.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: selected ? AppColors.navyDark : AppColors.gold, size: 22),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(color: selected ? AppColors.navyDark : AppColors.gold, fontWeight: FontWeight.bold, fontSize: 13)),
        ]),
      ),
    );
  }
}

class _QrScanScreen extends StatelessWidget {
  const _QrScanScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Scan Group QR Code'), backgroundColor: Colors.black),
      body: MobileScanner(
        onDetect: (capture) {
          final barcodes = capture.barcodes;
          if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
            Navigator.of(context).pop(barcodes.first.rawValue);
          }
        },
      ),
    );
  }
}