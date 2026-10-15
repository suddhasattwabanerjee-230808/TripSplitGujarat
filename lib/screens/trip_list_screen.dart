import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import '../update_service.dart';
import 'login_screen.dart';
import 'trip_home_screen.dart';
import 'update_dialog.dart';

class TripListScreen extends StatefulWidget {
  const TripListScreen({super.key});

  @override
  State<TripListScreen> createState() => _TripListScreenState();
}

class _TripListScreenState extends State<TripListScreen> {
  List<Trip>? _trips;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final trips = await ApiClient.instance.listTrips();
      if (mounted) setState(() => _trips = trips);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  Future<void> _openTrip(Trip trip) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TripHomeScreen(tripId: trip.id, tripName: trip.name)),
    );
    _load();
  }

  Future<void> _createTrip() async {
    final created = await showModalBottomSheet<Trip>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _CreateTripSheet(),
    );
    if (created != null) {
      await _load();
      if (mounted) _openTrip(created);
    }
  }

  Future<void> _joinTrip() async {
    final joined = await showModalBottomSheet<Trip>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _JoinTripSheet(),
    );
    if (joined != null) {
      await _load();
      if (mounted) _openTrip(joined);
    }
  }

  Future<void> _checkForUpdate() async {
    final info = await UpdateService.checkForUpdate();
    if (!mounted) return;
    if (info != null) {
      showUpdateDialog(context, info);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're on the latest version.")),
      );
    }
  }

  Future<void> _logOut() async {
    await ApiClient.instance.logOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ApiClient.instance.currentUser;
    return Scaffold(
      backgroundColor: paper,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'TRIPSPLIT',
                            style: TextStyle(
                              color: muted,
                              fontSize: 11,
                              letterSpacing: 2.2,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Hi, ${user?.name ?? ''}',
                            style: const TextStyle(
                              color: ink,
                              fontSize: 25,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.6,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        onPressed: _checkForUpdate,
                        icon: const Icon(Icons.system_update_rounded, color: muted),
                      ),
                      IconButton(
                        onPressed: _logOut,
                        icon: const Icon(Icons.logout_rounded, color: muted),
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _joinTrip,
                          icon: const Icon(Icons.group_add_rounded, size: 18),
                          label: const Text('Join trip'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: ink,
                            side: const BorderSide(color: Color(0xFFD9DED8)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _createTrip,
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('New trip'),
                          style: FilledButton.styleFrom(
                            backgroundColor: ink,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverPadding(
                padding: EdgeInsets.fromLTRB(22, 26, 22, 0),
                sliver: SliverToBoxAdapter(
                  child: Text(
                    'Your trips',
                    style: TextStyle(
                      fontSize: 17,
                      color: ink,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -.3,
                    ),
                  ),
                ),
              ),
              if (_error != null)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 14, 22, 0),
                  sliver: SliverToBoxAdapter(
                    child: Text(_error!, style: const TextStyle(color: Color(0xFFD1805C))),
                  ),
                )
              else if (_trips == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator(color: teal)),
                )
              else if (_trips!.isEmpty)
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(22, 14, 22, 0),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'No trips yet — start one or join with an invite code.',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(22, 13, 22, 24),
                  sliver: SliverList.builder(
                    itemCount: _trips!.length,
                    itemBuilder: (context, index) => _tripCard(_trips![index]),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tripCard(Trip trip) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openTrip(trip),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F3EE),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.map_rounded, color: teal),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.name,
                      style: const TextStyle(
                        color: ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${trip.destination ?? 'No destination set'} · ${trip.memberCount} people · code ${trip.inviteCode}',
                      style: const TextStyle(color: muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: muted),
            ],
          ),
        ),
      ),
    ),
  );
}

class _CreateTripSheet extends StatefulWidget {
  const _CreateTripSheet();

  @override
  State<_CreateTripSheet> createState() => _CreateTripSheetState();
}

class _CreateTripSheetState extends State<_CreateTripSheet> {
  final _name = TextEditingController();
  final _destination = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the trip a name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final trip = await ApiClient.instance.createTrip(
        name: name,
        destination: _destination.text.trim().isEmpty ? null : _destination.text.trim(),
      );
      if (mounted) Navigator.pop(context, trip);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(22, 12, 22, 24 + bottom),
      decoration: const BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9DED8),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Start a new trip',
              style: TextStyle(color: ink, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.5),
            ),
            const SizedBox(height: 23),
            fieldLabel('TRIP NAME'),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: appInputDecoration('e.g. Gujarat Trip', Icons.edit_rounded),
            ),
            const SizedBox(height: 18),
            fieldLabel('DESTINATION (OPTIONAL)'),
            const SizedBox(height: 8),
            TextField(
              controller: _destination,
              textCapitalization: TextCapitalization.words,
              decoration: appInputDecoration('e.g. Ahmedabad', Icons.location_on_rounded),
            ),
            const SizedBox(height: 18),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFD1805C), fontSize: 12)),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _create,
                style: FilledButton.styleFrom(
                  backgroundColor: ink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Create trip', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinTripSheet extends StatefulWidget {
  const _JoinTripSheet();

  @override
  State<_JoinTripSheet> createState() => _JoinTripSheetState();
}

class _JoinTripSheetState extends State<_JoinTripSheet> {
  final _code = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter an invite code.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final trip = await ApiClient.instance.joinTrip(code);
      if (mounted) Navigator.pop(context, trip);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(22, 12, 22, 24 + bottom),
      decoration: const BoxDecoration(
        color: paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9DED8),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(height: 22),
            const Text(
              'Join a trip',
              style: TextStyle(color: ink, fontSize: 23, fontWeight: FontWeight.w800, letterSpacing: -.5),
            ),
            const SizedBox(height: 5),
            const Text(
              'Ask whoever created the trip for their invite code.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 23),
            fieldLabel('INVITE CODE'),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              textCapitalization: TextCapitalization.characters,
              decoration: appInputDecoration('e.g. HVHKBJ', Icons.key_rounded),
            ),
            const SizedBox(height: 18),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(_error!, style: const TextStyle(color: Color(0xFFD1805C), fontSize: 12)),
              ),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: _busy ? null : _join,
                style: FilledButton.styleFrom(
                  backgroundColor: ink,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Join trip', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
