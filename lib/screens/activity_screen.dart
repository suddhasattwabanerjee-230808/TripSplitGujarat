import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../widgets.dart';

/// The bell's feed: expenses added on any of the user's trips, newest first.
/// Opening it marks everything read.
class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key, this.onOpenTrip});
  final void Function(String tripId)? onOpenTrip;

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  final _store = TripStore.instance;

  /// Which items were unread when the screen opened (they keep their dot).
  late final Set<String> _fresh = {
    for (final a in _store.activity)
      if (_store.isUnread(a)) a.expenseId,
  };

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
    _store.markActivitySeen();
  }

  @override
  void dispose() {
    _store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final items = _store.activity;
    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(
        backgroundColor: paper,
        surfaceTintColor: paper,
        title: const Text('Notifications', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        color: accent,
        onRefresh: () async {
          await _store.refresh();
          await _store.markActivitySeen();
        },
        child: items.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(child: IconCircle(icon: Icons.notifications_none_rounded, size: 64)),
                  SizedBox(height: 14),
                  Center(
                    child: Text('No activity yet', style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                  SizedBox(height: 4),
                  Center(
                    child: Text(
                      'When someone adds an expense, it shows up here.',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _item(items[i]),
              ),
      ),
    );
  }

  Widget _item(ActivityItem a) {
    final me = ApiClient.instance.currentUser?.id;
    final mine = a.paidBy == me;
    final settlement = a.category == settlementCategory;
    final who = mine ? 'You' : a.paidByName;
    final String text;
    if (settlement) {
      text = a.myShare > 0 ? '$who paid you back ${money(a.amount)}' : '$who settled up ${money(a.amount)}';
    } else {
      text = '$who added “${a.description}”';
    }
    final double impact = settlement ? 0 : (mine ? a.amount - a.myShare : -a.myShare);
    final trip = _store.trips?.where((t) => t.id == a.tripId).firstOrNull;
    final payer = trip?.member(a.paidBy);
    return AppCard(
      onTap: widget.onOpenTrip == null
          ? null
          : () {
              Navigator.pop(context);
              widget.onOpenTrip!(a.tripId);
            },
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              payer != null ? MemberAvatar.of(payer, size: 38) : MemberAvatar(id: a.paidBy, name: a.paidByName, size: 38),
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: IconCircle(icon: iconForCategory(a.category), color: colorForCategory(a.category), size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w500, height: 1.3),
                ),
                const SizedBox(height: 3),
                Text(
                  '${a.tripName} · ${timeAgo(a.createdAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (impact.abs() >= 0.5) AmountPill(value: impact, fontSize: 11.5) else Text(money(a.amount), style: const TextStyle(color: muted, fontSize: 12)),
              if (_fresh.contains(a.expenseId))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: accent, shape: BoxShape.circle)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
