import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:waymate/core/theme.dart';
import 'package:waymate/services/location_service.dart';
import 'package:waymate/models/user_model.dart';

class MemberDetailScreen extends StatelessWidget {
  final AppUser member;
  const MemberDetailScreen({required this.member, super.key});

  Future<void> _call(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      await launchUrl(uri);
    } catch (_) {
      // Ignore — not every environment (e.g. a desktop browser) can
      // place a call; the number is still visible on screen to dial
      // manually.
    }
  }

  @override
  Widget build(BuildContext context) {
    final locationService = LocationService();

    return Scaffold(
      appBar: AppBar(title: Text(member.name)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _ContactButton(
                    icon: Icons.call,
                    label: 'Call ${member.name}',
                    onTap: () => _call(member.phone),
                  ),
                ),
                if (member.emergencyContactPhone != null && member.emergencyContactPhone!.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ContactButton(
                      icon: Icons.family_restroom,
                      label: 'Emergency Contact',
                      onTap: () => _call(member.emergencyContactPhone!),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<DocumentSnapshot>(
              stream: locationService.singleUserLocationStream(member.uid),
              builder: (context, snapshot) {
                if (!snapshot.hasData || !snapshot.data!.exists) {
                  return const Center(child: Text('No location data yet.'));
                }
                final data = snapshot.data!.data() as Map<String, dynamic>?;
                final lat = data?['lat'] as double?;
                final lng = data?['lng'] as double?;
                final ts = data?['timestamp'] as Timestamp?;

                if (lat == null || lng == null) {
                  return const Center(child: Text('No location data yet.'));
                }

                final point = LatLng(lat, lng);
                final minutesAgo = ts != null ? DateTime.now().difference(ts.toDate()).inMinutes : null;
                final isActive = minutesAgo != null && minutesAgo < 10;

                return Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: isActive ? AppColors.success.withOpacity(0.1) : Colors.grey.shade100,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isActive ? Icons.check_circle : Icons.circle_outlined,
                            color: isActive ? AppColors.success : Colors.grey,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            minutesAgo == null
                                ? 'Status unknown'
                                : minutesAgo < 1
                                    ? 'Updated just now'
                                    : isActive
                                        ? 'Active — updated $minutesAgo min ago'
                                        : 'Inactive — last seen $minutesAgo min ago',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isActive ? AppColors.success : Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: FlutterMap(
                        options: MapOptions(initialCenter: point, initialZoom: 16),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.example.waymate',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: point,
                                width: 44,
                                height: 44,
                                child: const Icon(Icons.person_pin_circle, color: AppColors.primary, size: 40),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ContactButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label, overflow: TextOverflow.ellipsis),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 14),
        foregroundColor: AppColors.primary,
        side: const BorderSide(color: AppColors.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}