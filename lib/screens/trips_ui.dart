import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../invite_email.dart';
import '../models.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../widgets.dart';

/// Picks which trip the Trip tab shows (same list as Profile → Your trips).
Future<void> showTripSwitcher(BuildContext context) => showAppSheet<void>(
  context,
  title: 'Switch trip',
  children: (ctx) => [
    for (final t in TripStore.instance.trips ?? const <Trip>[])
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TripCard(
          trip: t,
          current: t.id == TripStore.instance.currentTripId,
          onTap: () {
            Navigator.pop(ctx);
            TripStore.instance.selectTrip(t.id);
          },
        ),
      ),
    Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              showJoinTrip(context);
            },
            icon: const Icon(Icons.group_add_outlined, size: 18),
            label: const Text('Join trip'),
            style: secondaryButton(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              showCreateTrip(context);
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('New trip'),
            style: primaryButton(),
          ),
        ),
      ],
    ),
  ],
);

Future<void> showCreateTrip(BuildContext context) => _openTripSheet(context, const _CreateTripSheet());

Future<void> showJoinTrip(BuildContext context) => _openTripSheet(context, const _JoinTripSheet());

/// Shows the create/join sheet; the new trip becomes the current one.
Future<void> _openTripSheet(BuildContext context, Widget sheet) async {
  final trip = await showModalBottomSheet<Trip>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => sheet,
  );
  if (trip != null) {
    await TripStore.instance.refresh();
    TripStore.instance.selectTrip(trip.id);
  }
}

/// The trip's invite sheet: copy the code, or email someone an invite.
Future<void> showInviteSheet(BuildContext context, Trip trip) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _InviteSheet(trip),
);

/// The "+" button's menu: start a trip or join one with a code.
Future<void> showNewTripMenu(BuildContext context) async {
  final choice = await showAppSheet<String>(
    context,
    title: 'New split',
    children: (ctx) => [
      groupedCard([
        _menuRow(
          ctx,
          Icons.add_circle_outline_rounded,
          'Start a new trip or group',
          'Trip, flat, couple, event…',
          'new',
        ),
        _menuRow(
          ctx,
          Icons.group_add_outlined,
          'Join with an invite code',
          'Ask a friend for their 6-letter code',
          'join',
        ),
      ], indent: 64),
    ],
  );
  if (choice == null || !context.mounted) return;
  final trip = await showModalBottomSheet<Trip>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => choice == 'new' ? const _CreateTripSheet() : const _JoinTripSheet(),
  );
  if (trip != null) {
    await TripStore.instance.refresh();
    TripStore.instance.selectTrip(trip.id);
  }
}

Widget _menuRow(BuildContext ctx, IconData icon, String title, String subtitle, String value) => InkWell(
  onTap: () => Navigator.pop(ctx, value),
  child: Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    child: Row(
      children: [
        IconCircle(icon: icon, size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
              ),
              Text(subtitle, style: const TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: muted),
      ],
    ),
  ),
);

/// One trip in the Profile list: icon by trip kind, date, total spent, then
/// the user's balance pill and the members' faces.
class TripCard extends StatelessWidget {
  const TripCard({super.key, required this.trip, this.current = false, this.onTap});
  final Trip trip;

  /// Defaults to showing this trip on the Trip tab.
  final VoidCallback? onTap;

  /// The trip the Trip tab is showing: outlined in the accent colour.
  final bool current;

  @override
  Widget build(BuildContext context) {
    final net = TripStore.instance.myNet(trip.id);
    final kind = trip.tripKind;
    final date = trip.date;
    return AppCard(
      onTap: onTap ?? () => TripStore.instance.selectTrip(trip.id),
      selected: current,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Row(
              children: [
                IconCircle(icon: kind.icon, color: kind.color, size: 42),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trip.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (date != null) formatDate(date),
                          if (trip.destination != null) trip.destination!,
                          if (date == null && trip.destination == null) kind.label,
                        ].join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      money(trip.totalSpent),
                      style: const TextStyle(
                        color: ink,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    const Text('spent', style: TextStyle(color: muted, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: line),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text.rich(
                        TextSpan(
                          text: 'Balance: ',
                          style: const TextStyle(color: muted, fontSize: 11.5),
                          children: [
                            TextSpan(
                              text: net == null
                                  ? '…'
                                  : net.abs() < 0.5
                                  ? 'Settled'
                                  : (net > 0 ? 'You’re owed' : 'You owe'),
                              style: const TextStyle(color: ink, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      if (net != null && net.abs() >= 0.5) ...[
                        const SizedBox(height: 5),
                        AmountPill(value: net, signed: false, fontSize: 12),
                      ],
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Sharing: ${trip.memberCount} ${trip.memberCount == 1 ? 'person' : 'persons'}',
                      style: const TextStyle(color: muted, fontSize: 11.5),
                    ),
                    const SizedBox(height: 4),
                    AvatarStack(members: trip.members, size: 22, max: 4),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CreateTripSheet extends StatefulWidget {
  const _CreateTripSheet();

  @override
  State<_CreateTripSheet> createState() => _CreateTripSheetState();
}

class _CreateTripSheetState extends State<_CreateTripSheet> {
  final _name = TextEditingController();
  final _destination = TextEditingController();
  String _kind = tripKinds.first.id;
  DateTime? _start;
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
        kind: _kind,
        startDate: _start == null
            ? null
            : '${_start!.year}-${_start!.month.toString().padLeft(2, '0')}-${_start!.day.toString().padLeft(2, '0')}',
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFD5D8E2), borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Start a new split',
                style: TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -.4),
              ),
              const SizedBox(height: 23),
              fieldLabel('TRIP NAME'),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: appInputDecoration('e.g. Gujarat Trip', Icons.edit_outlined),
              ),
              const SizedBox(height: 18),
              fieldLabel('TYPE'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final k in tripKinds)
                    ChoiceChip(
                      label: Text(k.label),
                      avatar: Icon(k.icon, size: 16, color: _kind == k.id ? k.color : muted),
                      selected: _kind == k.id,
                      onSelected: (_) => setState(() => _kind = k.id),
                      showCheckmark: false,
                      backgroundColor: Colors.white,
                      selectedColor: k.color.withValues(alpha: .12),
                      side: BorderSide(color: _kind == k.id ? k.color.withValues(alpha: .45) : line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _kind == k.id ? ink : muted,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              fieldLabel('STARTS (OPTIONAL)'),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _start ?? now,
                    firstDate: DateTime(now.year - 2),
                    lastDate: DateTime(now.year + 2),
                  );
                  if (picked != null) setState(() => _start = picked);
                },
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                  decoration: cardDecoration(radius: 14),
                  child: Row(
                    children: [
                      const Icon(Icons.event_outlined, size: 18, color: muted),
                      const SizedBox(width: 10),
                      Text(
                        _start == null ? 'Today' : formatDate(_start!),
                        style: const TextStyle(fontSize: 13, color: ink, fontWeight: FontWeight.w600),
                      ),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded, color: muted, size: 18),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              fieldLabel('DESTINATION (OPTIONAL)'),
              const SizedBox(height: 8),
              TextField(
                controller: _destination,
                textCapitalization: TextCapitalization.words,
                decoration: appInputDecoration('e.g. Ahmedabad', Icons.location_on_outlined),
              ),
              const SizedBox(height: 18),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!, style: const TextStyle(color: negative, fontSize: 12)),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _create,
                  style: primaryButton(radius: 16),
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFD5D8E2), borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'Join a trip',
                style: TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -.4),
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
                decoration: appInputDecoration('e.g. HVHKBJ', Icons.key_outlined),
              ),
              const SizedBox(height: 18),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!, style: const TextStyle(color: negative, fontSize: 12)),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _join,
                  style: primaryButton(radius: 16),
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
      ),
    );
  }
}

class _InviteSheet extends StatefulWidget {
  const _InviteSheet(this.trip);

  final Trip trip;

  @override
  State<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends State<_InviteSheet> {
  final _email = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _copy() {
    Clipboard.setData(ClipboardData(text: widget.trip.inviteCode));
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    messenger.showSnackBar(
      SnackBar(content: Text('Invite code ${widget.trip.inviteCode} copied — share it with your crew.')),
    );
  }

  Future<void> _send() async {
    final to = _email.text.trim();
    if (!InviteEmail.isValidAddress(to)) {
      setState(() => _error = 'Enter an email address, like name@gmail.com.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    // The note that joins them on sign-in. Without it the email still works,
    // with the code to type.
    var autoJoin = true;
    try {
      await ApiClient.instance.inviteByEmail(widget.trip, to);
    } on ApiException {
      autoJoin = false;
    }
    try {
      final opened = await InviteEmail.compose(
        to: to,
        trip: widget.trip,
        inviter: ApiClient.instance.currentUser?.name ?? 'A friend',
        autoJoin: autoJoin,
      );
      if (!mounted) return;
      if (!opened) {
        setState(() => _error = 'No email app found. Copy the code and share it another way.');
        return;
      }
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            autoJoin
                ? 'Tap Send in your email app. $to joins ${widget.trip.name} as soon as they sign in with that address.'
                : 'Invite for $to is ready — tap Send in your email app.',
          ),
        ),
      );
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = 'Couldn’t open your email app (${e.message ?? e.code}).');
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetHandle(),
              const SizedBox(height: 22),
              Text(
                'Invite to ${widget.trip.name}',
                style: const TextStyle(color: ink, fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -.4),
              ),
              const SizedBox(height: 5),
              const Text(
                'Email them an invite: once they install TripSplit and sign in with that Gmail, they land straight in this trip.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 20),
              fieldLabel('INVITE CODE'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.trip.inviteCode,
                        style: const TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 4),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _copy,
                      icon: const Icon(Icons.copy_rounded, size: 18),
                      label: const Text('Copy'),
                      style: TextButton.styleFrom(
                        foregroundColor: accent,
                        textStyle: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              fieldLabel('INVITE BY EMAIL'),
              const SizedBox(height: 8),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _busy ? null : _send(),
                decoration: appInputDecoration('name@gmail.com', Icons.mail_outline_rounded),
              ),
              const SizedBox(height: 6),
              const Text(
                'Opens your email app with the download link and how to join. You tap Send.',
                style: TextStyle(color: muted, fontSize: 11.5),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(_error!, style: const TextStyle(color: negative, fontSize: 12)),
                ),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _send,
                  style: primaryButton(radius: 16),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Send invite', style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
