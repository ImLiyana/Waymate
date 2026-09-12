import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../../services/auth_service.dart';
import '../../services/group_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _authService = AuthService();
  final _groupService = GroupService();

  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _groupCodeController = TextEditingController();
  final _emergencyContactController = TextEditingController();

  String _role = 'tourist';
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  final _emailRegex = RegExp(r'^[\w.+-]+@gmail\.com$');

  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your name';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your phone number';
    }
    final digitsOnly = value.trim();
    if (digitsOnly.length != 10 || !RegExp(r'^[0-9]{10}$').hasMatch(digitsOnly)) {
      return 'Phone number must be exactly 10 digits';
    }
    return null;
  }

  String? _validateEmergencyContact(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter an emergency contact number';
    }
    if (value.trim().length != 10 || !RegExp(r'^[0-9]{10}$').hasMatch(value.trim())) {
      return 'Must be exactly 10 digits';
    }
    return null;
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter your email';
    }
    if (!_emailRegex.hasMatch(value.trim().toLowerCase())) {
      return 'Please enter a valid Gmail address (example@gmail.com)';
    }
    return null;
  }

  String? _validateGroupCode(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Please enter the group code your guide gave you';
    }
    if (value.trim().length != 6) {
      return 'Group codes are exactly 6 characters';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter a password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final newUser = await _authService.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        role: _role,
        emergencyContactPhone: _emergencyContactController.text.trim(),
      );

      if (_role == 'guide') {
        await _groupService.createGroupForGuide(
          guideId: newUser.uid,
          groupName: "${newUser.name}'s Group",
        );
      } else {
        // Group code is required for tourists — a tourist with no group
        // has no guide watching over them, which defeats the point of
        // the app. If the code doesn't match a real group, we back the
        // whole registration out rather than leaving an untracked account.
        final code = _groupCodeController.text.trim().toUpperCase();
        final joined = await _groupService.joinGroup(uid: newUser.uid, groupCode: code);
        if (!joined) {
          await _authService.currentUser?.delete();
          if (mounted) {
            setState(() => _errorMessage = 'That group code was not found. Please check it with your guide and try again.');
          }
          return;
        }
      }

      if (mounted) {
        Navigator.of(context).pop();
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _friendlyError(e.code));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'An account with this email already exists.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  InputDecoration _fieldDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: AppColors.primary),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.sos, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.sos, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Join WayMate',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Create your account to get started',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.white.withOpacity(0.85)),
                  ),
                  const SizedBox(height: 24),

                  GlassCard(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('I am a:', style: AppTextStyles.bodyLarge),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: _RoleButton(
                                label: 'Tourist',
                                icon: Icons.hiking,
                                selected: _role == 'tourist',
                                onTap: () => setState(() => _role = 'tourist'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _RoleButton(
                                label: 'Guide',
                                icon: Icons.groups,
                                selected: _role == 'guide',
                                onTap: () => setState(() => _role = 'guide'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),

                        TextFormField(
                          controller: _nameController,
                          style: AppTextStyles.body,
                          decoration: _fieldDecoration('Full Name', Icons.person_outline),
                          validator: _validateName,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          style: AppTextStyles.body,
                          decoration: _fieldDecoration('Phone Number', Icons.phone_outlined).copyWith(
                            counterText: '',
                          ),
                          validator: _validatePhone,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _emergencyContactController,
                          keyboardType: TextInputType.phone,
                          maxLength: 10,
                          style: AppTextStyles.body,
                          decoration: _fieldDecoration('Emergency Contact Number', Icons.family_restroom).copyWith(
                            counterText: '',
                          ),
                          validator: _validateEmergencyContact,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          style: AppTextStyles.body,
                          decoration: _fieldDecoration('Email', Icons.email_outlined),
                          validator: _validateEmail,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          style: AppTextStyles.body,
                          decoration: _fieldDecoration('Password', Icons.lock_outline).copyWith(
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                                color: Colors.grey.shade600,
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          validator: _validatePassword,
                        ),
                        const SizedBox(height: 16),

                        if (_role == 'tourist')
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _groupCodeController,
                                textCapitalization: TextCapitalization.characters,
                                maxLength: 6,
                                style: AppTextStyles.body,
                                decoration: _fieldDecoration('Group Code (from your guide)', Icons.groups_outlined).copyWith(
                                  counterText: '',
                                ),
                                validator: _validateGroupCode,
                              ),
                              const SizedBox(height: 16),
                            ],
                          ),

                        if (_errorMessage != null)
                          Container(
                            padding: const EdgeInsets.all(12),
                            margin: const EdgeInsets.only(bottom: 16),
                            decoration: BoxDecoration(
                              color: AppColors.sos.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.sos.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, color: AppColors.sos, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _errorMessage!,
                                    style: const TextStyle(color: AppColors.sos, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        SizedBox(
                          height: 58,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleRegister,
                            style: ElevatedButton.styleFrom(
                              elevation: 4,
                              shadowColor: AppColors.primary.withOpacity(0.4),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 24, width: 24,
                                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                                  )
                                : const Text('Register'),
                          ),
                        ),
                        const SizedBox(height: 12),

                        Center(
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text(
                              'Already have an account? Log In',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.primary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _RoleButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: AppSpacing.minTouchTarget + 12,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.white,
          border: Border.all(color: AppColors.primary, width: 2),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? Colors.white : AppColors.primary, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: selected ? Colors.white : AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}