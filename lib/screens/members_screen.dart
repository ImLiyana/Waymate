import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:waymate/core/theme.dart';
import 'package:waymate/services/auth_service.dart';
import 'package:waymate/services/location_service.dart';
import 'package:waymate/models/user_model.dart';
import 'package:waymate/screens/member_detail_screen.dart';

class MembersScreen extends StatelessWidget {
  final String groupId;
  const MembersScreen({required this.groupId, super.key});

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final locationService = LocationService();

    return Scaffold(
      appBar: AppBar(title: const Text('Group Members')),
      body: StreamBuilder<QuerySnapshot>(
        stream: locationService.groupLocationsStream(groupId),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final touristDocs = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>;
            return data['role'] != 'guide';
          }).toList();

          if (touristDocs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No tourists have joined this group yet.',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.body,
                ),
              ),
            );
          }

          final now = DateTime.now();

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: touristDocs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = touristDocs[index];
              final data = doc.data() as Map<String, dynamic>;
              final uid = doc.id;
              final ts = data['timestamp'] as Timestamp?;
              final isActive = ts != null && now.difference(ts.toDate()).inMinutes < 10;

              return FutureBuilder<AppUser?>(
                future: authService.getUserProfile(uid),
                builder: (context, userSnap) {
                  final user = userSnap.data;
                  final name = user?.name ?? 'Loading...';
                  final phone = user?.phone ?? '';

                  return Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    elevation: 1,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: user == null
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => MemberDetailScreen(member: user)),
                              );
                            },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: AppColors.primary.withOpacity(0.15),
                              child: Text(
                                name.isNotEmpty ? name[0].toUpperCase() : '?',
                                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                  if (phone.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(phone, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
                                  ],
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Icon(
                                  isActive ? Icons.check_circle : Icons.circle_outlined,
                                  color: isActive ? AppColors.success : Colors.grey,
                                  size: 20,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  isActive ? 'Active' : 'Inactive',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isActive ? AppColors.success : Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                            const Icon(Icons.chevron_right, color: Colors.grey),
                          ],
                        ),
                      ),
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