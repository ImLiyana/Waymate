import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/group_service.dart';

/// Accessed from the drawer. Shows the group's current announcement
/// (if any) with a Clear action, plus a compose box to send a new one.
/// No history list — the Firestore schema only ever stores ONE current
/// announcement per group (sending a new one replaces it), so there's
/// nothing to show beyond "what's live right now."
class AnnouncementsScreen extends StatefulWidget {
  final String groupId;
  const AnnouncementsScreen({required this.groupId, super.key});

  @override
  State<AnnouncementsScreen> createState() => _AnnouncementsScreenState();
}

class _AnnouncementsScreenState extends State<AnnouncementsScreen> {
  final _groupService = GroupService();
  final _controller = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    await _groupService.postAnnouncement(groupId: widget.groupId, text: text);
    if (mounted) {
      _controller.clear();
      setState(() => _sending = false);
      FocusScope.of(context).unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('Announcements')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('CURRENTLY SHOWING TO YOUR GROUP', style: AppTextStyles.label),
            const SizedBox(height: 10),
            StreamBuilder<Map<String, dynamic>?>(
              stream: _groupService.announcementStream(widget.groupId),
              builder: (context, snapshot) {
                final ann = snapshot.data;
                if (ann == null) {
                  return const NavyCard(
                    child: Text('No announcement is currently active.', style: AppTextStyles.body),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(14)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.campaign, color: AppColors.navyDark, size: 20),
                        const SizedBox(width: 10),
                        Expanded(child: Text(ann['text'] as String? ?? '', style: const TextStyle(color: AppColors.navyDark, fontWeight: FontWeight.w600, fontSize: 14))),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.close, size: 18, color: AppColors.sos),
                      label: const Text('Clear Announcement', style: TextStyle(color: AppColors.sos)),
                      style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.sos, width: 1.5)),
                      onPressed: () => _groupService.clearAnnouncement(groupId: widget.groupId),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const Divider(color: AppColors.navyBorder),
            const SizedBox(height: 24),
            const Text('SEND A NEW ANNOUNCEMENT', style: AppTextStyles.label),
            const SizedBox(height: 10),
            TextField(
              controller: _controller,
              maxLines: 3,
              style: AppTextStyles.body,
              decoration: const InputDecoration(hintText: 'e.g. Bus leaves in 10 minutes from the north gate'),
            ),
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navyDark))
                  : const Text('Send to Group'),
            ),
            const SizedBox(height: 12),
            const Text(
              'Sending a new announcement replaces the one currently shown to your group.',
              style: TextStyle(color: AppColors.textOnNavyMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}