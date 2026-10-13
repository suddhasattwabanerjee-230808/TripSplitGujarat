import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../location_service.dart';
import '../theme.dart';

/// A cab-app-style location picker: a map with a pin fixed at the center of
/// the screen — the user pans the map underneath it, and the address below
/// updates to match whatever the pin is currently over. Defaults to the
/// device's current GPS position. Returns the resolved "area, city" label,
/// or null if the user backs out without confirming.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initialLabel});
  final String? initialLabel;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

// Fallback center (Ahmedabad) used only if GPS is unavailable.
const _fallbackCenter = LatLng(23.0225, 72.5714);

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _mapController = MapController();
  LatLng _center = _fallbackCenter;
  String? _label;
  bool _loadingStartPosition = true;
  bool _resolvingLabel = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _label = widget.initialLabel;
    _init();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final position = await fetchCurrentPosition();
    if (!mounted) return;
    if (position != null) {
      _center = LatLng(position.latitude, position.longitude);
    }
    setState(() => _loadingStartPosition = false);
    await _resolveLabel(_center);
  }

  Future<void> _resolveLabel(LatLng point) async {
    setState(() => _resolvingLabel = true);
    final label = await labelForCoordinates(point.latitude, point.longitude);
    if (!mounted) return;
    setState(() {
      _resolvingLabel = false;
      if (label != null) _label = label;
    });
  }

  void _onPositionChanged(MapCamera camera, bool hasGesture) {
    _center = camera.center;
    if (!hasGesture) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () => _resolveLabel(_center));
  }

  Future<void> _recenterOnCurrentLocation() async {
    final position = await fetchCurrentPosition();
    if (position == null || !mounted) return;
    final target = LatLng(position.latitude, position.longitude);
    _mapController.move(target, _mapController.camera.zoom);
    _center = target;
    await _resolveLabel(target);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: paper,
      body: Stack(
        children: [
          if (_loadingStartPosition)
            const Center(child: CircularProgressIndicator(color: teal))
          else
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 16,
                onPositionChanged: _onPositionChanged,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.trip_split_gujarat',
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          if (!_loadingStartPosition)
            const IgnorePointer(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.only(bottom: 34),
                  child: Icon(Icons.location_on_rounded, size: 46, color: ink, shadows: [
                    Shadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 3)),
                  ]),
                ),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  _roundButton(Icons.close_rounded, () => Navigator.pop(context)),
                  const Spacer(),
                  _roundButton(Icons.my_location_rounded, _recenterOnCurrentLocation),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .12), blurRadius: 18, offset: const Offset(0, 6))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded, color: teal, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _resolvingLabel ? 'Finding address…' : (_label ?? 'Unknown location'),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Drag the map so the pin sits where you want.',
                      style: TextStyle(color: muted, fontSize: 11),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: (_loadingStartPosition || _label == null)
                            ? null
                            : () => Navigator.pop(context, _label),
                        style: FilledButton.styleFrom(
                          backgroundColor: ink,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                        ),
                        child: const Text('Confirm location', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundButton(IconData icon, VoidCallback onTap) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(15),
    child: Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .1), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Icon(icon, color: ink, size: 21),
    ),
  );
}
