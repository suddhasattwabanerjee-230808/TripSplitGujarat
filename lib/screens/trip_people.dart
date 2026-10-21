import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api_client.dart';
import '../ledger.dart';
import '../models.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../widgets.dart';
import 'expense_screen.dart';

/// A trip and its expenses, kept live (the trip through the store, the
/// expenses through their own listener), for the people pages.
class _TripData extends StatefulWidget {
  const _TripData({required this.tripId, required this.builder});
  final String tripId;
  final Widget Function(BuildContext context, Trip trip, List<TripExpense> expenses) builder;

  @override
  State<_TripData> createState() => _TripDataState();
}

class _TripDataState extends State<_TripData> {
  final _store = TripStore.instance;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  Trip? _trip;
  List<TripExpense>? _expenses;

  @override
  void initState() {
    super.initState();
    _trip = _store.trips?.where((t) => t.id == widget.tripId).firstOrNull;
    _store.addListener(_onStore);
    _sub = ApiClient.instance.watchExpenseSnapshots(widget.tripId).listen((snap) {
      if (mounted) setState(() => _expenses = snap.docs.map(TripExpense.fromDoc).toList());
    }, onError: (Object _) {});
    if (_trip == null) {
      ApiClient.instance.getTrip(widget.tripId).then((t) {
        if (mounted) setState(() => _trip = t);
      }).catchError((Object _) {});
    }
  }

  void _onStore() {
    final trip = _store.trips?.where((t) => t.id == widget.tripId).firstOrNull;
    if (trip != null && mounted) setState(() => _trip = trip);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _store.removeListener(_onStore);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip, expenses = _expenses;
    if (trip == null || expenses == null) {
      return Center(child: CircularProgressIndicator(color: accent));
    }
    return widget.builder(context, trip, expenses);
  }
}

String _firstName(String name) => name.trim().split(RegExp(r'\s+')).first;

/// Everyone on a trip with what they paid, their share and their balance,
/// side by side. Tap a person for their page.
class TripDetailsScreen extends StatelessWidget {
  const TripDetailsScreen({super.key, required this.tripId});
  final String tripId;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paper,
    appBar: AppBar(
      actions: const [ThemeToggle()],
      backgroundColor: paper,
      surfaceTintColor: paper,
      title: const Text('Trip details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    ),
    body: _TripData(tripId: tripId, builder: (_, trip, expenses) => TripDetailsView(trip: trip, expenses: expenses)),
  );
}

/// The trip details page's content, for a given trip and its expenses.
class TripDetailsView extends StatelessWidget {
  const TripDetailsView({super.key, required this.trip, required this.expenses});
  final Trip trip;
  final List<TripExpense> expenses;

  @override
  Widget build(BuildContext context) {
    final totals = totalsFromExpenses(expenses);
    final balances = balancesFor(trip.members, totals.paid, totals.owed);
    final settlements = settlementsFor(balances);
    final me = ApiClient.instance.currentUser?.id;
    final spent = expenses.where((e) => !e.isSettlement).length;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        _header(trip, totals.totalSpent, spent),
        const SizedBox(height: 22),
        const Padding(padding: EdgeInsets.only(left: 2, bottom: 10), child: SectionHeader(title: 'People')),
        Container(
          decoration: cardDecoration(),
          child: Column(
            children: [
              // Column headings line up with the numbers below.
              const Padding(
                padding: EdgeInsets.fromLTRB(14, 12, 34, 6),
                child: Row(
                  children: [
                    Expanded(child: _Heading('NAME', align: TextAlign.left)),
                    SizedBox(width: _numWidth, child: _Heading('PAID')),
                    SizedBox(width: _numWidth, child: _Heading('SHARE')),
                    SizedBox(width: _numWidth + 6, child: _Heading('BALANCE')),
                  ],
                ),
              ),
              for (final (i, m) in trip.members.indexed) ...[
                if (i > 0) Divider(height: 1, indent: 60, color: line),
                _personRow(context, trip, m, balances.firstWhere((b) => b.userId == m.id), m.id == me),
              ],
              const SizedBox(height: 4),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Padding(padding: EdgeInsets.only(left: 2, bottom: 10), child: SectionHeader(title: 'Settle up')),
        Container(
          decoration: cardDecoration(),
          child: settlements.isEmpty
              ? Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    leading: Icon(Icons.check_circle_outline_rounded, color: positive),
                    title: Text('Everyone’s settled up', style: TextStyle(color: ink, fontWeight: FontWeight.w700)),
                  ),
                )
              : Column(
                  children: [
                    for (final (i, s) in settlements.indexed) ...[
                      if (i > 0) Divider(height: 1, indent: 14, color: line),
                      _settlementRow(trip, s),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 10),
        Text(
          'The fewest payments that settle the whole trip.',
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ],
    );
  }

  static const _numWidth = 66.0;

  Widget _header(Trip trip, double total, int count) => Container(
    padding: const EdgeInsets.all(16),
    decoration: cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconCircle(icon: trip.tripKind.icon, color: trip.tripKind.color, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w800, letterSpacing: -.4),
                  ),
                  Text(
                    [
                      trip.tripKind.label,
                      if (trip.date != null) formatDate(trip.date!),
                      if (trip.destination != null) trip.destination!,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _Stat('Total spent', money(total))),
            Expanded(child: _Stat('People', '${trip.memberCount}')),
            Expanded(child: _Stat('Expenses', '$count')),
          ],
        ),
      ],
    ),
  );

  Widget _personRow(BuildContext context, Trip trip, TripMember m, Balance b, bool isMe) {
    final net = unsettledAmount(b.totalPaid, b.totalOwed);
    return InkWell(
      onTap: () => openMember(context, trip.id, m.id),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(
          children: [
            MemberAvatar.of(m, size: 36),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _firstName(m.name),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w700),
                  ),
                  if (isMe) Text('you', style: TextStyle(color: accent, fontSize: 11, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            SizedBox(width: _numWidth, child: _Num(money(b.totalPaid))),
            SizedBox(width: _numWidth, child: _Num(money(b.totalOwed))),
            SizedBox(
              width: _numWidth + 6,
              child: _Num(
                net == 0 ? 'Settled' : signedMoney(net),
                color: net == 0 ? muted : (net > 0 ? positive : negative),
                bold: true,
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 18, color: muted),
          ],
        ),
      ),
    );
  }

  Widget _settlementRow(Trip trip, Settlement s) {
    TripMember who(String? id, String name) => (id == null ? null : trip.member(id)) ?? TripMember(id: id ?? name, name: name);
    final from = who(s.fromUserId, s.fromUser), to = who(s.toUserId, s.toUser);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          MemberAvatar.of(from, size: 28, tripId: trip.id),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(Icons.arrow_forward_rounded, size: 16, color: muted),
          ),
          MemberAvatar.of(to, size: 28, tripId: trip.id),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${_firstName(from.name)} pays ${_firstName(to.name)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w500),
            ),
          ),
          Text(money(s.amount), style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Asks for the signed-in user's own name for [member] and applies it
/// everywhere; an empty name goes back to the one they chose.
Future<void> editPrivateName(BuildContext context, TripMember member) async {
  final controller = TextEditingController(text: member.renamed ? member.name : '');
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: paper,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Your name for them', style: TextStyle(color: ink, fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Only you see this, everywhere in TripSplit. They still go by “${member.ownName}” for everyone else.',
            style: TextStyle(color: muted, fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 24,
            textCapitalization: TextCapitalization.words,
            decoration: appInputDecoration(member.ownName, Icons.badge_outlined),
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ],
      ),
      actions: [
        if (member.renamed)
          TextButton(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Text('Use their name', style: TextStyle(color: muted)),
          ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, controller.text.trim()),
          style: primaryButton(radius: 12),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (name == null) return;
  try {
    await ApiClient.instance.setPrivateName(member.id, name);
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
  TripStore.instance.applyPrivateNames();
}

/// Opens a tripmate's page.
void openMember(BuildContext context, String tripId, String memberId) =>
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => MemberScreen(tripId: tripId, memberId: memberId)));

/// One person on a trip: their profile, totals, who they settle with, and
/// every expense they paid for or share in.
class MemberScreen extends StatelessWidget {
  const MemberScreen({super.key, required this.tripId, required this.memberId});
  final String tripId;
  final String memberId;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paper,
    appBar: AppBar(backgroundColor: paper, surfaceTintColor: paper, actions: const [ThemeToggle()]),
    body: _TripData(
      tripId: tripId,
      builder: (_, trip, expenses) => MemberView(trip: trip, expenses: expenses, memberId: memberId),
    ),
  );
}

/// A person's page content, for a given trip and its expenses.
class MemberView extends StatelessWidget {
  const MemberView({super.key, required this.trip, required this.expenses, required this.memberId});
  final Trip trip;
  final List<TripExpense> expenses;
  final String memberId;

  @override
  Widget build(BuildContext context) {
    final member = trip.member(memberId);
    if (member == null) {
      return Center(child: Text('They’re not on this trip any more.', style: TextStyle(color: muted)));
    }
    final me = ApiClient.instance.currentUser?.id;
    final isMe = member.id == me;
    final totals = totalsFromExpenses(expenses);
    final balances = balancesFor(trip.members, totals.paid, totals.owed);
    final b = balances.firstWhere((b) => b.userId == member.id);
    final net = unsettledAmount(b.totalPaid, b.totalOwed);
    final theirs = settlementsFor(balances).where((s) => s.fromUserId == member.id || s.toUserId == member.id).toList();
    final involved = expenses.where((e) => e.paidBy == member.id || e.shareOf(member.id) > 0).toList()
      ..sort((a, c) => c.dateTime.compareTo(a.dateTime));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      children: [
        Center(child: MemberAvatar.of(member, size: 92, ring: 3)),
        const SizedBox(height: 12),
        Center(
          child: Text(
            member.name,
            textAlign: TextAlign.center,
            style: TextStyle(color: ink, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -.5),
          ),
        ),
        const SizedBox(height: 2),
        Center(
          child: Text(
            isMe ? 'You · ${trip.name}' : (member.renamed ? 'Calls themselves ${member.ownName}' : trip.name),
            style: TextStyle(color: muted, fontSize: 13),
          ),
        ),
        if (!isMe) ...[
          const SizedBox(height: 14),
          // A name only the signed-in user sees, used everywhere in the app.
          Container(
            decoration: cardDecoration(),
            // Its own ink layer, so the tap ripple shows over the card.
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
              leading: Icon(Icons.badge_outlined, color: accent),
              title: Text('Your name for them', style: TextStyle(color: muted, fontSize: 12)),
              subtitle: Text(
                member.renamed ? member.name : 'Not set · only you will see it',
                style: TextStyle(color: ink, fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              trailing: Icon(Icons.edit_outlined, size: 18, color: muted),
              onTap: () => editPrivateName(context, member),
              ),
            ),
          ),
        ],
        if (member.upiId != null) ...[
          const SizedBox(height: 10),
          Center(
            child: ActionChip(
              avatar: Icon(Icons.qr_code_2_outlined, size: 16, color: accent),
              label: Text(member.upiId!),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: member.upiId!));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('UPI ID ${member.upiId} copied.')));
              },
              backgroundColor: surface,
              side: BorderSide(color: line),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              labelStyle: TextStyle(color: ink, fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(child: _Tile('Paid', money(b.totalPaid))),
            const SizedBox(width: 10),
            Expanded(child: _Tile('Share', money(b.totalOwed))),
            const SizedBox(width: 10),
            Expanded(
              child: _Tile(
                net == 0 ? 'Balance' : (net > 0 ? 'Gets back' : 'Owes'),
                net == 0 ? 'Settled' : money(net.abs()),
                color: net == 0 ? muted : (net > 0 ? positive : negative),
              ),
            ),
          ],
        ),
        if (theirs.isNotEmpty) ...[
          const SizedBox(height: 22),
          const Padding(padding: EdgeInsets.only(left: 2, bottom: 10), child: SectionHeader(title: 'Settle up')),
          Container(
            decoration: cardDecoration(),
            child: Column(
              children: [
                for (final (i, s) in theirs.indexed) ...[
                  if (i > 0) Divider(height: 1, indent: 56, color: line),
                  _settleRow(context, trip, s),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: SectionHeader(title: 'Expenses (${involved.length})'),
        ),
        if (involved.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('Nothing yet.', style: TextStyle(color: muted))),
          )
        else
          Container(
            decoration: cardDecoration(),
            child: Column(
              children: [
                for (final (i, e) in involved.indexed) ...[
                  if (i > 0) Divider(height: 1, indent: 64, color: line),
                  _expenseRow(context, trip, member, e),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _settleRow(BuildContext context, Trip trip, Settlement s) {
    final pays = s.fromUserId == memberId;
    final otherId = pays ? s.toUserId : s.fromUserId;
    final other = (otherId == null ? null : trip.member(otherId)) ??
        TripMember(id: otherId ?? '', name: pays ? s.toUser : s.fromUser);
    return InkWell(
      onTap: otherId == null ? null : () => openMember(context, trip.id, otherId),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            MemberAvatar.of(other, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                pays ? 'Pays ${_firstName(other.name)}' : 'Gets from ${_firstName(other.name)}',
                style: TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w500),
              ),
            ),
            Text(
              money(s.amount),
              style: TextStyle(color: pays ? negative : positive, fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  Widget _expenseRow(BuildContext context, Trip trip, TripMember member, TripExpense e) {
    final paid = e.paidBy == member.id;
    final share = e.shareOf(member.id);
    final city = cityFromLocation(e.location);
    return InkWell(
      onTap: () => openExpense(context, trip.id, e.id, initial: e),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        child: Row(
          children: [
            IconCircle(icon: e.icon, color: colorForCategory(e.category), size: 38, outlined: true),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [formatDateTime(e.dateTime), if (city != null) city].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  paid ? 'paid ${money(e.amount)}' : 'share ${money(share)}',
                  style: TextStyle(color: paid ? ink : negative, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                if (paid && share > 0)
                  Text('share ${money(share)}', style: TextStyle(color: muted, fontSize: 11.5)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {this.align = TextAlign.right});
  final String text;
  final TextAlign align;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: align,
    style: TextStyle(color: muted, fontSize: 10, letterSpacing: .8, fontWeight: FontWeight.w700),
  );
}

class _Num extends StatelessWidget {
  const _Num(this.text, {this.color, this.bold = false});
  final String text;
  final Color? color;
  final bool bold;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.right,
    maxLines: 1,
    overflow: TextOverflow.fade,
    softWrap: false,
    style: TextStyle(
      color: color ?? ink,
      fontSize: 12.5,
      fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
    ),
  );
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: TextStyle(color: muted, fontSize: 11)),
      const SizedBox(height: 2),
      Text(
        value,
        style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]),
      ),
    ],
  );
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    decoration: cardDecoration(),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: muted, fontSize: 11.5)),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: color ?? ink, fontSize: 17, fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()]),
        ),
      ],
    ),
  );
}
