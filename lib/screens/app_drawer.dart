import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/user_model.dart';
import 'profile_screen.dart';
import 'members_screen.dart';
import 'chat_screen.dart';

class AppDrawer extends StatelessWidget {
  final AppUser user;
  final VoidCallback onLogout;

  const AppDrawer({required this.user, required this.onLogout, super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.navyDark,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.navyCard,
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(user.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        Text(
                          user.role == 'guide' ? 'Guide' : 'Tourist',
                          style: const TextStyle(color: AppColors.textOnNavySecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline, color: AppColors.gold),
              title: const Text('My Profile', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.groups_outlined, color: AppColors.gold),
              title: const Text('Group Members', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MembersScreen()));
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline, color: AppColors.gold),
              title: const Text('Group Chat', style: TextStyle(color: Colors.white)),
              onTap: () {
                Navigator.of(context).pop();
                if (user.groupId != null) {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChatScreen(groupId: user.groupId!, currentUser: user),
                  ));
                }
              },
            ),
            const Divider(color: AppColors.navyBorder, height: 32),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.sos),
              title: const Text('Log Out', style: TextStyle(color: AppColors.sos)),
              onTap: onLogout,
            ),
          ],
        ),
      ),
    );
  }
}