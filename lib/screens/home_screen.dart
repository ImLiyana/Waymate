import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'package:waymate/core/theme.dart';
import 'package:waymate/core/widgets.dart';
import 'package:waymate/services/auth_service.dart';
import 'package:waymate/services/location_service.dart';
import 'package:waymate/services/sos_service.dart';
import 'package:waymate/services/notification_service.dart';
import 'package:waymate/models/user_model.dart';
import 'package:waymate/screens/profile_screen.dart';
import 'package:waymate/screens/members_screen.dart';
import 'package:waymate/screens/member_detail_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _authService = AuthService();
  final _locationService = LocationService();
  final _sosService = SosService();

  AppUser? _user;
  bool _loading = true;
  LatLng? _currentLatLng;
  String? _locationError;
  final Set<String> _notifiedAlertIds = {};

  // Real address text for the tourist's own "Your location" banner.
  // Refreshed periodically (not on every GPS tick) since reverse
  // geocoding is a network call — hammering it on every 15m movement
  // would be wasteful and risks hitting the free service's rate limit.
  String? _myAddress;
  Timer? _addressRefreshTimer;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _addressRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadProfile();
    _startLocation();
  }

  Future<void> _loadProfile() async {
    final uid = _authService.currentUser?.uid;
    if (uid != null) {
      final profile = await _authService.getUserProfile(uid);
      if (mounted) setState(() { _user = profile; _loading = false; });
    }
  }

  Future<void> _refreshMyAddress() async {
    if (_currentLatLng == null) return;
    final address = await _locationService.reverseGeocode(
      _currentLatLng!.latitude,
      _currentLatLng!.longitude,
    );
    if (mounted && address != null) {
      setState(() => _myAddress = address);
    }
  }

  Future<void> _startLocation() async {
    final granted = await _locationService.ensurePermission();
    if (!granted) {
      setState(() => _locationError = 'Location permission is needed to show your position on the map.');
      return;
    }

    final role = _user?.role ?? 'tourist';

    try {
      // Fast, lower-accuracy fix first so the screen doesn't sit blocked
      // on a slow high-accuracy GPS lock. The continuous stream below
      // still uses high accuracy for every update after this.
      final position = await _locationService
          .getCurrentPosition(accuracy: LocationAccuracy.medium)
          .timeout(const Duration(seconds: 8));
      if (mounted) {
        setState(() => _currentLatLng = LatLng(position.latitude, position.longitude));
      }

      // Push the very first fix immediately — don't wait for 15m of
      // movement, otherwise a stationary tourist (or emulator/web tab)
      // never shows up in the guide's dashboard at all. Both tourists
      // AND guides push their location — the guide's own position is
      // shown too, marked distinctly, so tourists can see where to go.
      final uid = _authService.currentUser?.uid;
      if (uid != null) {
        _locationService.pushLocation(uid: uid, groupId: _user?.groupId, position: position, role: role);
      }

      // Look up a real address once we have a position, then keep it
      // fresh every 60 seconds — frequent enough to stay accurate as
      // someone walks around, infrequent enough not to hammer the free
      // geocoding service.
      _refreshMyAddress();
      _addressRefreshTimer?.cancel();
      _addressRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) => _refreshMyAddress());

      _locationService.positionStream.listen((pos) {
        if (mounted) {
          setState(() => _currentLatLng = LatLng(pos.latitude, pos.longitude));
        }
        final uid = _authService.currentUser?.uid;
        if (uid != null) {
          _locationService.pushLocation(uid: uid, groupId: _user?.groupId, position: pos, role: role);
        }
      });
    } catch (e) {
      setState(() => _locationError = 'Could not get your location.');
    }
  }

  Future<void> _handleSosTriggered() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return;

    try {
      final position = _currentLatLng != null
          ? Position(
              latitude: _currentLatLng!.latitude,
              longitude: _currentLatLng!.longitude,
              timestamp: DateTime.now(),
              accuracy: 0, altitude: 0, altitudeAccuracy: 0,
              heading: 0, headingAccuracy: 0, speed: 0, speedAccuracy: 0,
            )
          : await _locationService.getCurrentPosition();

      final alertId = await _sosService.triggerSos(
        uid: uid,
        touristName: _user?.name ?? 'A tourist',
        groupId: _user?.groupId,
        position: position,
        emergencyContactPhone: _user?.emergencyContactPhone,
      );

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => _SosConfirmationDialog(
            onCancelPressed: () async {
              await _sosService.resolveAlert(alertId);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send SOS alert: $e')),
        );
      }
    }
  }

  /// Shows a small bottom sheet identifying whoever's marker was tapped —
  /// name, active/inactive status, and the exact coordinates.
  void _showLocationInfo({
    required String name,
    required bool isGuide,
    required LatLng point,
    DateTime? lastUpdate,
  }) {
    String subtitle;
    if (lastUpdate == null) {
      subtitle = 'Location status unknown';
    } else {
      final minutesAgo = DateTime.now().difference(lastUpdate).inMinutes;
      subtitle = minutesAgo < 1
          ? 'Updated just now'
          : minutesAgo < 10
              ? 'Updated $minutesAgo min ago — Active'
              : 'Last seen $minutesAgo min ago — Inactive';
    }

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      isGuide ? Icons.shield : Icons.person_pin_circle,
                      color: isGuide ? Colors.amber.shade800 : AppColors.primary,
                      size: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        isGuide ? '$name (Guide)' : name,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(subtitle, style: AppTextStyles.body),
                const SizedBox(height: 16),
                FutureBuilder<String?>(
                  future: _locationService.reverseGeocode(point.latitude, point.longitude),
                  builder: (context, snap) {
                    final address = snap.data;
                    final loading = snap.connectionState == ConnectionState.waiting;

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            loading ? Icons.hourglass_empty : Icons.place_outlined,
                            size: 18,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loading
                                      ? 'Finding address...'
                                      : (address ?? 'Address unavailable'),
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
                                  style: TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.grey.shade600),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const _BrandedLoadingScreen(message: 'Loading your profile...');
    }

    final isGuide = _user?.role == 'guide';

    return AppScaffoldWithSos(
      onSosTriggered: _handleSosTriggered,
      drawer: _user == null ? null : _AppDrawer(user: _user!, onLogout: () => _authService.logout()),
      appBar: AppBar(
        title: const Text('WayMate'),
        backgroundColor: AppColors.primary,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _authService.logout(),
          ),
        ],
      ),
      body: Container(
        // A soft, light-blue wash behind the whole screen — glassy cards
        // sit on top of this instead of a flat white background. Kept
        // deliberately gentle (not the strong navy auth gradient) so map
        // content and text stay easy to read.
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFE0F2F1), Color(0xFFB2DFDB)],
          ),
        ),
        child: isGuide
            ? SingleChildScrollView(
                // The guide's screen can have any number of alert cards
                // stacked above the map — rather than squeezing the map
                // into whatever space is left (which caused it to
                // disappear entirely with 2+ alerts), the WHOLE screen
                // scrolls now, and the map keeps a solid fixed height so
                // scrolling down always reveals it in full.
                child: Column(
                  children: [
                    ResponsiveCenter(
                      maxWidth: 600,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: GlassCard(
                          child: Column(
                            children: [
                              Text('Your Group Code', style: AppTextStyles.bodyLarge),
                              const SizedBox(height: 8),
                              Text(
                                _user?.groupId ?? '—',
                                style: TextStyle(
                                  fontSize: AppResponsive.font(context, 32), fontWeight: FontWeight.bold,
                                  letterSpacing: 4, color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ResponsiveCenter(maxWidth: 600, child: _buildActiveAlertsList()),
                    const SizedBox(height: 16),
                    ResponsiveCenter(
                      maxWidth: 700,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: SizedBox(
                            height: 480,
                            child: _buildGroupMonitorMap(),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 150),
                  ],
                ),
              )
            : Column(
                children: [
                  ResponsiveCenter(maxWidth: 600, child: _buildOwnActiveAlertBanner()),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                      child: _buildOwnMap(),
                    ),
                  ),
                  const SizedBox(height: 130),
                ],
              ),
      ),
    );
  }

  /// Tourist-only: if THEY currently have an active SOS alert (e.g. after
  /// pressing "Return to App" instead of cancelling), show a persistent
  /// banner with a way to cancel it — previously the only way to cancel
  /// was the one moment right after triggering, on the confirmation
  /// dialog itself.
  Widget _buildOwnActiveAlertBanner() {
    final uid = _authService.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: _sosService.myActiveAlertStream(uid),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final alertId = snapshot.data!.docs.first.id;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.sos,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_rounded, color: Colors.white, size: 28),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Your SOS alert is active',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Cancel your alert?'),
                        content: const Text('Only do this if you no longer need help.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Keep Active'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(true),
                            child: const Text('Cancel Alert'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      await _sosService.resolveAlert(alertId);
                    }
                  },
                  style: TextButton.styleFrom(backgroundColor: Colors.white.withOpacity(0.2)),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Tourist's own map: shows their own position, their guide, AND every
  /// other tourist in the group (previously only the guide showed up
  /// here). Also shows their own coordinates written out plainly above
  /// the map, not just on tap. Tapping any marker shows who it is.
  Widget _buildOwnMap() {
    if (_locationError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_locationError!, style: AppTextStyles.body, textAlign: TextAlign.center),
        ),
      );
    }
    if (_currentLatLng == null) {
      return const Center(
        child: _LoadingIndicator(message: 'Getting your location...'),
      );
    }

    final myUid = _authService.currentUser?.uid;
    final ownMarker = Marker(
      point: _currentLatLng!,
      width: 50,
      height: 50,
      child: GestureDetector(
        onTap: () => _showLocationInfo(
          name: _user?.name ?? 'You',
          isGuide: false,
          point: _currentLatLng!,
          lastUpdate: DateTime.now(),
        ),
        child: const Icon(Icons.location_on, color: AppColors.sos, size: 44),
      ),
    );

    final coordsHeader = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      color: Colors.white.withOpacity(0.9),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.my_location, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _myAddress ??
                  'Your location: ${_currentLatLng!.latitude.toStringAsFixed(5)}, ${_currentLatLng!.longitude.toStringAsFixed(5)}',
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppResponsive.font(context, 15),
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );

    // No group joined — just show own position.
    final groupId = _user?.groupId;
    if (groupId == null) {
      return Column(
        children: [
          coordsHeader,
          Expanded(
            child: FlutterMap(
              options: MapOptions(initialCenter: _currentLatLng!, initialZoom: 17),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.waymate',
                ),
                MarkerLayer(markers: [ownMarker]),
              ],
            ),
          ),
        ],
      );
    }

    // In a group — show the guide AND every other tourist too, not just
    // the guide.
    return StreamBuilder<QuerySnapshot>(
      stream: _locationService.groupLocationsStream(groupId),
      builder: (context, snapshot) {
        final markers = <Marker>[ownMarker];

        if (snapshot.hasData) {
          for (final doc in snapshot.data!.docs) {
            if (doc.id == myUid) continue; // already plotted as ownMarker
            final data = doc.data() as Map<String, dynamic>;
            final lat = data['lat'] as double?;
            final lng = data['lng'] as double?;
            final ts = data['timestamp'] as Timestamp?;
            if (lat == null || lng == null) continue;
            final point = LatLng(lat, lng);

            if (data['role'] == 'guide') {
              markers.add(_guideMarker(
                point: point,
                onTap: () => _showLocationInfo(
                  name: 'Your Guide',
                  isGuide: true,
                  point: point,
                  lastUpdate: ts?.toDate(),
                ),
              ));
            } else {
              markers.add(
                Marker(
                  point: point,
                  width: 44,
                  height: 44,
                  child: GestureDetector(
                    onTap: () => _showLocationInfo(
                      name: 'Fellow tourist',
                      isGuide: false,
                      point: point,
                      lastUpdate: ts?.toDate(),
                    ),
                    child: const Icon(Icons.person_pin_circle, color: AppColors.primary, size: 40),
                  ),
                ),
              );
            }
          }
        }

        return Column(
          children: [
            coordsHeader,
            Expanded(
              child: FlutterMap(
                options: MapOptions(initialCenter: _currentLatLng!, initialZoom: 17),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.waymate',
                  ),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// A gold shield marker with a "GUIDE" label above it, so it's always
  /// visually distinct from tourist pins. Tappable to show who it is.
  Marker _guideMarker({required LatLng point, required VoidCallback onTap}) {
    return Marker(
      point: point,
      width: 70,
      height: 66,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.amber.shade800,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'GUIDE',
                style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ),
            const SizedBox(height: 2),
            Icon(Icons.shield, color: Colors.amber.shade800, size: 36),
          ],
        ),
      ),
    );
  }

  /// Guide's view: every tourist plotted on one map, plus a scrollable
  /// status list showing who's active/inactive. The guide's own
  /// location is shown on the map too (marked distinctly) but is
  /// excluded from the tourist status list below. Tapping any marker
  /// identifies who it belongs to.
  Widget _buildGroupMonitorMap() {
    final groupId = _user?.groupId;
    if (groupId == null) {
      return const Center(child: Text('No group yet.'));
    }

    return StreamBuilder<QuerySnapshot>(
      stream: _locationService.groupLocationsStream(groupId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: _LoadingIndicator(message: 'Loading your group...'),
          );
        }

        final allDocs = snapshot.data!.docs;
        // Tourist docs only — used for the status chip list below.
        final touristDocs = allDocs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return data['role'] != 'guide';
        }).toList();

        if (allDocs.isEmpty) {
          return const Center(child: Text('No members are sharing location yet.'));
        }

        return _GroupMap(
          docs: allDocs,
          touristDocs: touristDocs,
          authService: _authService,
          guideMarkerBuilder: _guideMarker,
          onShowInfo: _showLocationInfo,
        );
      },
    );
  }

  Widget _buildActiveAlertsList() {
    final groupId = _user?.groupId;
    if (groupId == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('sos_alerts')
          .where('groupId', isEqualTo: groupId)
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final alerts = snapshot.data!.docs;

        for (final doc in alerts) {
          if (!_notifiedAlertIds.contains(doc.id)) {
            _notifiedAlertIds.add(doc.id);
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              final uid = doc['uid'] as String?;
              String touristName = 'A tourist';
              if (uid != null) {
                final profile = await _authService.getUserProfile(uid);
                if (profile != null) touristName = profile.name;
              }
              NotificationService.showSosAlert(touristName: touristName);
            });
          }
        }

        return Container(
          constraints: const BoxConstraints(maxHeight: 200),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView.builder(
            shrinkWrap: true,
            physics: alerts.length > 1 ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
            itemCount: alerts.length,
            itemBuilder: (context, index) {
              final doc = alerts[index];
              final uid = doc['uid'] as String?;

              return FutureBuilder<AppUser?>(
                future: uid != null ? _authService.getUserProfile(uid) : null,
                builder: (context, userSnap) {
                  final profile = userSnap.data;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.sos,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.warning_rounded, color: Colors.white, size: 32),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                '${profile?.name ?? "A tourist"} needs help!',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _AlertActionButton(
                                icon: Icons.call,
                                label: 'Call',
                                onTap: profile == null || profile.phone.isEmpty
                                    ? null
                                    : () => launchUrl(Uri(scheme: 'tel', path: profile.phone)),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _AlertActionButton(
                                icon: Icons.map_outlined,
                                label: 'Locate',
                                onTap: profile == null
                                    ? null
                                    : () => Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => MemberDetailScreen(member: profile)),
                                        ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _AlertActionButton(
                                icon: Icons.check_circle_outline,
                                label: 'Resolve',
                                onTap: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Mark as resolved?'),
                                      content: const Text('Confirm this emergency has been handled.'),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.of(context).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.of(context).pop(true),
                                          child: const Text('Resolve'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed == true) {
                                    await _sosService.resolveAlert(doc.id);
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}

/// Extracted so each tourist name can be looked up via FutureBuilder and
/// reused for both the status chips and the tappable map markers,
/// without re-fetching per rebuild any more than necessary.
class _GroupMap extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final List<QueryDocumentSnapshot> touristDocs;
  final AuthService authService;
  final Marker Function({required LatLng point, required VoidCallback onTap}) guideMarkerBuilder;
  final void Function({
    required String name,
    required bool isGuide,
    required LatLng point,
    DateTime? lastUpdate,
  }) onShowInfo;

  const _GroupMap({
    required this.docs,
    required this.touristDocs,
    required this.authService,
    required this.guideMarkerBuilder,
    required this.onShowInfo,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    return FutureBuilder<Map<String, AppUser?>>(
      future: _loadNames(),
      builder: (context, namesSnap) {
        final names = namesSnap.data ?? {};
        final markers = <Marker>[];

        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final lat = data['lat'] as double?;
          final lng = data['lng'] as double?;
          if (lat == null || lng == null) continue;
          final point = LatLng(lat, lng);
          final ts = data['timestamp'] as Timestamp?;
          final name = names[doc.id]?.name ?? '...';

          if (data['role'] == 'guide') {
            markers.add(guideMarkerBuilder(
              point: point,
              onTap: () => onShowInfo(name: name, isGuide: true, point: point, lastUpdate: ts?.toDate()),
            ));
          } else {
            markers.add(
              Marker(
                point: point,
                width: 44,
                height: 44,
                child: GestureDetector(
                  onTap: () => onShowInfo(name: name, isGuide: false, point: point, lastUpdate: ts?.toDate()),
                  child: const Icon(Icons.person_pin_circle, color: AppColors.primary, size: 40),
                ),
              ),
            );
          }
        }

        final center = markers.isNotEmpty ? markers.first.point : const LatLng(0, 0);

        return Column(
          children: [
            SizedBox(
              height: 130,
              child: touristDocs.isEmpty
                  ? const Center(child: Text('No tourists are sharing location yet.'))
                  : ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: touristDocs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final ts = data['timestamp'] as Timestamp?;
                        final isActive = ts != null && now.difference(ts.toDate()).inMinutes < 10;
                        final name = names[doc.id]?.name ?? '...';

                        return Container(
                          width: 110,
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isActive ? AppColors.success : Colors.grey.shade400,
                              width: 2,
                            ),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                isActive ? Icons.check_circle : Icons.circle_outlined,
                                color: isActive ? AppColors.success : Colors.grey,
                                size: 22,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              Text(
                                isActive ? 'Active' : 'Inactive',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isActive ? AppColors.success : Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
            ),
            Expanded(
              child: FlutterMap(
                options: MapOptions(initialCenter: center, initialZoom: 14),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.example.waymate',
                  ),
                  MarkerLayer(markers: markers),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Future<Map<String, AppUser?>> _loadNames() async {
    final result = <String, AppUser?>{};
    for (final doc in docs) {
      result[doc.id] = await authService.getUserProfile(doc.id);
    }
    return result;
  }
}

class _SosConfirmationDialog extends StatelessWidget {
  final VoidCallback onCancelPressed;
  const _SosConfirmationDialog({required this.onCancelPressed});

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: AppColors.sos,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 80),
              const SizedBox(height: 24),
              const Text(
                'Help is on the way',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Your guide has been notified of your location.',
                style: TextStyle(fontSize: 18, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.sos,
                  ),
                  child: const Text(
                    'Return to App',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: OutlinedButton(
                  onPressed: onCancelPressed,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white, width: 2),
                  ),
                  child: const Text(
                    'This was a mistake — Cancel Alert',
                    style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small inline spinner + message, used inside a screen that's otherwise
/// already loaded (e.g. waiting for a GPS fix or a Firestore query) —
/// gives context instead of a bare, unexplained spinner.
class _LoadingIndicator extends StatelessWidget {
  final String message;
  const _LoadingIndicator({required this.message});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 16),
        Text(message, style: AppTextStyles.body, textAlign: TextAlign.center),
      ],
    );
  }
}

/// Full-screen branded loading state — shown briefly on first app load
/// while the user's profile is being fetched. Uses the same gradient as
/// the auth screens so the transition into the app doesn't feel like a
/// jarring drop to a blank white page.
class _BrandedLoadingScreen extends StatelessWidget {
  final String message;
  const _BrandedLoadingScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.shield_moon, color: Colors.white, size: 56),
              const SizedBox(height: 16),
              const Text(
                'WayMate',
                style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 24),
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              Text(message, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pill-shaped action button used inside an active SOS alert card
/// (Call / Locate / Resolve).
class _AlertActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  const _AlertActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withOpacity(0.18),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}

/// App-wide navigation drawer: profile for everyone, and a group
/// member directory for guides.
class _AppDrawer extends StatelessWidget {
  final AppUser user;
  final VoidCallback onLogout;

  const _AppDrawer({required this.user, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final isGuide = user.role == 'guide';

    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: AppColors.primary),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white,
                    child: Text(
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 22),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          user.name,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          isGuide ? 'Guide' : 'Tourist',
                          style: const TextStyle(color: Colors.white70, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('My Profile'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ProfileScreen(user: user)),
                );
              },
            ),
            if (isGuide && user.groupId != null)
              ListTile(
                leading: const Icon(Icons.groups_outlined),
                title: const Text('Group Members'),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => MembersScreen(groupId: user.groupId!)),
                  );
                },
              ),
            const Spacer(),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.sos),
              title: const Text('Log Out', style: TextStyle(color: AppColors.sos)),
              onTap: onLogout,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}