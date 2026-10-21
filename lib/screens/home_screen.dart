import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/auth_service.dart';
import '../services/location_service.dart';
import '../services/sos_service.dart';
import '../services/notification_service.dart';
import '../services/group_service.dart';
import '../services/background_location_service.dart';
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
  final _groupService = GroupService();

  final MapController _mapController = MapController();

  AppUser? _user;
  bool _loading = true;

  LatLng? _currentLatLng;
  String? _locationError;

  List<LatLng>? _routePoints;
  bool _isLoadingRoute = false;

  final Set<String> _notifiedAlertIds = {};

  StreamSubscription<AppUser?>? _profileSub;
  StreamSubscription<Position>? _positionSub;

  final Completer<void> _profileReady = Completer<void>();
  bool _backgroundServiceStarted = false;

  // flutter_map's `initialCenter` only applies on the VERY FIRST build
  // of the map widget. The guide map starts rendering as soon as the
  // Firestore stream fires (often before GPS/location data exists), so
  // without this flag the map silently locks onto the fallback
  // LatLng(11.2588, 75.7804) forever, even once real data arrives.
  bool _didCenterGuideMap = false;

  // ===============================================================
  // Cached group streams
  // ===============================================================
  String? _cachedGroupId;
  Stream<Map<String, dynamic>?>? _destinationStream;
  Stream<Map<String, dynamic>?>? _announcementStream;
  Stream<QuerySnapshot>? _locationsStream;
  Stream<QuerySnapshot>? _alertsStream;

  void _ensureGroupStreams(String groupId) {
    if (_cachedGroupId == groupId &&
        _destinationStream != null &&
        _locationsStream != null &&
        _alertsStream != null &&
        _announcementStream != null) {
      return;
    }
    debugPrint('Creating group streams for group: $groupId');
    _cachedGroupId = groupId;
    // New group → the map should re-center fresh for it.
    _didCenterGuideMap = false;
    _destinationStream = _groupService.destinationStream(groupId);
    _announcementStream = _groupService.announcementStream(groupId);
    _locationsStream = _locationService.groupLocationsStream(groupId);
    _alertsStream = FirebaseFirestore.instance
        .collection('sos_alerts')
        .where('groupId', isEqualTo: groupId)
        .where('status', isEqualTo: 'active')
        .snapshots();
  }

  // ===============================================================
  // Lifecycle
  // ===============================================================
  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _profileSub?.cancel();
    super.dispose();
  }

  // ===============================================================
  // Initialization
  // ===============================================================
  Future<void> _init() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }

    _profileSub = _authService.userProfileStream(uid).listen(
      (profile) {
        if (!mounted) return;
        setState(() {
          _user = profile;
          _loading = false;
        });
        if (!_profileReady.isCompleted) _profileReady.complete();
        // NOTE: the background service is NOT started here anymore.
        // It only starts once location permission is actually granted
        // — see _startLocation() below. Starting it before permission
        // exists is unreliable on Android 14+ and was silently failing.
      },
      onError: (error) {
        debugPrint('User profile stream error: $error');
        if (!_profileReady.isCompleted) _profileReady.complete();
        if (mounted) setState(() => _loading = false);
      },
    );

    await _profileReady.future;
    if (!mounted) return;
    await _startLocation();
  }

  // ===============================================================
  // Start GPS
  // ===============================================================
  Future<void> _startLocation() async {
    if (mounted) setState(() => _locationError = null);

    final granted = await _locationService.ensurePermission();
    if (!granted) {
      if (mounted) {
        setState(() {
          _locationError =
              'Location permission is needed to show your position on the map. Turn on GPS and allow location for WayMate, then tap Retry.';
        });
      }
      return;
    }

    // Safe to start the background service now that permission exists.
    if (!_backgroundServiceStarted) {
      _backgroundServiceStarted = true;
      try {
        startBackgroundLocationService();
      } catch (e) {
        debugPrint('Background location service failed to start: $e');
      }
      NotificationService.requestPermission();
    }

    // ---- THE FIX ----
    // The live GPS stream is now set up FIRST, unconditionally, as soon
    // as permission is granted. Before, it was only created AFTER the
    // one-shot getCurrentPosition() call below succeeded — so if that
    // first fetch timed out (very common: cold GPS, indoors, right
    // after install with no cached last-known position), the stream
    // listener never got created at all, and the location would never
    // update again for the rest of the session. Now, even if the
    // one-shot fetch below fails, live updates still flow in the
    // moment the device gets a real fix.
    await _positionSub?.cancel();
    _positionSub = _locationService.positionStream.listen(
      (pos) {
        if (!mounted) return;
        setState(() {
          _currentLatLng = LatLng(pos.latitude, pos.longitude);
          _locationError = null;
        });
        debugPrint('LIVE GPS: ${pos.latitude}, ${pos.longitude}');
        unawaited(_pushAndCheck(pos));
      },
      onError: (error) {
        debugPrint('Location stream error: $error');
      },
    );

    // Try to get an instant first fix (cache or quick GPS lock) just to
    // populate the map faster. If this fails, it no longer matters —
    // the listener above is already live and will catch the next fix.
    try {
      final position = await _locationService.getCurrentPosition().timeout(
        const Duration(seconds: 10),
        onTimeout: () async {
          debugPrint('getCurrentPosition timed out after 10 seconds.');
          final last = await Geolocator.getLastKnownPosition();
          if (last != null) {
            debugPrint('Using last known position.');
            return last;
          }
          throw Exception(
              'GPS timed out and no last known position is available.');
        },
      );

      if (!mounted) return;
      setState(() {
        _currentLatLng = LatLng(position.latitude, position.longitude);
        _locationError = null;
      });
      debugPrint('INITIAL GPS: ${position.latitude}, ${position.longitude}');
      await _pushAndCheck(position);
    } catch (e) {
      // No longer fatal — just means the map opens without a pin until
      // the live stream above delivers the first real fix.
      debugPrint('Initial getCurrentPosition failed (non-fatal): $e');
      if (_currentLatLng == null && mounted) {
        setState(() {
          _locationError =
              'Still waiting for a GPS fix… make sure location is turned on. This will update automatically once a signal is found.';
        });
      }
    }
  }

  // ===============================================================
  // Push location and battery status
  // ===============================================================
  Future<void> _pushAndCheck(Position pos) async {
    final uid = _authService.currentUser?.uid;
    if (uid == null || _user == null) return;

    try {
      await _locationService.pushLocation(
        uid: uid,
        groupId: _user!.groupId,
        role: _user!.role,
        position: pos,
      );
    } catch (e) {
      debugPrint(
          'pushLocation failed. uid=$uid role=${_user!.role} groupId=${_user!.groupId} error=$e');
      return;
    }

    if (_user!.role == 'tourist') {
      final shouldAlert = await _locationService.checkLowBatteryOnce();
      if (shouldAlert) {
        try {
          await _sosService.sendLowBatteryAlert(
            uid: uid,
            touristName: _user!.name,
            groupId: _user!.groupId,
            position: pos,
          );
        } catch (e) {
          debugPrint('Low battery alert failed: $e');
        }
      }
    }
  }

  // ===============================================================
  // SOS
  // ===============================================================
  Future<void> _handleSos() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null || _currentLatLng == null) return;

    try {
      final position = Position(
        latitude: _currentLatLng!.latitude,
        longitude: _currentLatLng!.longitude,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

      final alertId = await _sosService.triggerSos(
        uid: uid,
        touristName: _user?.name ?? 'A tourist',
        groupId: _user?.groupId,
        position: position,
        emergencyContactPhone: _user?.emergencyContactPhone,
      );

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _AlertConfirmationDialog(
          color: AppColors.sos,
          title: 'Help is on the way',
          subtitle:
              'Your guide, emergency contact, and nearest group member have been notified.',
          onCancel: () async {
            await _sosService.resolveAlert(alertId);
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      );
    } catch (e) {
      debugPrint('SOS failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send alert. Try again.')),
        );
      }
    }
  }

  // ===============================================================
  // Medical aid
  // ===============================================================
  Future<void> _handleMedicalAid() async {
    final uid = _authService.currentUser?.uid;
    if (uid == null || _currentLatLng == null) return;

    try {
      final position = Position(
        latitude: _currentLatLng!.latitude,
        longitude: _currentLatLng!.longitude,
        timestamp: DateTime.now(),
        accuracy: 0,
        altitude: 0,
        altitudeAccuracy: 0,
        heading: 0,
        headingAccuracy: 0,
        speed: 0,
        speedAccuracy: 0,
      );

      final alertId = await _sosService.triggerMedicalAid(
        uid: uid,
        touristName: _user?.name ?? 'A tourist',
        groupId: _user?.groupId,
        position: position,
      );

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => _AlertConfirmationDialog(
          color: AppColors.medical,
          title: 'Help is being arranged',
          subtitle: 'Your guide and nearest group member have been notified.',
          onCancel: () async {
            await _sosService.resolveAlert(alertId);
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
      );
    } catch (e) {
      debugPrint('Medical aid failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not send request. Try again.')),
        );
      }
    }
  }

  // ===============================================================
  // Route
  // ===============================================================
  Future<void> _fetchRoute(LatLng from, LatLng to) async {
    if (_isLoadingRoute) return;
    if (mounted) setState(() => _isLoadingRoute = true);

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/foot/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final response = await http.get(url);

      if (response.statusCode != 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Route service returned an error (${response.statusCode}). Try again shortly.'),
          ));
        }
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final routes = data['routes'];
      if (routes is! List || routes.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No route could be found.')),
          );
        }
        return;
      }

      final geometry = routes.first['geometry'];
      if (geometry is! Map<String, dynamic>) return;
      final rawCoords = geometry['coordinates'];
      if (rawCoords is! List || rawCoords.isEmpty) return;

      final points = <LatLng>[];
      for (final coordinate in rawCoords) {
        if (coordinate is! List || coordinate.length < 2) continue;
        final lng = (coordinate[0] as num?)?.toDouble();
        final lat = (coordinate[1] as num?)?.toDouble();
        if (lat == null || lng == null) continue;
        points.add(LatLng(lat, lng));
      }

      if (!mounted) return;
      setState(() => _routePoints = points.isEmpty ? null : points);
    } catch (e) {
      debugPrint('Route loading failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not load route right now.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  // ===============================================================
  // Map controls
  // ===============================================================
  void _jumpToLocation(double lat, double lng) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _mapController.move(LatLng(lat, lng), 16);
      } catch (_) {}
    });
  }

  void _zoomBy(double delta) {
    try {
      final camera = _mapController.camera;
      _mapController.move(camera.center, camera.zoom + delta);
    } catch (_) {}
  }

  void _recenter() {
    if (_currentLatLng == null) return;
    try {
      _mapController.move(_currentLatLng!, _mapController.camera.zoom);
    } catch (_) {}
  }

  Widget _buildZoomControls({Widget? topExtra}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (topExtra != null) ...[topExtra, const SizedBox(height: 10)],
        Container(
          decoration: BoxDecoration(
            color: AppColors.navyCard,
            border: Border.all(color: AppColors.navyBorder),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.add, color: Colors.white, size: 18),
                onPressed: () => _zoomBy(1),
                tooltip: 'Zoom in',
              ),
              Container(height: 1, width: 24, color: AppColors.navyBorder),
              IconButton(
                icon: const Icon(Icons.remove, color: Colors.white, size: 18),
                onPressed: () => _zoomBy(-1),
                tooltip: 'Zoom out',
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppColors.navyCard,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.navyBorder),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4)),
            ],
          ),
          child: IconButton(
            icon: const Icon(Icons.my_location,
                color: Color(0xFF3B82F6), size: 18),
            onPressed: _recenter,
            tooltip: 'Recenter on my location',
          ),
        ),
      ],
    );
  }

  // ===============================================================
  // Marker information
  // ===============================================================
  Future<void> _showMarkerInfo(
    String uid,
    double lat,
    double lng,
    String role, {
    int battery = -1,
  }) async {
    final profile = await _authService.getUserProfile(uid);
    final address =
        await _locationService.getAddressFromCoordinates(lat, lng);

    double? distanceKm;
    if (_currentLatLng != null) {
      distanceKm = _locationService.distanceBetween(
            _currentLatLng!.latitude,
            _currentLatLng!.longitude,
            lat,
            lng,
          ) /
          1000;
    }

    final myUid = _authService.currentUser?.uid;
    final isSelf = uid == myUid;
    final groupId = _user?.groupId;
    final canManage = _user?.role == 'guide' && !isSelf && groupId != null;

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.navyCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  role == 'guide' ? Icons.shield_outlined : Icons.person_outline,
                  color: AppColors.gold,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isSelf
                        ? '${profile?.name ?? 'You'} (You)'
                        : (profile?.name ?? 'Group member'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              role == 'guide' ? 'Guide' : 'Tourist',
              style: const TextStyle(
                  color: AppColors.textOnNavySecondary, fontSize: 12),
            ),
            const SizedBox(height: 16),
            if (profile != null && profile.phone.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.phone_outlined,
                      color: AppColors.textOnNavySecondary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(profile.phone,
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.call, color: AppColors.gold, size: 20),
                    onPressed: () =>
                        launchUrl(Uri.parse('tel:${profile.phone}')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined,
                    color: AppColors.textOnNavySecondary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(address,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                ),
              ],
            ),
            if (distanceKm != null && !isSelf) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.social_distance_outlined,
                      color: AppColors.textOnNavySecondary, size: 18),
                  const SizedBox(width: 8),
                  Text('${distanceKm.toStringAsFixed(1)} km away',
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                ],
              ),
            ],
            if (battery >= 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    battery <= 15 ? Icons.battery_alert : Icons.battery_std,
                    color: battery <= 15
                        ? AppColors.medical
                        : AppColors.textOnNavySecondary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$battery% battery',
                    style: TextStyle(
                      color: battery <= 15 ? AppColors.sos : Colors.white,
                      fontSize: 14,
                      fontWeight:
                          battery <= 15 ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ],
            if (profile?.emergencyContactPhone != null &&
                profile!.emergencyContactPhone!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.family_restroom,
                      color: AppColors.textOnNavySecondary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Emergency: ${profile.emergencyContactPhone}',
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                ],
              ),
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
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: sheetContext,
                      builder: (c) => AlertDialog(
                        backgroundColor: AppColors.navyCard,
                        title: const Text('Transfer guide role?',
                            style: TextStyle(color: Colors.white)),
                        content: Text(
                          '${profile?.name ?? "This member"} will become the new guide. You will become a regular tourist in this group.',
                          style:
                              const TextStyle(color: AppColors.textOnNavySecondary),
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(c).pop(false),
                              child: const Text('Cancel')),
                          TextButton(
                              onPressed: () => Navigator.of(c).pop(true),
                              child: const Text('Transfer')),
                        ],
                      ),
                    );
                    if (confirmed == true && myUid != null) {
                      await _groupService.transferGuideRole(
                        groupId: groupId!,
                        currentGuideUid: myUid,
                        newGuideUid: uid,
                      );
                      if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                    }
                  },
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.person_remove_outlined,
                      size: 18, color: AppColors.sos),
                  label: const Text('Remove from Group',
                      style: TextStyle(color: AppColors.sos)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.sos, width: 1.5),
                  ),
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: sheetContext,
                      builder: (c) => AlertDialog(
                        backgroundColor: AppColors.navyCard,
                        title: const Text('Remove member?',
                            style: TextStyle(color: Colors.white)),
                        content: Text(
                          '${profile?.name ?? "This member"} will be removed from the group.',
                          style:
                              const TextStyle(color: AppColors.textOnNavySecondary),
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.of(c).pop(false),
                              child: const Text('Cancel')),
                          TextButton(
                            onPressed: () => Navigator.of(c).pop(true),
                            child: const Text('Remove',
                                style: TextStyle(color: AppColors.sos)),
                          ),
                        ],
                      ),
                    );
                    if (confirmed == true) {
                      try {
                        await _groupService.removeMember(
                            groupId: groupId!, memberUid: uid);
                        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                      } catch (e) {
                        debugPrint('removeMember failed: $e');
                        if (sheetContext.mounted) {
                          ScaffoldMessenger.of(sheetContext).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'Could not remove this member — check Firestore rules allow it.')),
                          );
                        }
                      }
                    }
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // Alert helpers
  // ===============================================================
  static String _alertLabel(String type) {
    switch (type) {
      case 'medical':
        return 'feels unwell';
      case 'lowBattery':
        return 'low battery — last known location';
      default:
        return 'needs help!';
    }
  }

  Future<void> _showAlertDetail(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final uid = data['uid'] as String?;
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    final type = data['type'] as String? ?? 'sos';
    final label = _alertLabel(type);
    final color = type == 'medical'
        ? AppColors.medical
        : (type == 'lowBattery' ? AppColors.goldDark : AppColors.sos);

    final profile =
        uid != null ? await _authService.getUserProfile(uid) : null;
    final address =
        await _locationService.getAddressFromCoordinates(lat, lng);

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.navyCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  type == 'medical'
                      ? Icons.medical_services_outlined
                      : (type == 'lowBattery'
                          ? Icons.battery_alert
                          : Icons.warning_rounded),
                  color: color,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${profile?.name ?? "A tourist"} $label',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (profile != null && profile.phone.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.phone_outlined,
                      color: AppColors.textOnNavySecondary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(profile.phone,
                        style: const TextStyle(color: Colors.white, fontSize: 14)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.call, color: AppColors.gold, size: 20),
                    onPressed: () =>
                        launchUrl(Uri.parse('tel:${profile.phone}')),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.location_on_outlined,
                    color: AppColors.textOnNavySecondary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(address,
                      style: const TextStyle(color: Colors.white, fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: AppColors.navyDark,
                ),
                icon: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('Mark as Resolved'),
                onPressed: () async {
                  await _sosService.resolveAlert(doc.id);
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // Main build
  // ===============================================================
  @override
  Widget build(BuildContext context) {
    if (_loading || _user == null) {
      return const Scaffold(
        backgroundColor: AppColors.navy,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isGuide = _user!.role == 'guide';

    return AppScaffoldWithSos(
      title: 'WayMate',
      drawer: AppDrawer(user: _user!, onLogout: () => _authService.logout()),
      onSosTriggered: _handleSos,
      onMedicalAidTriggered: _handleMedicalAid,
      onAssistantTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AiAssistantScreen()),
        );
      },
      body: isGuide ? _buildGuideMap() : _buildTouristView(),
    );
  }

  // ===============================================================
  // No group
  // ===============================================================
  Widget _buildNoGroupState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.groups_outlined, color: AppColors.gold, size: 56),
            const SizedBox(height: 16),
            const Text(
              "You're not currently in a group",
              style: TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Ask your guide for their group code or QR, then join below.',
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('Join a Group'),
              onPressed: _showJoinGroupDialog,
            ),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // Join group
  // ===============================================================
  Future<void> _showJoinGroupDialog() async {
    final controller = TextEditingController();
    String? errorText;

    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          backgroundColor: AppColors.navyCard,
          title: const Text('Join a Group', style: TextStyle(color: Colors.white)),
          content: TextField(
            controller: controller,
            textCapitalization: TextCapitalization.characters,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(labelText: 'Group Code', errorText: errorText),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                final trimmed = controller.text.trim().toUpperCase();
                if (trimmed.isEmpty) {
                  setDialogState(() => errorText = 'Enter a group code');
                  return;
                }
                Navigator.of(dialogContext).pop(trimmed);
              },
              child: const Text('Join'),
            ),
          ],
        ),
      ),
    );

    controller.dispose();
    if (code == null || !mounted) return;

    final uid = _authService.currentUser?.uid;
    if (uid == null) return;

    final joined = await _groupService.joinGroup(uid: uid, groupCode: code);
    if (!mounted) return;

    if (joined) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Joined the group!')));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That group code was not found.')));
    }
  }

  // ===============================================================
  // Guide without group
  // ===============================================================
  Widget _buildGuideNoGroupState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flag_circle_outlined, color: AppColors.gold, size: 56),
            const SizedBox(height: 16),
            const Text(
              "You're not running a trip right now",
              style: TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Start a new group to begin tracking a fresh set of tourists.',
              style: AppTextStyles.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Start New Trip'),
              onPressed: _showStartNewTripDialog,
            ),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // Start new trip
  // ===============================================================
  Future<void> _showStartNewTripDialog() async {
    final controller =
        TextEditingController(text: "${_user?.name ?? 'Guide'}'s Group");

    final name = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColors.navyCard,
        title: const Text('Start New Trip', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(labelText: 'Group name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(c).pop(), child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.of(c).pop(controller.text.trim()),
              child: const Text('Create')),
        ],
      ),
    );

    controller.dispose();
    final uid = _authService.currentUser?.uid;
    if (name != null && name.isNotEmpty && uid != null) {
      await _groupService.createGroupForGuide(guideId: uid, groupName: name);
    }
  }

  // ===============================================================
  // TOURIST VIEW
  // ===============================================================
  Widget _buildTouristView() {
    if (_locationError != null && _currentLatLng == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_locationError!, style: AppTextStyles.body, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _startLocation, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    if (_currentLatLng == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_user!.groupId == null) {
      return _buildNoGroupState();
    }

    final groupId = _user!.groupId!;
    _ensureGroupStreams(groupId);

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _destinationStream,
      builder: (context, destSnapshot) {
        final destination = destSnapshot.data;
        LatLng? destLatLng;
        if (destination != null) {
          final dLat = (destination['lat'] as num?)?.toDouble();
          final dLng = (destination['lng'] as num?)?.toDouble();
          if (dLat != null && dLng != null) destLatLng = LatLng(dLat, dLng);
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _locationsStream,
          builder: (context, snapshot) {
            final markers = <Marker>[
              Marker(
                point: _currentLatLng!,
                width: 44,
                height: 44,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    final uid = _authService.currentUser?.uid;
                    if (uid != null) {
                      _showMarkerInfo(uid, _currentLatLng!.latitude,
                          _currentLatLng!.longitude, _user?.role ?? 'tourist');
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
                final lat = (data['lat'] as num?)?.toDouble();
                final lng = (data['lng'] as num?)?.toDouble();
                final role = data['role'] as String? ?? 'tourist';
                final battery = (data['batteryLevel'] as num?)?.toInt() ?? -1;
                final isOnline = data['online'] as bool? ?? true;

                if (lat == null || lng == null) continue;
                if (role == 'guide') guideLatLng = LatLng(lat, lng);

                markers.add(Marker(
                  point: LatLng(lat, lng),
                  width: 40,
                  height: 40,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showMarkerInfo(doc.id, lat, lng, role, battery: battery),
                    child: role == 'guide'
                        ? _GuideMarker(isOnline: isOnline)
                        : _TouristMarker(isOnline: isOnline),
                  ),
                ));
              }
            }

            if (destLatLng != null) {
              markers.add(Marker(
                point: destLatLng,
                width: 40,
                height: 40,
                child: const _DestinationMarker(),
              ));
            }

            return Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(initialCenter: _currentLatLng!, initialZoom: 15),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.waymate',
                    ),
                    if (_routePoints != null)
                      PolylineLayer(
                        polylines: [
                          Polyline(points: _routePoints!, color: AppColors.gold, strokeWidth: 4),
                        ],
                      ),
                    MarkerLayer(markers: markers),
                  ],
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Column(
                    children: [
                      _buildAnnouncementBanner(groupId),
                      if (destination != null && destLatLng != null) ...[
                        const SizedBox(height: 8),
                        _buildDestinationBanner(destination, destLatLng),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 254,
                  child: _buildZoomControls(
                    topExtra: guideLatLng == null
                        ? null
                        : GestureDetector(
                            onTap: _isLoadingRoute
                                ? null
                                : () => _fetchRoute(_currentLatLng!, guideLatLng!),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration:
                                  BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(12)),
                              child: _isLoadingRoute
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: AppColors.navyDark),
                                    )
                                  : const Icon(Icons.route, color: AppColors.navyDark, size: 20),
                            ),
                          ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===============================================================
  // Announcement
  // ===============================================================
  Widget _buildAnnouncementBanner(String groupId) {
    return StreamBuilder<Map<String, dynamic>?>(
      stream: _announcementStream,
      builder: (context, snapshot) {
        final ann = snapshot.data;
        if (ann == null) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(14)),
          child: Row(
            children: [
              const Icon(Icons.campaign, color: AppColors.navyDark, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  ann['text'] as String? ?? '',
                  style: const TextStyle(
                      color: AppColors.navyDark, fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ===============================================================
  // Destination banner
  // ===============================================================
  Widget _buildDestinationBanner(Map<String, dynamic> destination, LatLng destLatLng) {
    double? distanceKm;
    if (_currentLatLng != null) {
      distanceKm = _locationService.distanceBetween(
            _currentLatLng!.latitude,
            _currentLatLng!.longitude,
            destLatLng.latitude,
            destLatLng.longitude,
          ) /
          1000;
    }

    final reachBy = destination['reachByTime'] as String?;
    final subtitleParts = <String>[
      if (distanceKm != null) '${distanceKm.toStringAsFixed(1)} km away',
      if (reachBy != null && reachBy.isNotEmpty) 'Reach by $reachBy',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.navyCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.gold),
      ),
      child: Row(
        children: [
          const Icon(Icons.flag, color: AppColors.sos, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  destination['name'] as String? ?? 'Destination',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                ),
                if (subtitleParts.isNotEmpty)
                  Text(subtitleParts.join(' · '),
                      style: const TextStyle(color: AppColors.textOnNavySecondary, fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _isLoadingRoute || _currentLatLng == null
                ? null
                : () => _fetchRoute(_currentLatLng!, destLatLng),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(8)),
              child: const Text('Navigate',
                  style: TextStyle(color: AppColors.navyDark, fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  // ===============================================================
  // GUIDE MAP
  // ===============================================================
  Widget _buildGuideMap() {
    final groupId = _user!.groupId;
    if (groupId == null) return _buildGuideNoGroupState();

    _ensureGroupStreams(groupId);

    return StreamBuilder<Map<String, dynamic>?>(
      stream: _destinationStream,
      builder: (context, destSnapshot) {
        final destination = destSnapshot.data;
        LatLng? destLatLng;
        if (destination != null) {
          final dLat = (destination['lat'] as num?)?.toDouble();
          final dLng = (destination['lng'] as num?)?.toDouble();
          if (dLat != null && dLng != null) destLatLng = LatLng(dLat, dLng);
          debugPrint('DESTINATION DATA: $destination');
          debugPrint('DESTINATION LAT/LNG: $dLat, $dLng');
        }

        return StreamBuilder<QuerySnapshot>(
          stream: _locationsStream,
          builder: (context, locSnapshot) {
            final docs = locSnapshot.data?.docs ?? [];
            final myUid = _authService.currentUser?.uid;
            final markers = <Marker>[];

            // Guide's own live location.
            if (_currentLatLng != null) {
              markers.add(Marker(
                point: _currentLatLng!,
                width: 44,
                height: 44,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (myUid != null) {
                      _showMarkerInfo(
                          myUid, _currentLatLng!.latitude, _currentLatLng!.longitude, 'guide');
                    }
                  },
                  child: const _MyLocationDot(),
                ),
              ));
            }

            // Other group members.
            for (final doc in docs) {
              final data = doc.data() as Map<String, dynamic>;
              final uid = doc.id;
              if (uid == myUid) continue;

              final lat = (data['lat'] as num?)?.toDouble();
              final lng = (data['lng'] as num?)?.toDouble();
              if (lat == null || lng == null) {
                debugPrint(
                    'Skipping marker for $uid because coordinates are invalid: ${data['lat']} / ${data['lng']}');
                continue;
              }

              final role = data['role'] as String? ?? 'tourist';
              final battery = (data['batteryLevel'] as num?)?.toInt() ?? -1;
              final isOnline = data['online'] as bool? ?? true;

              markers.add(Marker(
                point: LatLng(lat, lng),
                width: 44,
                height: 44,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showMarkerInfo(uid, lat, lng, role, battery: battery),
                  child: role == 'guide'
                      ? _GuideMarker(isOnline: isOnline)
                      : _TouristMarker(isOnline: isOnline),
                ),
              ));
            }

            if (destLatLng != null) {
              markers.add(Marker(
                point: destLatLng,
                width: 44,
                height: 44,
                child: const _DestinationMarker(),
              ));
            }

            debugPrint('GUIDE UID: $myUid');
            debugPrint('GUIDE CURRENT LOCATION: $_currentLatLng');
            debugPrint('FIRESTORE LOCATION DOCS: ${docs.length}');
            debugPrint('TOTAL MAP MARKERS: ${markers.length}');
            debugPrint('DESTINATION LATLNG: $destLatLng');

            final center = _currentLatLng ??
                (markers.isNotEmpty ? markers.first.point : const LatLng(11.2588, 75.7804));

            // THE FIX: as soon as we have a REAL position to show (our
            // own GPS, or at least one member's marker), move the map
            // there exactly once. `initialCenter` can't do this because
            // it only applies on the first-ever build, which usually
            // happens before any real data exists.
            final hasRealCenter = _currentLatLng != null || markers.isNotEmpty;
            if (hasRealCenter && !_didCenterGuideMap) {
              _didCenterGuideMap = true;
              final target = center;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                try {
                  _mapController.move(target, 15);
                } catch (_) {}
              });
            }

            final touristCount =
                docs.where((d) => (d.data() as Map<String, dynamic>)['role'] != 'guide').length;

            return StreamBuilder<QuerySnapshot>(
              stream: _alertsStream,
              builder: (context, alertSnapshot) {
                final alerts = alertSnapshot.data?.docs ?? [];

                for (final doc in alerts) {
                  if (!_notifiedAlertIds.contains(doc.id)) {
                    _notifiedAlertIds.add(doc.id);
                    WidgetsBinding.instance.addPostFrameCallback((_) async {
                      final data = doc.data() as Map<String, dynamic>;
                      final uid = data['uid'] as String?;
                      final profile =
                          uid != null ? await _authService.getUserProfile(uid) : null;
                      NotificationService.showSosAlert(touristName: profile?.name ?? 'A tourist');
                    });
                  }
                }

                final topAlert = alerts.isNotEmpty ? alerts.first : null;

                return Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(initialCenter: center, initialZoom: 15),
                      children: [
                        TileLayer(
                          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.example.waymate',
                        ),
                        MarkerLayer(markers: markers),
                      ],
                    ),
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.navyCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.navyBorder),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 16, offset: const Offset(0, 6)),
                          ],
                        ),
                        child: Row(
                          children: [
                            Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.success, shape: BoxShape.circle)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(groupId,
                                  style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 2.5)),
                            ),
                            Text('$touristCount members',
                                style: const TextStyle(color: AppColors.textOnNavySecondary, fontSize: 11)),
                            const SizedBox(width: 10),
                            Container(width: 1, height: 16, color: AppColors.navyBorder),
                            if (alerts.isNotEmpty)
                              IconButton(
                                icon: Badge(
                                  label: Text('${alerts.length}'),
                                  backgroundColor: AppColors.sos,
                                  child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 20),
                                ),
                                onPressed: () => _showAlertDetail(topAlert!),
                              )
                            else
                              const SizedBox(width: 44),
                            IconButton(
                              icon: const Icon(Icons.qr_code, color: AppColors.gold, size: 20),
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => QrDisplayScreen(groupCode: groupId)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (topAlert != null)
                      Positioned(top: 66, left: 12, right: 12, child: _buildAlertBanner(topAlert)),
                    Positioned(right: 14, bottom: 254, child: _buildZoomControls()),
                    DraggableScrollableSheet(
                      initialChildSize: 0.22,
                      minChildSize: 0.20,
                      maxChildSize: 0.7,
                      builder: (context, scrollController) => Container(
                        decoration: const BoxDecoration(
                          color: AppColors.navyCard,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        child: _buildMemberSheetContent(scrollController, docs),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // ===============================================================
  // Alert banner
  // ===============================================================
  Widget _buildAlertBanner(QueryDocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final type = data['type'] as String? ?? 'sos';
    final uid = data['uid'] as String?;
    final color = type == 'medical'
        ? AppColors.medical
        : (type == 'lowBattery' ? AppColors.goldDark : AppColors.sos);
    final icon = type == 'medical'
        ? Icons.medical_services_outlined
        : (type == 'lowBattery' ? Icons.battery_alert : Icons.warning_rounded);
    final label = _alertLabel(type);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showAlertDetail(doc),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 19),
            const SizedBox(width: 10),
            Expanded(
              child: FutureBuilder<AppUser?>(
                future: uid != null ? _authService.getUserProfile(uid) : null,
                builder: (context, snap) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${snap.data?.name ?? "A tourist"} $label',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    const Text('Tap for details', style: TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // Member sheet
  // ===============================================================
  Widget _buildMemberSheetContent(ScrollController scrollController, List<QueryDocumentSnapshot> docs) {
    final now = DateTime.now();
    final touristCount =
        docs.where((d) => (d.data() as Map<String, dynamic>)['role'] != 'guide').length;

    LatLng? guideLatLng;
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      if (data['role'] == 'guide') {
        final lat = (data['lat'] as num?)?.toDouble();
        final lng = (data['lng'] as num?)?.toDouble();
        if (lat != null && lng != null) guideLatLng = LatLng(lat, lng);
      }
    }
    guideLatLng ??= _currentLatLng;

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      children: [
        Center(
          child: Container(width: 36, height: 4, margin: const EdgeInsets.only(bottom: 14), decoration: BoxDecoration(color: AppColors.navyBorder, borderRadius: BorderRadius.circular(2))),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('MEMBERS ($touristCount)', style: AppTextStyles.label),
            const Icon(Icons.keyboard_arrow_up, color: AppColors.textOnNavyMuted, size: 18),
          ],
        ),
        const SizedBox(height: 12),
        ...docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final uid = doc.id;
          final lat = (data['lat'] as num?)?.toDouble();
          final lng = (data['lng'] as num?)?.toDouble();
          final role = data['role'] as String? ?? 'tourist';
          final battery = (data['batteryLevel'] as num?)?.toInt() ?? -1;
          final ts = data['timestamp'] as Timestamp?;
          final isActive = ts != null && now.difference(ts.toDate()).inMinutes < 10;
          final isOnline = data['online'] as bool? ?? true;

          bool isStraying = false;
          if (role == 'tourist' && guideLatLng != null && lat != null && lng != null) {
            isStraying = _locationService.isStrayingTooFar(
              touristLat: lat,
              touristLng: lng,
              guideLat: guideLatLng.latitude,
              guideLng: guideLatLng.longitude,
            );
          }

          String statusText;
          Color statusColor;
          if (!isOnline) {
            statusText = 'Offline — last known location';
            statusColor = AppColors.textOnNavyMuted;
          } else if (isStraying) {
            statusText = 'Straying too far';
            statusColor = AppColors.goldDark;
          } else if (isActive) {
            statusText = 'Active';
            statusColor = AppColors.success;
          } else {
            statusText = 'Inactive';
            statusColor = AppColors.textOnNavyMuted;
          }

          return FutureBuilder<AppUser?>(
            future: _authService.getUserProfile(uid),
            builder: (context, snap) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (lat != null && lng != null) _jumpToLocation(lat, lng);
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isStraying ? AppColors.goldDark : AppColors.navyBorder, width: isStraying ? 1.5 : 1),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: role == 'guide' ? AppColors.gold : AppColors.navyCard,
                        child: role == 'guide'
                            ? const Icon(Icons.shield, color: AppColors.navyDark, size: 16)
                            : Text(
                                (snap.data?.name.isNotEmpty ?? false) ? snap.data!.name[0].toUpperCase() : '?',
                                style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(snap.data?.name ?? '...', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                            Text(statusText, style: TextStyle(fontSize: 11, color: statusColor)),
                          ],
                        ),
                      ),
                      if (battery >= 0 && battery <= 15)
                        const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.battery_alert, color: AppColors.medical, size: 18)),
                      IconButton(
                        icon: const Icon(Icons.info_outline, color: AppColors.textOnNavySecondary, size: 20),
                        onPressed: () {
                          if (lat != null && lng != null) {
                            _showMarkerInfo(uid, lat, lng, role, battery: battery);
                          }
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        }),
      ],
    );
  }
}

// ===================================================================
// MY LOCATION MARKER
// ===================================================================
class _MyLocationDot extends StatelessWidget {
  const _MyLocationDot();

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFF3B82F6).withOpacity(0.20))),
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF3B82F6),
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 1))],
          ),
        ),
      ],
    );
  }
}

// ===================================================================
// GUIDE MARKER
// ===================================================================
class _GuideMarker extends StatelessWidget {
  final double size;
  final bool isOnline;
  const _GuideMarker({this.size = 34, this.isOnline = true});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.gold,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 5, offset: const Offset(0, 2))],
          ),
          child: Icon(Icons.shield, color: AppColors.navyDark, size: size * 0.56),
        ),
        if (!isOnline)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.36,
              height: size * 0.36,
              decoration: BoxDecoration(color: AppColors.textOnNavyMuted, shape: BoxShape.circle, border: Border.all(color: AppColors.navy, width: 1.5)),
              child: Icon(Icons.wifi_off, color: Colors.white, size: size * 0.2),
            ),
          ),
      ],
    );
  }
}

// ===================================================================
// TOURIST MARKER
// ===================================================================
class _TouristMarker extends StatelessWidget {
  final double size;
  final bool isOnline;
  const _TouristMarker({this.size = 30, this.isOnline = true});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.navy,
            border: Border.all(color: AppColors.gold, width: 2),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 4, offset: const Offset(0, 1))],
          ),
          child: Icon(Icons.person, color: Colors.white, size: size * 0.56),
        ),
        if (!isOnline)
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: size * 0.4,
              height: size * 0.4,
              decoration: BoxDecoration(color: AppColors.textOnNavyMuted, shape: BoxShape.circle, border: Border.all(color: AppColors.navy, width: 1.5)),
              child: Icon(Icons.wifi_off, color: Colors.white, size: size * 0.22),
            ),
          ),
      ],
    );
  }
}

// ===================================================================
// DESTINATION MARKER
// ===================================================================
class _DestinationMarker extends StatelessWidget {
  final double size;
  const _DestinationMarker({this.size = 34});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.sos,
        border: Border.all(color: Colors.white, width: 2.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.35), blurRadius: 5, offset: const Offset(0, 2))],
      ),
      child: Icon(Icons.flag, color: Colors.white, size: size * 0.56),
    );
  }
}

// ===================================================================
// ALERT CONFIRMATION
// ===================================================================
class _AlertConfirmationDialog extends StatelessWidget {
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onCancel;

  const _AlertConfirmationDialog({
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onCancel,
  });

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
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Return to app')),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton(
                  onPressed: onCancel,
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.white, width: 2)),
                  child: const Text('This was a mistake — Cancel', style: TextStyle(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}