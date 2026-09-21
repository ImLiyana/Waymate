import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../models/user_model.dart';
import '../services/chat_service.dart';
import '../services/group_service.dart';
import 'profile_screen.dart';
import 'members_screen.dart';
import 'chat_screen.dart';
import 'trip_destination_screen.dart';
import 'announcements_screen.dart';

class AppDrawer extends StatelessWidget {
  final AppUser user;
  final VoidCallback onLogout;
  final _groupService = GroupService();

  AppDrawer({required this.user, required this.onLogout, super.key});

  Future<void> _confirmEndTrip(BuildContext context) async {
    final groupId = user.groupId;
    if (groupId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('End this trip?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This removes every member from the group, deletes the group chat, and ends the group entirely. '
          "Everyone — including you — will be free to join or start a new group afterward. This can't be undone.",
          style: TextStyle(color: AppColors.textOnNavySecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('End Trip', style: TextStyle(color: AppColors.sos, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _groupService.endTrip(groupId: groupId, guideUid: user.uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trip ended. All members have been removed.')));
      }
    } catch (e) {
      debugPrint('endTrip failed for group=$groupId: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not end the trip. Try again.')));
      }
    }
  }

  /// A tourist leaving is functionally identical to a guide removing
  /// them — same cleanup (clear groupId, delete their location, drop
  /// them from memberIds) — just self-initiated instead of guide-
  /// initiated, so this reuses removeMember() rather than duplicating
  /// that logic.
  Future<void> _confirmLeaveGroup(BuildContext context) async {
    final groupId = user.groupId;
    if (groupId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('Leave this group?', style: TextStyle(color: Colors.white)),
        content: const Text(
          "You'll stop appearing on your guide's map and lose access to this group's chat. "
          'You can join a new group afterward.',
          style: TextStyle(color: AppColors.textOnNavySecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.of(c).pop(true),
            child: const Text('Leave', style: TextStyle(color: AppColors.sos, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _groupService.removeMember(groupId: groupId, memberUid: user.uid);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("You've left the group.")));
      }
    } catch (e) {
      debugPrint('leaveGroup failed for uid=${user.uid} in group=$groupId: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not leave the group. Try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGuide = user.role == 'guide';
    final groupId = user.groupId;

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
                          isGuide ? 'Guide' : 'Tourist',
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
              leading: groupId != null
                  ? _ChatIconWithBadge(groupId: groupId, uid: user.uid)
                  : const Icon(Icons.chat_bubble_outline, color: AppColors.gold),
              title: const Text('Group Chat', style: TextStyle(color: Colors.white)),
              onTap: () {
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                Navigator.of(context).pop();
                if (groupId != null) {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ChatScreen(groupId: groupId, currentUser: user),
                  ));
                } else {
                  scaffoldMessenger.showSnackBar(
                    const SnackBar(content: Text("Still setting up your group — try again in a moment.")),
                  );
                }
              },
            ),

            // Trip management — guide only. Moved off the Home
            // dashboard so Home stays focused on live map state.
            if (isGuide && groupId != null) ...[
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: AppColors.gold),
                title: const Text('Trip Destination', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripDestinationScreen(groupId: groupId)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.campaign_outlined, color: AppColors.gold),
                title: const Text('Announcements', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => AnnouncementsScreen(groupId: groupId)));
                },
              ),
            ],

            if (isGuide && groupId != null)
              ListTile(
                leading: const Icon(Icons.flag_outlined, color: AppColors.sos),
                title: const Text('End Trip', style: TextStyle(color: AppColors.sos)),
                onTap: () {
                  Navigator.of(context).pop();
                  _confirmEndTrip(context);
                },
              ),
            if (!isGuide && groupId != null)
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: AppColors.sos),
                title: const Text('Leave Group', style: TextStyle(color: AppColors.sos)),
                onTap: () {
                  Navigator.of(context).pop();
                  _confirmLeaveGroup(context);
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

/// Chat icon with a small red unread-count badge, live-updating via
/// ChatService.unreadCountStream. Shows "9+" past 9 to avoid the badge
/// growing unbounded for a very chatty group.
class _ChatIconWithBadge extends StatelessWidget {
  final String groupId;
  final String uid;
  final _chatService = ChatService();

  _ChatIconWithBadge({required this.groupId, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _chatService.unreadCountStream(groupId: groupId, uid: uid),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.chat_bubble_outline, color: AppColors.gold),
            if (count > 0)
              Positioned(
                right: -6,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  constraints: const BoxConstraints(minWidth: 16),
                  decoration: BoxDecoration(color: AppColors.sos, borderRadius: BorderRadius.circular(10)),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}