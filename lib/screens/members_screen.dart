
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../core/theme.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../models/user_model.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final _authService = AuthService();
  final _locationService = LocationService();
  String? _groupId;

  @override
  void initState() {
    super.initState();
    _loadGroupId();
  }

  Future<void> _loadGroupId() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;
    final profile = await _authService.getUserProfile(uid);
    if (mounted) setState(() => _groupId = profile?.groupId);
  }

  Future<void> _callNumber(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('Group Members')),
      body: _groupId == null
          ? const Center(child: CircularProgressIndicator())
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

                    return FutureBuilder<AppUser?>(
                      future: _authService.getUserProfile(uid),
                      builder: (context, userSnap) {
                        final name = userSnap.data?.name ?? '...';
                        final phone = userSnap.data?.phone ?? '';

                        return Container(
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
                          ]),
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