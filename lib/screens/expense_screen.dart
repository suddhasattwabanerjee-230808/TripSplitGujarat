import 'package:flutter/material.dart';

import '../api_client.dart';
import '../models.dart';
import '../theme.dart';
import '../trip_store.dart';
import '../widgets.dart';
import 'trip_people.dart';

/// Opens one expense, read-only (from a notification or a person's page).
void openExpense(BuildContext context, String tripId, String expenseId, {TripExpense? initial}) =>
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ExpenseScreen(tripId: tripId, expenseId: expenseId, initial: initial)),
    );

/// One expense, read-only and live: who paid (with their photo), how much,
/// what for, when and where, and how it's split. Changes are made from the
/// trip itself, by whoever paid.
class ExpenseScreen extends StatelessWidget {
  const ExpenseScreen({super.key, required this.tripId, required this.expenseId, this.initial});
  final String tripId;
  final String expenseId;
  final TripExpense? initial;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paper,
    appBar: AppBar(
      actions: const [ThemeToggle()],
      backgroundColor: paper,
      surfaceTintColor: paper,
      title: const Text('Expense', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    ),
    body: StreamBuilder<TripExpense?>(
      stream: ApiClient.instance.watchExpense(tripId, expenseId),
      initialData: initial,
      builder: (context, snap) {
        final expense = snap.data;
        if (expense == null) {
          return snap.connectionState == ConnectionState.waiting || snap.connectionState == ConnectionState.none
              ? Center(child: CircularProgressIndicator(color: accent))
              : Center(child: Text('This expense was deleted.', style: TextStyle(color: muted)));
        }
        return ListenableBuilder(
          listenable: TripStore.instance,
          builder: (context, _) => _body(context, expense),
        );
      },
    ),
  );

  Widget _body(BuildContext context, TripExpense e) {
    final trip = TripStore.instance.trips?.where((t) => t.id == tripId).firstOrNull;
    final me = ApiClient.instance.currentUser?.id;
    final payer = trip?.member(e.paidBy) ?? TripMember(id: e.paidBy, name: e.payerName(trip));
    final catColor = colorForCategory(e.category);
    String name(String id) => id == me ? 'You' : (trip?.member(id)?.name ?? 'Someone');
    final myShare = e.shareOf(me ?? '');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // Who paid and how much: the photo with the category as a badge.
        Container(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 18),
          decoration: cardDecoration(),
          child: Column(
            children: [
              GestureDetector(
                onTap: () => openMember(context, tripId, payer.id),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    MemberAvatar.of(payer, size: 76, ring: 3),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: surface,
                          shape: BoxShape.circle,
                          border: Border.all(color: line),
                        ),
                        child: Icon(e.icon, size: 16, color: catColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                e.isSettlement
                    ? '${name(e.paidBy)} Paid Back ${e.shares.isEmpty ? '' : name(e.shares.first.userId)}'
                    : '${name(e.paidBy)} Paid',
                style: TextStyle(color: muted, fontSize: 13.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                money(e.amount),
                style: TextStyle(color: ink, fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: -1),
              ),
              const SizedBox(height: 4),
              Text(
                e.description,
                textAlign: TextAlign.center,
                style: TextStyle(color: ink, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (!e.isSettlement && myShare > 0 && e.paidBy != me) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: negative.withValues(alpha: .08), borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    'Your Share ${money(myShare)}',
                    style: TextStyle(color: negative, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          decoration: cardDecoration(),
          child: Column(
            children: [
              _info(Icons.sell_outlined, 'Category', e.isSettlement ? 'Settle-Up Payment' : (e.category ?? 'Other'), catColor),
              Divider(height: 1, indent: 50, color: line),
              _info(Icons.schedule_outlined, 'When', formatDateAndTime(e.dateTime), accent),
              Divider(height: 1, indent: 50, color: line),
              _info(Icons.location_on_outlined, 'Where', e.location ?? 'No Location', accent),
              if (trip != null) ...[
                Divider(height: 1, indent: 50, color: line),
                _info(trip.tripKind.icon, 'Trip', trip.name, trip.tripKind.color),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 10),
          child: SectionHeader(title: e.isSettlement ? 'Paid To' : 'Split Between ${e.shares.length}'),
        ),
        Container(
          decoration: cardDecoration(),
          child: Column(
            children: [
              for (final (i, s) in e.shares.indexed) ...[
                if (i > 0) Divider(height: 1, indent: 58, color: line),
                InkWell(
                  onTap: () => openMember(context, tripId, s.userId),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    child: Row(
                      children: [
                        MemberAvatar.of(
                          trip?.member(s.userId) ?? TripMember(id: s.userId, name: name(s.userId)),
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            name(s.userId),
                            style: TextStyle(
                              color: ink,
                              fontSize: 14,
                              fontWeight: s.userId == me ? FontWeight.w800 : FontWeight.w500,
                            ),
                          ),
                        ),
                        Text(
                          money(s.shareAmount),
                          style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (e.paidBy != me) ...[
          const SizedBox(height: 12),
          Text(
            'Only ${name(e.paidBy)} can change this expense.',
            textAlign: TextAlign.center,
            style: TextStyle(color: muted, fontSize: 12),
          ),
        ],
      ],
    );
  }

  Widget _info(IconData icon, String label, String value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: muted, fontSize: 11.5)),
              const SizedBox(height: 1),
              Text(value, style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    ),
  );
}
