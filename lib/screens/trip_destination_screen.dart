import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../services/location_service.dart';
import '../services/group_service.dart';

/// Accessed from the drawer. Shows the group's current destination
/// (if any) with Change/Clear actions, or an empty state prompting the
/// guide to set one. Previously this was a card permanently sitting on
/// the Home dashboard; moving it here keeps Home focused purely on
/// live map state.
class TripDestinationScreen extends StatefulWidget {
  final String groupId;
  const TripDestinationScreen({required this.groupId, super.key});

  @override
  State<TripDestinationScreen> createState() => _TripDestinationScreenState();
}

class _TripDestinationScreenState extends State<TripDestinationScreen> {
  final _groupService = GroupService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('Trip Destination')),
      body: StreamBuilder<Map<String, dynamic>?>(
        stream: _groupService.destinationStream(widget.groupId),
        builder: (context, snapshot) {
          final destination = snapshot.data;
          if (destination == null) {
            return _EmptyState(groupId: widget.groupId);
          }
          return _CurrentDestination(groupId: widget.groupId, destination: destination);
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String groupId;
  const _EmptyState({required this.groupId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.flag_outlined, color: AppColors.gold, size: 56),
            const SizedBox(height: 16),
            const Text('No destination set', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            const Text('Set a meeting point so tourists know where to head next.', style: AppTextStyles.body, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.add_location_alt_outlined, size: 18),
              label: const Text('Set Destination'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SetDestinationScreen(groupId: groupId))),
            ),
          ],
        ),
      ),
    );
  }
}

class _CurrentDestination extends StatelessWidget {
  final String groupId;
  final Map<String, dynamic> destination;
  const _CurrentDestination({required this.groupId, required this.destination});

  @override
  Widget build(BuildContext context) {
    final name = destination['name'] as String? ?? 'Destination';
    final reachBy = destination['reachByTime'] as String?;
    final instructions = destination['instructions'] as String?;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavyCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.flag, color: AppColors.sos, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600))),
                ]),
                if (reachBy != null && reachBy.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.schedule, color: AppColors.textOnNavySecondary, size: 16),
                    const SizedBox(width: 8),
                    Text('Reach by $reachBy', style: AppTextStyles.body),
                  ]),
                ],
                if (instructions != null && instructions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Icon(Icons.notes, color: AppColors.textOnNavySecondary, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(instructions, style: AppTextStyles.body)),
                  ]),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            icon: const Icon(Icons.edit_location_alt_outlined, size: 18),
            label: const Text('Change Destination'),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => SetDestinationScreen(groupId: groupId))),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            icon: const Icon(Icons.close, size: 18, color: AppColors.sos),
            label: const Text('Clear Destination', style: TextStyle(color: AppColors.sos)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppColors.sos, width: 1.5)),
            onPressed: () => GroupService().clearDestination(groupId: groupId),
          ),
        ],
      ),
    );
  }
}

/// Tap-to-drop-pin map + a short form. Reused for both "set" (no
/// destination yet) and "change" (overwrite the existing one) — both
/// just call setDestination(), which replaces whatever was there.
class SetDestinationScreen extends StatefulWidget {
  final String groupId;
  const SetDestinationScreen({required this.groupId, super.key});

  @override
  State<SetDestinationScreen> createState() => _SetDestinationScreenState();
}

class _SetDestinationScreenState extends State<SetDestinationScreen> {
  final _groupService = GroupService();
  final _locationService = LocationService();
  final _nameController = TextEditingController();
  final _instructionsController = TextEditingController();
  final MapController _mapController = MapController();
  LatLng? _pickedPoint;
  LatLng _mapCenter = const LatLng(11.2588, 75.7804);
  bool _locationReady = false;
  String? _locationError;
  TimeOfDay? _reachByTime;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _centerOnMyLocation();
  }

  // Previously this set _mapCenter via setState AFTER the map had
  // already been built with the wrong default — FlutterMap's
  // initialCenter is only read on the map's FIRST build, so updating
  // it later via setState silently did nothing, leaving the map
  // stuck on the fallback location no matter how long you waited.
  // The fix: don't build the map at all until the real location is
  // known, so initialCenter is correct from the very first frame.
  Future<void> _centerOnMyLocation() async {
    try {
      final granted = await _locationService.ensurePermission();
      if (!granted) {
        if (mounted) setState(() => _locationError = 'Location permission is needed to center the map on you.');
        return;
      }
      final pos = await _locationService.getCurrentPosition();
      if (mounted) setState(() { _mapCenter = LatLng(pos.latitude, pos.longitude); _locationReady = true; });
    } catch (_) {
      if (mounted) setState(() => _locationError = 'Could not get your location. You can still pan the map manually.');
      // Fall through to showing the map at the fallback center rather
      // than blocking the guide from setting a destination at all.
      if (mounted) setState(() => _locationReady = true);
    }
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time != null) setState(() => _reachByTime = time);
  }

  String _formatTime(TimeOfDay t) {
    final hour = t.hourOfPeriod == 0 ? 12 : t.hourOfPeriod;
    final minute = t.minute.toString().padLeft(2, '0');
    final period = t.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  Future<void> _save() async {
    if (_pickedPoint == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tap the map to drop a pin first.')));
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give the destination a name.')));
      return;
    }
    setState(() => _saving = true);
    await _groupService.setDestination(
      groupId: widget.groupId,
      name: _nameController.text.trim(),
      lat: _pickedPoint!.latitude,
      lng: _pickedPoint!.longitude,
      reachByTime: _reachByTime != null ? _formatTime(_reachByTime!) : null,
      instructions: _instructionsController.text.trim().isEmpty ? null : _instructionsController.text.trim(),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(title: const Text('Set Destination')),
      body: !_locationReady
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Finding your location…', style: AppTextStyles.body, textAlign: TextAlign.center),
                  ],
                ),
              ),
            )
          : Column(
        children: [
          if (_locationError != null)
            Container(
              width: double.infinity,
              color: AppColors.goldDark,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Text(_locationError!, style: const TextStyle(color: Colors.white, fontSize: 12), textAlign: TextAlign.center),
            ),
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _mapCenter,
                    initialZoom: 15,
                    onTap: (tapPosition, point) => setState(() => _pickedPoint = point),
                  ),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.waymate'),
                    if (_pickedPoint != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _pickedPoint!,
                          width: 42, height: 42,
                          child: const Icon(Icons.location_on, color: AppColors.sos, size: 42),
                        ),
                      ]),
                  ],
                ),
                if (_pickedPoint == null)
                  Positioned(
                    top: 12, left: 12, right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(color: AppColors.navyCard, borderRadius: BorderRadius.circular(10)),
                      child: const Text('Tap anywhere on the map to drop a pin', style: TextStyle(color: Colors.white, fontSize: 13), textAlign: TextAlign.center),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(controller: _nameController, style: AppTextStyles.body, decoration: const InputDecoration(labelText: 'Destination name', hintText: 'e.g. Kappad Beach — Main Entrance')),
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: _pickTime,
                    child: InputDecorator(
                      decoration: const InputDecoration(labelText: 'Reach by (optional)'),
                      child: Text(_reachByTime != null ? _formatTime(_reachByTime!) : 'Tap to set a time', style: TextStyle(color: _reachByTime != null ? Colors.white : AppColors.textOnNavyMuted)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(controller: _instructionsController, maxLines: 2, style: AppTextStyles.body, decoration: const InputDecoration(labelText: 'Instructions (optional)', hintText: 'e.g. Meet near the large entrance gate')),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navyDark))
                        : const Text('Save Destination'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}