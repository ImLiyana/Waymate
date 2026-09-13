import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../models/user_model.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authService = AuthService();
  final _locationService = LocationService();

  AppUser? _user;
  bool _loading = true;
  String? _nearestName;
  double? _nearestDistanceMeters;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;

    final profile = await _authService.getUserProfile(uid);
    if (mounted) setState(() { _user = profile; _loading = false; });

    if (profile?.groupId != null) {
      await _findNearestTourist(uid, profile!.groupId!);
    }
  }

  Future<void> _findNearestTourist(String myUid, String groupId) async {
    try {
      final myPosition = await _locationService.getCurrentPosition();
      final snapshot = await _locationService.groupLocationsStream(groupId).first;

      String? nearestUid;
      double nearestDistance = double.infinity;

      for (final doc in snapshot.docs) {
        if (doc.id == myUid) continue;
        final data = doc.data() as Map<String, dynamic>;
        if (data['role'] != 'tourist') continue;
        final lat = data['lat'] as double?;
        final lng = data['lng'] as double?;
        if (lat == null || lng == null) continue;

        final distance = _locationService.distanceBetween(myPosition.latitude, myPosition.longitude, lat, lng);
        if (distance < nearestDistance) {
          nearestDistance = distance;
          nearestUid = doc.id;
        }
      }

      if (nearestUid != null && mounted) {
        final nearestProfile = await _authService.getUserProfile(nearestUid);
        setState(() {
          _nearestName = nearestProfile?.name ?? 'A fellow tourist';
          _nearestDistanceMeters = nearestDistance;
        });
      }
    } catch (_) {
      // Silently skip — this is a nice-to-have, not critical info
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _user == null) {
      return const Scaffold(backgroundColor: AppColors.navy, body: Center(child: CircularProgressIndicator()));
    }

    final email = _authService.currentUser?.email ?? '—';
    final user = _user!;

    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('My Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: AppColors.navyCard,
              child: Text(
                user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                style: const TextStyle(color: AppColors.gold, fontSize: 32, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(child: Text(user.name, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white))),
          const SizedBox(height: 6),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: AppColors.navyCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: AppColors.gold)),
              child: Text(user.role == 'guide' ? 'Guide' : 'Tourist', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.gold, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 28),

          _InfoTile(icon: Icons.phone_outlined, label: 'Phone', value: user.phone),
          _InfoTile(icon: Icons.email_outlined, label: 'Email', value: email),
          if (user.emergencyContactPhone != null && user.emergencyContactPhone!.isNotEmpty)
            _InfoTile(icon: Icons.family_restroom, label: 'Emergency Contact', value: user.emergencyContactPhone!),
          if (user.groupId != null)
            _InfoTile(icon: Icons.groups_outlined, label: user.role == 'guide' ? 'Your Group Code' : 'Group Code', value: user.groupId!),

          if (_nearestName != null) ...[
            const SizedBox(height: 8),
            NavyCard(
              child: Row(children: [
                const Icon(Icons.social_distance_outlined, color: AppColors.gold),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Nearest Tourist', style: AppTextStyles.label),
                      const SizedBox(height: 2),
                      Text(
                        '$_nearestName · ${(_nearestDistanceMeters! / 1000).toStringAsFixed(1)} km away',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ],
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
      decoration: BoxDecoration(color: AppColors.navyCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.navyBorder)),
      child: Row(children: [
        Icon(icon, color: AppColors.gold),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textOnNavySecondary)),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
            ],
          ),
        ),
      ]),
    );
  }
}