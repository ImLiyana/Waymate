import 'package:flutter/material.dart';
import 'package:waymate/core/theme.dart';
import 'package:waymate/services/auth_service.dart';
import 'package:waymate/models/user_model.dart';

class ProfileScreen extends StatelessWidget {
  final AppUser user;
  const ProfileScreen({required this.user, super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final email = authService.currentUser?.email ?? '—';

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: AppColors.primary,
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              user.name,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: user.role == 'guide' ? Colors.amber.shade100 : AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                user.role == 'guide' ? 'Guide' : 'Tourist',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: user.role == 'guide' ? Colors.amber.shade800 : AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          _InfoTile(icon: Icons.phone_outlined, label: 'Phone', value: user.phone),
          _InfoTile(icon: Icons.email_outlined, label: 'Email', value: email),
          if (user.emergencyContactPhone != null && user.emergencyContactPhone!.isNotEmpty)
            _InfoTile(icon: Icons.family_restroom, label: 'Emergency Contact', value: user.emergencyContactPhone!),
          if (user.groupId != null)
            _InfoTile(
              icon: Icons.groups_outlined,
              label: user.role == 'guide' ? 'Your Group Code' : 'Group Code',
              value: user.groupId!,
            ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoTile({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}