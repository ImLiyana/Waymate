import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/group_service.dart';
import '../models/user_model.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final _authService = AuthService();
  final _locationService = LocationService();
  final _groupService = GroupService();
  String? _groupId;
  bool _isCurrentUserGuide = false;
  String? _currentUid;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadGroupId();
  }

  Future<void> _loadGroupId() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    final profile = await _authService.getUserProfile(uid);
    if (mounted) {
      setState(() {
        _groupId = profile?.groupId;
        _isCurrentUserGuide = profile?.role == 'guide';
        _currentUid = uid;
        _loaded = true;
      });
    }
  }

  Future<void> _callNumber(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  Future<void> _confirmRemove(BuildContext sheetContext, String uid, String name) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('Remove member?', style: TextStyle(color: Colors.white)),
        content: Text('$name will be removed from the group and will stop appearing on your map.', style: const TextStyle(color: AppColors.textOnNavySecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Remove', style: TextStyle(color: AppColors.sos, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed == true && _groupId != null) {
      try {
        await _groupService.removeMember(groupId: _groupId!, memberUid: uid);
        if (sheetContext.mounted) Navigator.of(sheetContext).pop(); // close bottom sheet
      } catch (e) {
        // Previously unhandled — a Firestore rules rejection here (e.g.
        // rules that only let a user write their own users/{uid} or
        // locations/{uid} doc) would fail SILENTLY: the groups doc's
        // memberIds array would still update, but the member's own
        // groupId/location docs would stay untouched, making them look
        // "not actually removed" everywhere else in the app.
        debugPrint('removeMember failed for uid=$uid in group=$_groupId: $e');
        if (sheetContext.mounted) {
          ScaffoldMessenger.of(sheetContext).showSnackBar(
            const SnackBar(content: Text('Could not remove this member — check Firestore rules allow it.')),
          );
        }
      }
    }
  }

  Future<void> _confirmTransfer(BuildContext sheetContext, String newGuideUid, String name) async {
    final confirmed = await showDialog<bool>(
      context: sheetContext,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('Transfer leadership?', style: TextStyle(color: Colors.white)),
        content: Text('$name will become the new guide. You will become a regular tourist in this group.', style: const TextStyle(color: AppColors.textOnNavySecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Transfer', style: TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold))),
        ],
      ),
    );
    if (confirmed == true && _groupId != null && _currentUid != null) {
      try {
        await _groupService.transferGuideRole(groupId: _groupId!, currentGuideUid: _currentUid!, newGuideUid: newGuideUid);
        if (sheetContext.mounted) Navigator.of(sheetContext).pop(); // close bottom sheet
        if (mounted) Navigator.of(context).pop(); // leave screen since role just changed
      } catch (e) {
        debugPrint('transferGuideRole failed (from $_currentUid to $newGuideUid) in group=$_groupId: $e');
        if (sheetContext.mounted) {
          ScaffoldMessenger.of(sheetContext).showSnackBar(
            const SnackBar(content: Text('Could not transfer leadership — check Firestore rules allow it.')),
          );
        }
      }
    }
  }

  Future<void> _showMemberDetails({
    required String uid,
    required String name,
    required String role,
    required String phone,
    required int battery,
    required bool isActive,
    required double? lat,
    required double? lng,
  }) async {
    final isSelf = uid == _currentUid;
    final canManage = _isCurrentUserGuide && !isSelf && role == 'tourist' && _groupId != null;

    String? address;
    double? distanceKm;
    AppUser? profile;

    if (lat != null && lng != null) {
      address = await _locationService.getAddressFromCoordinates(lat, lng);
    }
    profile = await _authService.getUserProfile(uid);
    final emergencyPhone = profile?.emergencyContactPhone;

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.navyCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(role == 'guide' ? Icons.shield_outlined : Icons.person_outline, color: AppColors.gold, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600))),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: isActive ? AppColors.success : AppColors.inactive, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(
                role == 'guide' ? 'Guide' : (isActive ? 'Active' : 'Inactive'),
                style: TextStyle(color: isActive ? AppColors.success : AppColors.textOnNavySecondary, fontSize: 12),
              ),
            ]),
            const SizedBox(height: 16),

            if (phone.isNotEmpty) ...[
              Row(children: [
                const Icon(Icons.phone_outlined, color: AppColors.textOnNavySecondary, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(phone, style: const TextStyle(color: Colors.white, fontSize: 14))),
                IconButton(
                  icon: const Icon(Icons.call, color: AppColors.gold, size: 20),
                  onPressed: () => _callNumber(phone),
                ),
              ]),
              const SizedBox(height: 8),
            ],

            if (address != null) ...[
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.location_on_outlined, color: AppColors.textOnNavySecondary, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(address, style: const TextStyle(color: Colors.white, fontSize: 14))),
              ]),
              const SizedBox(height: 8),
            ],

            if (battery >= 0) ...[
              Row(children: [
                Icon(battery <= 15 ? Icons.battery_alert : Icons.battery_std,
                    color: battery <= 15 ? AppColors.medical : AppColors.textOnNavySecondary, size: 18),
                const SizedBox(width: 8),
                Text('$battery% battery', style: const TextStyle(color: Colors.white, fontSize: 14)),
              ]),
              const SizedBox(height: 8),
            ],

            if (emergencyPhone != null && emergencyPhone.isNotEmpty) ...[
              Row(children: [
                const Icon(Icons.family_restroom, color: AppColors.textOnNavySecondary, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Emergency: $emergencyPhone', style: const TextStyle(color: Colors.white, fontSize: 14))),
              ]),
            ],

            if (canManage) ...[
              const SizedBox(height: 20),
              const Divider(color: AppColors.navyBorder),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.shield_outlined, size: 18),
                  label: const Text('Make Guide'),
                  onPressed: () => _confirmTransfer(sheetContext, uid, name),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.person_remove_outlined, size: 18, color: AppColors.sos),
                  label: const Text('Remove from Group', style: TextStyle(color: AppColors.sos)),
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.sos, width: 1.5)),
                  onPressed: () => _confirmRemove(sheetContext, uid, name),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('Group Members')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : _groupId == null
              // Previously this fell into the "loading" branch forever,
              // since _groupId being null was never distinguished from
              // "still loading" — a removed tourist opening this screen
              // saw an infinite spinner instead of an explanation.
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      "You're not currently in a group.",
                      style: TextStyle(color: AppColors.textOnNavySecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : StreamBuilder<QuerySnapshot>(
              stream: _locationService.groupLocationsStream(_groupId!),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                if (docs.isEmpty) return const Center(child: Text('No members yet.', style: TextStyle(color: AppColors.textOnNavySecondary)));

                final now = DateTime.now();

                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data() as Map<String, dynamic>;
                    final uid = doc.id;
                    final role = data['role'] as String? ?? 'tourist';
                    final ts = data['timestamp'] as Timestamp?;
                    final isActive = ts != null && now.difference(ts.toDate()).inMinutes < 10;
                    final battery = data['batteryLevel'] as int? ?? -1;
                    final lat = data['lat'] as double?;
                    final lng = data['lng'] as double?;
                    final isSelf = uid == _currentUid;

                    return FutureBuilder<AppUser?>(
                      future: _authService.getUserProfile(uid),
                      builder: (context, userSnap) {
                        final name = userSnap.data?.name ?? '...';
                        final phone = userSnap.data?.phone ?? '';

                        return GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showMemberDetails(
                            uid: uid,
                            name: name,
                            role: role,
                            phone: phone,
                            battery: battery,
                            isActive: isActive,
                            lat: lat,
                            lng: lng,
                          ),
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: AppColors.navyCard, borderRadius: BorderRadius.circular(14)),
                            child: Row(children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundColor: AppColors.navy,
                                child: Text(
                                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Text(name, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                                      if (role == 'guide') ...[
                                        const SizedBox(width: 6),
                                        const Icon(Icons.shield, color: AppColors.gold, size: 14),
                                      ],
                                    ]),
                                    const SizedBox(height: 2),
                                    Row(children: [
                                      Container(width: 7, height: 7, decoration: BoxDecoration(color: isActive ? AppColors.success : AppColors.inactive, shape: BoxShape.circle)),
                                      const SizedBox(width: 5),
                                      Text(isActive ? 'Active' : 'Inactive', style: TextStyle(fontSize: 11, color: isActive ? AppColors.success : AppColors.textOnNavyMuted)),
                                      if (battery >= 0 && battery <= 15) ...[
                                        const SizedBox(width: 8),
                                        const Icon(Icons.battery_alert, color: AppColors.medical, size: 13),
                                      ],
                                    ]),
                                  ],
                                ),
                              ),
                              if (phone.isNotEmpty)
                                IconButton(icon: const Icon(Icons.phone, color: AppColors.gold), onPressed: () => _callNumber(phone)),
                              const Icon(Icons.chevron_right, color: AppColors.textOnNavyMuted),
                            ]),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
    );
  }
}