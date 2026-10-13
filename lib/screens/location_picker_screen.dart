import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../location_service.dart';
import '../places_service.dart';
import '../theme.dart';

/// A cab-app-style Google Maps location picker: a pin fixed at the center of
/// the screen — the user pans the map underneath it, or searches for a place
/// by name (Google Places Autocomplete, same as Ola/Uber), and the address
/// below updates to match wherever the pin lands. Defaults to the device's
/// current GPS position. Returns the resolved address label, or null if the
/// user backs out without confirming.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, this.initialLabel});
  final String? initialLabel;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

// Fallback center (Ahmedabad) used only if GPS is unavailable.
const _fallbackCenter = LatLng(23.0225, 72.5714);

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  GoogleMapController? _mapController;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  LatLng _center = _fallbackCenter;
  String? _label;
  bool _loadingStartPosition = true;
  bool _resolvingLabel = true;
  bool _searching = false;
  // Set right before an animateCamera() triggered by code (search pick,
  // recenter) rather than a user drag, so the onCameraIdle it fires doesn't
  // clobber the more specific label we already set with a plain reverse-geocode.
  bool _ignoreNextCameraIdle = false;
  List<PlaceSuggestion> _searchResults = [];
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _label = widget.initialLabel;
    _init();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
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

  void _onCameraMove(CameraPosition position) {
    _center = position.target;
  }

  void _onCameraIdle() {
    if (_ignoreNextCameraIdle) {
      _ignoreNextCameraIdle = false;
      return;
    }
    _resolveLabel(_center);
  }

  Future<void> _recenterOnCurrentLocation() async {
    final position = await fetchCurrentPosition();
    if (position == null || !mounted || _mapController == null) return;
    final target = LatLng(position.latitude, position.longitude);
    _ignoreNextCameraIdle = true;
    await _mapController!.animateCamera(CameraUpdate.newLatLng(target));
    _center = target;
    await _resolveLabel(target);
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    if (trimmed.length < 3) {
      setState(() => _searchResults = []);
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 450), () => _runSearch(trimmed));
  }

  Future<void> _runSearch(String query) async {
    setState(() => _searching = true);
    final results = await autocompletePlaces(
      query,
      originLat: _center.latitude,
      originLng: _center.longitude,
    );
    if (!mounted) return;
    setState(() {
      _searching = false;
      _searchResults = results;
    });
  }

  Future<void> _selectSearchResult(PlaceSuggestion suggestion) async {
    _searchFocus.unfocus();
    setState(() {
      _searchResults = [];
      _searchController.text = suggestion.mainText;
    });
    final place = await fetchPlaceLocation(suggestion.placeId);
    if (place == null || !mounted) return;
    final target = LatLng(place.latitude, place.longitude);
    if (_mapController != null) {
      _ignoreNextCameraIdle = true;
      await _mapController!.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
    }
    _center = target;
    setState(() {
      _resolvingLabel = false;
      _label = place.label;
    });
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
            GoogleMap(
              initialCameraPosition: CameraPosition(target: _center, zoom: 16),
              onMapCreated: (controller) => _mapController = controller,
              onCameraMove: _onCameraMove,
              onCameraIdle: _onCameraIdle,
              onTap: (_) => _searchFocus.unfocus(),
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              mapToolbarEnabled: false,
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _roundButton(Icons.close_rounded, () => Navigator.pop(context)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withValues(alpha: .1), blurRadius: 10, offset: const Offset(0, 3)),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            focusNode: _searchFocus,
                            onChanged: _onSearchChanged,
                            decoration: InputDecoration(
                              hintText: 'Search for a place',
                              hintStyle: const TextStyle(color: Color(0xFFAAB3B5), fontSize: 13),
                              prefixIcon: const Icon(Icons.search_rounded, size: 19, color: muted),
                              suffixIcon: _searching
                                  ? const Padding(
                                      padding: EdgeInsets.all(12),
                                      child: SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: teal),
                                      ),
                                    )
                                  : (_searchController.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.close_rounded, size: 17, color: muted),
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _searchResults = []);
                                          },
                                        )
                                      : null),
                              filled: true,
                              fillColor: Colors.white,
                              contentPadding: const EdgeInsets.symmetric(vertical: 13),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(15),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _roundButton(Icons.my_location_rounded, _recenterOnCurrentLocation),
                    ],
                  ),
                  if (_searchResults.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(maxHeight: 260),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: .1), blurRadius: 14, offset: const Offset(0, 6)),
                        ],
                      ),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F1EC)),
                        itemBuilder: (context, index) {
                          final result = _searchResults[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.place_outlined, color: teal, size: 20),
                            title: Text(
                              result.mainText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w700),
                            ),
                            subtitle: Text(
                              result.secondaryText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w500),
                            ),
                            onTap: () => _selectSearchResult(result),
                          );
                        },
                      ),
                    ),
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
                      'Search above, or drag the map so the pin sits where you want.',
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
