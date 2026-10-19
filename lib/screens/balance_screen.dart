import 'package:flutter/material.dart';

import '../theme.dart';
import '../trip_store.dart';
import '../widgets.dart';

/// The Balance tab: who owes whom across every trip, with "Pay" on each of
/// the user's debts.
class BalanceScreen extends StatefulWidget {
  const BalanceScreen({super.key, this.onOpenTrip});
  final void Function(int tripId)? onOpenTrip;

  @override
  State<BalanceScreen> createState() => _BalanceScreenState();
}

class _BalanceScreenState extends State<BalanceScreen> {
  final _store = TripStore.instance;

  @override
  void initState() {
    super.initState();
    _store.addListener(_onStore);
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
    final totals = _store.totals;
    final net = totals.owed - totals.owing;
    final debts = _store.debts;
    final iOwe = debts.where((d) => d.iOwe).toList();
    final owedToMe = debts.where((d) => !d.iOwe).toList();
    final trips = _store.trips ?? const [];
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: accent,
        onRefresh: _store.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 12),
              child: Text('Balance', style: TextStyle(color: ink, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -.5)),
            ),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const IconCircle(icon: Icons.account_balance_outlined, size: 40),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Net balance', style: TextStyle(color: muted, fontSize: 13, fontWeight: FontWeight.w500)),
                      ),
                      AmountPill(value: net, fontSize: 15),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(child: _stat('You are owed', totals.owed, positive)),
                      Container(width: 1, height: 34, color: line),
                      const SizedBox(width: 14),
                      Expanded(child: _stat('You owe', totals.owing, negative)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_store.trips == null)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator(color: accent)),
              )
            else if (debts.isEmpty)
              _allSettled()
            else ...[
              if (iOwe.isNotEmpty) ...[
                const SectionHeader(title: 'You owe'),
                const SizedBox(height: 8),
                groupedCard([for (final d in iOwe) DebtRow(debt: d, showTrip: true)], indent: 60),
                const SizedBox(height: 20),
              ],
              if (owedToMe.isNotEmpty) ...[
                const SectionHeader(title: 'Owed to you'),
                const SizedBox(height: 8),
                groupedCard([for (final d in owedToMe) DebtRow(debt: d, showTrip: true)], indent: 60),
                const SizedBox(height: 20),
              ],
            ],
            if (trips.isNotEmpty) ...[
              const SectionHeader(title: 'By trip'),
              const SizedBox(height: 8),
              groupedCard([
                for (final t in trips)
                  InkWell(
                    onTap: widget.onOpenTrip == null ? null : () => widget.onOpenTrip!(t.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      child: Row(
                        children: [
                          IconCircle(icon: t.tripKind.icon, color: t.tripKind.color, size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              t.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (_store.myNet(t.id) != null) AmountPill(value: _store.myNet(t.id)!, fontSize: 12),
                        ],
                      ),
                    ),
                  ),
              ], indent: 62),
            ],
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, double value, Color color) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: muted, fontSize: 12)),
      const SizedBox(height: 2),
      Text(
        money(value),
        style: TextStyle(
          color: value < 0.5 ? ink : color,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );

  Widget _allSettled() => Container(
    padding: const EdgeInsets.all(16),
    margin: const EdgeInsets.only(bottom: 20),
    decoration: cardDecoration(),
    child: const Row(
      children: [
        IconCircle(icon: Icons.check_circle_outline_rounded, color: positive, size: 40),
        SizedBox(width: 12),
        Expanded(
          child: Text(
            'You’re all settled up on every trip.',
            style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    ),
  );
}
