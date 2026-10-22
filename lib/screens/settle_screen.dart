import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../widgets.dart';
import 'trip_people.dart';

/// The balance between the signed-in user and [otherId] on a trip, with the
/// ways to settle it (where a settle-up reminder leads). Live: if it gets
/// settled meanwhile, it says so.
class SettleScreen extends StatelessWidget {
  const SettleScreen({super.key, required this.tripId, required this.otherId});
  final String tripId;
  final String otherId;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paper,
    appBar: AppBar(
      actions: const [ThemeToggle()],
      backgroundColor: paper,
      surfaceTintColor: paper,
      title: const Text('Settle Up', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    ),
    body: ListenableBuilder(
      listenable: TripStore.instance,
      builder: (context, _) {
        final store = TripStore.instance;
        final trip = store.trips?.where((t) => t.id == tripId).firstOrNull;
        if (trip == null) {
          return store.trips == null
              ? Center(child: CircularProgressIndicator(color: accent))
              : Center(child: Text('You’re no longer on this trip.', style: TextStyle(color: muted)));
        }
        final other = trip.member(otherId);
        final debt = store.debts.where((d) => d.trip.id == tripId && d.otherId == otherId).firstOrNull;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _hero(context, trip, other, debt),
            const SizedBox(height: 18),
            if (debt != null)
              SettleOptions(debt: debt, onChoose: (choice, amount) => settleDebt(context, debt, choice, amount: amount))
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Nothing to settle between you two right now: you’re square, or the fewest-payments plan routes it through someone else. See the trip’s Balance for the full picture.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: muted, fontSize: 13, height: 1.4),
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _hero(BuildContext context, Trip trip, TripMember? other, Debt? debt) {
    final me = ApiClient.instance.currentUser;
    final first = (other?.name ?? 'Them').trim().split(RegExp(r'\s+')).first;
    final iOwe = debt?.iOwe ?? false;
    final face = other == null ? null : MemberAvatar.of(other, size: 64, ring: 3, tripId: trip.id);
    final mine = me == null ? null : MemberAvatar(id: me.id, name: me.name, photoUrl: me.photoUrl, size: 64, ring: 3);
    // Payer on the left, the one paid on the right.
    final from = iOwe ? mine : face, to = iOwe ? face : mine;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 20),
      decoration: cardDecoration(),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (from != null) from,
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Icon(Icons.arrow_forward_rounded, color: debt == null ? muted : (iOwe ? negative : positive)),
              ),
              if (to != null) to,
            ],
          ),
          const SizedBox(height: 14),
          Text(
            debt == null ? 'All Square With $first' : (iOwe ? 'You Owe $first' : '$first Owes You'),
            style: TextStyle(color: muted, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (debt != null) ...[
            const SizedBox(height: 2),
            Text(
              money(debt.amount),
              style: TextStyle(
                color: iOwe ? negative : positive,
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
          ],
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TripDetailsScreen(tripId: trip.id))),
            child: Text(trip.name, style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
