import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/sos_service.dart';
import '../services/notification_service.dart';
import '../models/user_model.dart';
import 'app_drawer.dart';
import 'ai_assistant_screen.dart';
import 'qr_display_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authService = AuthService();
  final _locationService = LocationService();
  final _sosService = SosService();
  final MapController _mapController = MapController();

  AppUser? _user;
  bool _loading = true;
  LatLng? _currentLatLng;
  String? _locationError;
  bool _showListView = false;
  List<LatLng>? _routePoints;
  bool _isLoadingRoute = false;
  final Set<String> _notifiedAlertIds = {};

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _startLocation();
  }

  Future<void> _loadProfile() async {
    final uid = _authService.currentUser?.uid;
    if (uid != null) {
      final profile = await _authService.getUserProfile(uid);
      if (mounted) setState(() { _user = profile; _loading = false; });
    }
  }

  Future<void> _startLocation() async {
    final granted = await _locationService.ensurePermission();
    if (!granted) {
      setState(() => _locationError = 'Location permission is needed to show your position on the map.');
      return;
    }

    try {
      final position = await _locationService.getCurrentPosition().timeout(
        const Duration(seconds: 10),
        onTimeout: () async {
          debugPrint('getCurrentPosition timed out after 10s, trying last known position');
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) return last;
          throw Exception('GPS timed out and no last known position is available');
        },
      );
      if (mounted) setState(() => _currentLatLng = LatLng(position.latitude, position.longitude));
      await _pushAndCheck(position);

      _locationService.positionStream.listen((pos) {
        if (mounted) setState(() => _currentLatLng = LatLng(pos.latitude, pos.longitude));
        _pushAndCheck(pos);
      });
    } catch (e) {
      debugPrint('_startLocation failed: $e');
      setState(() => _locationError = 'Could not get your location. Make sure GPS/location is turned on and try again.');
    }
  }

  Future<void> _pushAndCheck(Position pos) async {
    final uid = _authService.currentUser?.uid;
    if (uid == null || _user == null) return;

    try {
      await _locationService.pushLocation(
        uid: uid, groupId: _user!.groupId, role: _user!.role, position: pos,
      );
    } catch (e) {
      debugPrint('pushLocation failed for uid=$uid role=${_user!.role} groupId=${_user!.groupId}: $e');
      return; // don't proceed to battery check if the write failed
    }

    if (_user!.role == 'tourist') {
      final shouldAlert = await _locationService.checkLowBatteryOnce();
      if (shouldAlert) {
        await _sosService.sendLowBatteryAlert(
          uid: uid, touristName: _user!.name, groupId: _user!.groupId, position: pos,
        );
      }
    }
  }

  Future<void> _handleSos() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null || _currentLatLng == null) return;

    try {
      final position = Position(
        latitude: _currentLatLng!.latitude, longitude: _currentLatLng!.longitude,
        timestamp: DateTime.now(), accuracy: 0, altitude: 0, altitudeAccuracy: 0,
        heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
      );
      final alertId = await _sosService.triggerSos(
        uid: uid, touristName: _user?.name ?? 'A tourist',
        groupId: _user?.groupId, position: position,
        emergencyContactPhone: _user?.emergencyContactPhone,
      );
      if (mounted) {
        showDialog(
          context: context, barrierDismissible: false,
          builder: (context) => _AlertConfirmationDialog(
            color: AppColors.sos, title: 'Help is on the way',
            subtitle: 'Your guide, emergency contact, and nearest group member have been notified.',
            onCancel: () async { await _sosService.resolveAlert(alertId); if (context.mounted) Navigator.of(context).pop(); },
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send alert. Try again.')));
    }
  }

  Future<void> _handleMedicalAid() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null || _currentLatLng == null) return;

    try {
      final position = Position(
        latitude: _currentLatLng!.latitude, longitude: _currentLatLng!.longitude,
        timestamp: DateTime.now(), accuracy: 0, altitude: 0, altitudeAccuracy: 0,
        heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
      );
      final alertId = await _sosService.triggerMedicalAid(
        uid: uid, touristName: _user?.name ?? 'A tourist', groupId: _user?.groupId, position: position,
      );
      if (mounted) {
        showDialog(
          context: context, barrierDismissible: false,
          builder: (context) => _AlertConfirmationDialog(
            color: AppColors.medical, title: 'Help is being arranged',
            subtitle: 'Your guide and nearest group member have been notified.',
            onCancel: () async { await _sosService.resolveAlert(alertId); if (context.mounted) Navigator.of(context).pop(); },
          ),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send request. Try again.')));
    }
  }

  Future<void> _fetchRoute(LatLng from, LatLng to) async {
    setState(() => _isLoadingRoute = true);
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/foot/${from.longitude},${from.latitude};${to.longitude},${to.latitude}?overview=full&geometries=geojson',
      );
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final coords = data['routes'][0]['geometry']['coordinates'] as List;
        setState(() {
          _routePoints = coords.map((c) => LatLng(c[1] as double, c[0] as double)).toList();
        });
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Route service returned an error (${response.statusCode}). Try again shortly.')));
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not load route right now.')));
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  void _jumpToLocation(double lat, double lng) {
    if (_user?.role == 'guide' && _showListView) {
      setState(() => _showListView = false);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(LatLng(lat, lng), 16);
      } catch (_) {}
    });
  }

  Future<void> _showMarkerInfo(String uid, double lat, double lng, String role) async {
    final profile = await _authService.getUserProfile(uid);
    final address = await _locationService.getAddressFromCoordinates(lat, lng);
    double? distanceKm;
    if (_currentLatLng != null) {
      distanceKm = _locationService.distanceBetween(_currentLatLng!.latitude, _currentLatLng!.longitude, lat, lng) / 1000;
    }

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.navyCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(role == 'guide' ? Icons.shield_outlined : Icons.person_outline, color: AppColors.gold, size: 22),
              const SizedBox(width: 8),
              Text(profile?.name ?? 'Group member', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 4),
            Text(role == 'guide' ? 'Guide' : 'Tourist', style: const TextStyle(color: AppColors.textOnNavySecondary, fontSize: 12)),
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.location_on_outlined, color: AppColors.textOnNavySecondary, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(address, style: const TextStyle(color: Colors.white, fontSize: 14))),
            ]),
            if (distanceKm != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.social_distance_outlined, color: AppColors.textOnNavySecondary, size: 18),
                const SizedBox(width: 8),
                Text('${distanceKm.toStringAsFixed(1)} km away', style: const TextStyle(color: Colors.white, fontSize: 14)),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _user == null) {
      return const Scaffold(backgroundColor: AppColors.navy, body: Center(child: CircularProgressIndicator()));
    }

    final isGuide = _user!.role == 'guide';

    return AppScaffoldWithSos(
      title: 'WayMate',
      drawer: AppDrawer(user: _user!, onLogout: () => _authService.logout()),
      onSosTriggered: _handleSos,
      onMedicalAidTriggered: _handleMedicalAid,
      onAssistantTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AiAssistantScreen())),
      body: isGuide ? _buildGuideDashboard() : _buildTouristView(),
    );
  }

  Widget _buildTouristView() {
    if (_locationError != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_locationError!, style: AppTextStyles.body, textAlign: TextAlign.center)));
    }
    if (_currentLatLng == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _user!.groupId != null ? _locationService.groupLocationsStream(_user!.groupId!) : null,
      builder: (context, snapshot) {
        final markers = <Marker>[
          Marker(
            point: _currentLatLng!, width: 44, height: 44,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                final uid = _authService.currentUser?.uid;
                if (uid != null) {
                  _showMarkerInfo(uid, _currentLatLng!.latitude, _currentLatLng!.longitude, _user?.role ?? 'tourist');
                }
              },
              child: const _MyLocationDot(),
            ),
          ),
        ];

        LatLng? guideLatLng;

        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            if (doc.id == _authService.currentUser?.uid) continue;
            final data = doc.data() as Map<String, dynamic>;
            final lat = data['lat'] as double?;
            final lng = data['lng'] as double?;
            final role = data['role'] as String? ?? 'tourist';
            if (lat == null || lng == null) continue;

            if (role == 'guide') guideLatLng = LatLng(lat, lng);

            markers.add(Marker(
              point: LatLng(lat, lng), width: 44, height: 44,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _showMarkerInfo(doc.id, lat, lng, role),
                child: Icon(
                  role == 'guide' ? Icons.change_history : Icons.circle,
                  color: role == 'guide' ? AppColors.gold : AppColors.inactive,
                  size: role == 'guide' ? 28 : 18,
                ),
              ),
            ));
          }
        }

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(initialCenter: _currentLatLng!, initialZoom: 15),
              children: [
                TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.waymate'),
                if (_routePoints != null) PolylineLayer(polylines: [Polyline(points: _routePoints!, color: AppColors.gold, strokeWidth: 4)]),
                MarkerLayer(markers: markers),
              ],
            ),
            if (guideLatLng != null)
              Positioned(
                top: 12, right: 12,
                child: GestureDetector(
                  onTap: _isLoadingRoute ? null : () => _fetchRoute(_currentLatLng!, guideLatLng!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(10)),
                    child: _isLoadingRoute
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navyDark))
                        : const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.route, color: AppColors.navyDark, size: 16),
                            SizedBox(width: 6),
                            Text('Show Route', style: TextStyle(color: AppColors.navyDark, fontSize: 12, fontWeight: FontWeight.bold)),
                          ]),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildGuideDashboard() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: NavyCard(
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(_user!.groupId ?? '—', style: const TextStyle(color: AppColors.gold, fontSize: 20, fontWeight: FontWeight.bold, letterSpacing: 3)),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_user!.groupId != null) {
                      Navigator.of(context).push(MaterialPageRoute(builder: (_) => QrDisplayScreen(groupCode: _user!.groupId!)));
                    }
                  },
                  child: const Icon(Icons.qr_code, color: AppColors.gold),
                ),
              ]),
            ),
          ),
          _buildAlertsAndWarnings(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('MEMBERS', style: AppTextStyles.label),
              Row(children: [
                IconButton(icon: Icon(Icons.map_outlined, color: !_showListView ? AppColors.gold : AppColors.textOnNavyMuted), onPressed: () => setState(() => _showListView = false)),
                IconButton(icon: Icon(Icons.list, color: _showListView ? AppColors.gold : AppColors.textOnNavyMuted), onPressed: () => setState(() => _showListView = true)),
              ]),
            ]),
          ),
          SizedBox(
            height: 420,
            child: StreamBuilder<QuerySnapshot>(
              stream: _locationService.groupLocationsStream(_user!.groupId!),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snapshot.data!.docs;
                return _showListView ? _buildMemberList(docs) : _buildMemberMap(docs);
              },
            ),
          ),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Future<void> _showFullAlertAddress({required String? uid, required double lat, required double lng, required String label}) async {
    final profile = uid != null ? await _authService.getUserProfile(uid) : null;
    final address = await _locationService.getAddressFromCoordinates(lat, lng);

    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.navyCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${profile?.name ?? "A tourist"} $label', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            if (profile?.phone != null) ...[
              Row(children: [
                const Icon(Icons.phone_outlined, color: AppColors.textOnNavySecondary, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(profile!.phone, style: const TextStyle(color: Colors.white, fontSize: 15))),
                IconButton(
                  icon: const Icon(Icons.call, color: AppColors.gold, size: 20),
                  onPressed: () => launchUrl(Uri.parse('tel:${profile.phone}')),
                ),
              ]),
              const SizedBox(height: 8),
            ],
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.location_on_outlined, color: AppColors.textOnNavySecondary, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(address, style: const TextStyle(color: Colors.white, fontSize: 15))),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsAndWarnings() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sos_alerts')
          .where('groupId', isEqualTo: _user!.groupId)
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        final alerts = snapshot.data?.docs ?? [];
        if (alerts.isEmpty) return const SizedBox.shrink();

        for (final doc in alerts) {
          if (!_notifiedAlertIds.contains(doc.id)) {
            _notifiedAlertIds.add(doc.id);
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              final data = doc.data() as Map<String, dynamic>;
              final uid = data['uid'] as String?;
              final profile = uid != null ? await _authService.getUserProfile(uid) : null;
              NotificationService.showSosAlert(touristName: profile?.name ?? 'A tourist');
            });
          }
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('ALERTS & WARNINGS', style: AppTextStyles.label),
              const SizedBox(height: 8),
              ...alerts.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final type = data['type'] as String? ?? 'sos';
                final uid = data['uid'] as String?;
                final lat = data['lat'] as double;
                final lng = data['lng'] as double;

                final color = type == 'medical' ? AppColors.medical : (type == 'lowBattery' ? AppColors.goldDark : AppColors.sos);
                final icon = type == 'medical' ? Icons.medical_services_outlined : (type == 'lowBattery' ? Icons.battery_alert : Icons.warning_rounded);
                final label = type == 'medical' ? 'feels unwell' : (type == 'lowBattery' ? 'low battery — last known location' : 'needs help!');

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showFullAlertAddress(uid: uid, lat: lat, lng: lng, label: label),
                  child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    Icon(icon, color: Colors.white, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FutureBuilder<AppUser?>(
                            future: uid != null ? _authService.getUserProfile(uid) : null,
                            builder: (context, s) => Text('${s.data?.name ?? "A tourist"} $label', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                          ),
                          FutureBuilder<String>(
                            future: _locationService.getAddressFromCoordinates(lat, lng),
                            builder: (context, s) => Text(
                              s.data ?? 'Locating...',
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(icon: const Icon(Icons.my_location, color: Colors.white, size: 18), onPressed: () => _jumpToLocation(lat, lng)),
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (c) => AlertDialog(
                            backgroundColor: AppColors.navyCard,
                            title: const Text('Mark as resolved?', style: TextStyle(color: Colors.white)),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('Cancel')),
                              TextButton(onPressed: () => Navigator.of(c).pop(true), child: const Text('Resolve')),
                            ],
                          ),
                        );
                        if (confirmed == true) await _sosService.resolveAlert(doc.id);
                      },
                    ),
                  ]),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMemberMap(List<QueryDocumentSnapshot> docs) {
    final markers = <Marker>[];
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final lat = data['lat'] as double?;
      final lng = data['lng'] as double?;
      final role = data['role'] as String? ?? 'tourist';
      if (lat == null || lng == null) continue;
      markers.add(Marker(
        point: LatLng(lat, lng), width: 40, height: 40,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _showMarkerInfo(doc.id, lat, lng, role),
          child: Icon(
            role == 'guide' ? Icons.change_history : Icons.circle,
            color: role == 'guide' ? AppColors.gold : AppColors.success,
            size: role == 'guide' ? 26 : 16,
          ),
        ),
      ));
    }
    final center = markers.isNotEmpty ? markers.first.point : (_currentLatLng ?? const LatLng(0, 0));
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(initialCenter: center, initialZoom: 14),
      children: [
        TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.waymate'),
        MarkerLayer(markers: markers),
      ],
    );
  }

  Widget _buildMemberList(List<QueryDocumentSnapshot> docs) {
    final now = DateTime.now();
    LatLng? guideLatLng;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['role'] == 'guide') {
        final lat = data['lat'] as double?; final lng = data['lng'] as double?;
        if (lat != null && lng != null) guideLatLng = LatLng(lat, lng);
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final uid = doc.id;
        final lat = data['lat'] as double?;
        final lng = data['lng'] as double?;
        final role = data['role'] as String? ?? 'tourist';
        final battery = data['batteryLevel'] as int? ?? -1;
        final ts = data['timestamp'] as Timestamp?;
        final isActive = ts != null && now.difference(ts.toDate()).inMinutes < 10;

        bool isStraying = false;
        if (role == 'tourist' && guideLatLng != null && lat != null && lng != null) {
          isStraying = _locationService.isStrayingTooFar(touristLat: lat, touristLng: lng, guideLat: guideLatLng.latitude, guideLng: guideLatLng.longitude);
        }

        return FutureBuilder<AppUser?>(
          future: _authService.getUserProfile(uid),
          builder: (context, snap) {
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () { if (lat != null && lng != null) _jumpToLocation(lat, lng); },
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.navyCard, borderRadius: BorderRadius.circular(12),
                  border: isStraying ? Border.all(color: AppColors.goldDark, width: 1.5) : null,
                ),
                child: Row(children: [
                  CircleAvatar(radius: 18, backgroundColor: AppColors.navy, child: Text(
                    (snap.data?.name.isNotEmpty ?? false) ? snap.data!.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.bold),
                  )),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(snap.data?.name ?? '...', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                        if (role == 'guide') ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.shield, color: AppColors.gold, size: 13),
                        ],
                      ]),
                      Text(
                        isStraying ? 'Straying too far' : (isActive ? 'Active' : 'Inactive'),
                        style: TextStyle(fontSize: 11, color: isStraying ? AppColors.goldDark : (isActive ? AppColors.success : AppColors.textOnNavyMuted)),
                      ),
                    ]),
                  ),
                  if (battery >= 0 && battery <= 15) const Icon(Icons.battery_alert, color: AppColors.medical, size: 18),
                ]),
              ),
            );
          },
        );
      }).toList(),
    );
  }
}

/// Classic "GPS blue dot" look: a soft light-blue halo behind a solid
/// blue circle with a white ring border, like Google Maps' own location marker.
class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF3B82F6).withOpacity(0.20),
          ),
        ),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF3B82F6),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 1)),
            ],
          ),
        ),
      ],
    );
  }
}

class _AlertConfirmationDialog extends StatelessWidget {
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onCancel;

  const _AlertConfirmationDialog({required this.color, required this.title, required this.subtitle, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: color,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 72),
              const SizedBox(height: 20),
              Text(title, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white), textAlign: TextAlign.center),
              const SizedBox(height: 10),
              Text(subtitle, style: const TextStyle(fontSize: 15, color: Colors.white), textAlign: TextAlign.center),
              const SizedBox(height: 40),
              SizedBox(width: double.infinity, height: 54, child: ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Return to app'))),
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, height: 54, child: OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white, width: 2)),
                child: const Text('This was a mistake — Cancel', style: TextStyle(color: Colors.white)),
              )),
            ],
          ),
        ),
      ),
    );
  }
}