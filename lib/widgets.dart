import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api_client.dart';
import 'models.dart';
import 'theme.dart';
import 'trip_store.dart';
import 'upi_pay.dart';

/// Google serves profile photos at any size; ask for one sharp at [size].
String? sizedPhoto(String? url, double size) {
  if (url == null) return null;
  final px = (size * 3).round();
  return url.contains(RegExp(r'=s\d+-c$')) ? url.replaceFirst(RegExp(r'=s\d+-c$'), '=s$px-c') : url;
}

/// Anyone's profile photo, or their initials on their member colour.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.id,
    required this.name,
    this.photoUrl,
    this.size = 32,
    this.ring = 0,
  });

  MemberAvatar.of(TripMember member, {Key? key, double size = 32, double ring = 0})
    : this(key: key, id: member.id, name: member.name, photoUrl: member.photoUrl, size: size, ring: ring);

  final int id;
  final String name;
  final String? photoUrl;
  final double size;

  /// A white ring around the photo, so overlapping stacks read as separate faces.
  final double ring;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    // Small faces overlap in stacks; one letter stays readable there.
    if (size < 30 || parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      alignment: Alignment.center,
      color: colorForMember(id),
      child: Text(
        _initials,
        style: TextStyle(color: Colors.white, fontSize: size * (size < 30 ? .44 : .36), fontWeight: FontWeight.w700),
      ),
    );
    final photo = sizedPhoto(photoUrl, size);
    final avatar = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: photo == null
            ? fallback
            : Image.network(
                photo,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
                frameBuilder: (_, child, frame, sync) => AnimatedOpacity(
                  opacity: sync || frame != null ? 1 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: child,
                ),
              ),
      ),
    );
    if (ring == 0) return avatar;
    return Container(
      padding: EdgeInsets.all(ring),
      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
      child: avatar,
    );
  }
}

/// Overlapping faces, with a "+N" disc when there are more than [max].
class AvatarStack extends StatelessWidget {
  const AvatarStack({super.key, required this.members, this.size = 26, this.max = 4});
  final List<TripMember> members;
  final double size;
  final int max;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(max).toList();
    final extra = members.length - shown.length;
    final outer = size + 4; // avatar + 2px ring each side
    final step = size * .62;
    final count = shown.length + (extra > 0 ? 1 : 0);
    if (count == 0) return const SizedBox.shrink();
    return SizedBox(
      width: outer + step * (count - 1),
      height: outer,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(left: step * i, child: MemberAvatar.of(shown[i], size: size, ring: 2)),
          if (extra > 0)
            Positioned(
              left: step * shown.length,
              child: Container(
                width: outer,
                height: outer,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accentSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Text(
                  '+$extra',
                  style: TextStyle(color: accent, fontSize: size * .36, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A money amount in a soft green (owed) / red (owe) / grey (settled) pill.
class AmountPill extends StatelessWidget {
  const AmountPill({super.key, required this.value, this.signed = true, this.fontSize = 13});

  /// Positive = in the user's favour.
  final double value;
  final bool signed;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final settled = value.abs() < 0.5;
    final color = settled ? muted : (value > 0 ? positive : negative);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: fontSize * .7, vertical: fontSize * .25),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(40),
      ),
      child: Text(
        settled ? 'Settled' : (signed ? signedMoney(value) : money(value.abs())),
        style: TextStyle(
          color: color,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

/// A thin-outline icon inside a soft tinted circle.
class IconCircle extends StatelessWidget {
  const IconCircle({super.key, required this.icon, this.color = accent, this.size = 40, this.outlined = false});
  final IconData icon;
  final Color color;
  final double size;

  /// An outlined ring instead of a tinted fill (used for expense categories).
  final bool outlined;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: outlined ? Colors.white : color.withValues(alpha: .12),
      shape: BoxShape.circle,
      border: outlined ? Border.all(color: color.withValues(alpha: .35), width: 1.2) : null,
    ),
    child: Icon(icon, color: color, size: size * .48),
  );
}

/// "Your splits                  See all ↗"
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: const TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w700)),
      ),
      if (action != null)
        InkWell(
          onTap: onAction,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action!, style: const TextStyle(color: accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(width: 2),
                const Icon(Icons.north_east_rounded, color: accent, size: 14),
              ],
            ),
          ),
        ),
    ],
  );
}

/// A white outlined card that ripples when tapped.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.onTap, this.onLongPress, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cardRadius),
      side: const BorderSide(color: line),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(padding: padding, child: child),
    ),
  );
}

/// The standard bottom sheet: handle, title, scrolling content.
Future<T?> showAppSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<Widget> Function(BuildContext) children,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (context) => Container(
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .88),
    decoration: const BoxDecoration(
      color: paper,
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SheetHandle(),
            const SizedBox(height: 16),
            Text(title, style: const TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -.3)),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle, style: const TextStyle(color: muted, fontSize: 12.5)),
            ],
            const SizedBox(height: 14),
            ...children(context),
          ],
        ),
      ),
    ),
  ),
);

class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 38,
      height: 4,
      decoration: BoxDecoration(color: const Color(0xFFD5D8E2), borderRadius: BorderRadius.circular(4)),
    ),
  );
}

/// Rows inside one outlined card, split by hairlines.
Widget groupedCard(List<Widget> rows, {double indent = 0}) => Container(
  clipBehavior: Clip.antiAlias,
  decoration: cardDecoration(),
  child: Column(
    children: [
      for (var i = 0; i < rows.length; i++) ...[
        if (i > 0) Divider(height: 1, indent: indent, color: line),
        rows[i],
      ],
    ],
  ),
);

ButtonStyle primaryButton({double radius = 14}) => FilledButton.styleFrom(
  backgroundColor: accent,
  foregroundColor: Colors.white,
  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
);

ButtonStyle secondaryButton({Color color = ink, double radius = 14}) => OutlinedButton.styleFrom(
  foregroundColor: color,
  backgroundColor: Colors.white,
  side: const BorderSide(color: line),
  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
  textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
);

// --- Pay now ------------------------------------------------------------------

/// Pays [debt] through a UPI app when the other person has a UPI ID, then
/// records it as a settle-up payment so the balances update. Returns true if
/// a payment was recorded.
Future<bool> payDebt(BuildContext context, Debt debt) async {
  final other = debt.other;
  final upiId = other?.upiId;
  final messenger = ScaffoldMessenger.of(context);
  if (debt.otherId == null) {
    messenger.showSnackBar(const SnackBar(content: Text('Refresh and try again — the server is still updating.')));
    return false;
  }

  String method = 'UPI';
  if (upiId == null) {
    final choice = await showAppSheet<String>(
      context,
      title: 'Pay ${debt.otherName}',
      subtitle: '${debt.otherName} hasn’t added a UPI ID yet. Pay another way, then mark it paid here.',
      children: (ctx) => [
        _payAmountCard(debt),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, 'Cash'),
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('I paid in cash'),
            style: primaryButton(),
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => Navigator.pop(ctx, 'UPI'),
            icon: const Icon(Icons.qr_code_2_outlined, size: 18),
            label: const Text('I paid by UPI another way'),
            style: secondaryButton(),
          ),
        ),
      ],
    );
    if (choice == null) return false;
    method = choice;
  } else {
    final status = await UpiPay.pay(
      upiId: upiId,
      name: debt.otherName,
      amount: debt.amount,
      note: 'TripSplit · ${debt.trip.name}',
    );
    if (!context.mounted) return false;
    switch (status) {
      case UpiPayStatus.noApp:
        await Clipboard.setData(ClipboardData(text: upiId));
        messenger.showSnackBar(SnackBar(content: Text('No UPI app found. $upiId copied — pay from any app.')));
        return false;
      case UpiPayStatus.failed:
        messenger.showSnackBar(const SnackBar(content: Text('The payment didn’t go through.')));
        return false;
      case UpiPayStatus.unknown:
        final paid = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            title: const Text('Did the payment go through?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            content: Text(
              'If you paid ${money(debt.amount)} to ${debt.otherName}, mark it paid so everyone’s balance updates.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not yet')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), style: primaryButton(radius: 12), child: const Text('Mark paid')),
            ],
          ),
        );
        if (paid != true) return false;
      case UpiPayStatus.success:
        break;
    }
  }

  try {
    await ApiClient.instance.recordPayment(
      tripId: debt.trip.id,
      toUserId: debt.otherId!,
      amount: debt.amount,
      method: method,
    );
    messenger.showSnackBar(SnackBar(content: Text('Paid ${money(debt.amount)} to ${debt.otherName} — balances updated.')));
    await TripStore.instance.refresh();
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

Widget _payAmountCard(Debt debt) => Container(
  padding: const EdgeInsets.all(14),
  decoration: cardDecoration(),
  child: Row(
    children: [
      if (debt.other != null) MemberAvatar.of(debt.other!, size: 38) else const IconCircle(icon: Icons.person_outline),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(debt.otherName, style: const TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w700)),
            Text(debt.trip.name, style: const TextStyle(color: muted, fontSize: 12)),
          ],
        ),
      ),
      Text(money(debt.amount), style: const TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w700)),
    ],
  ),
);

/// One "You owe X ₹N  [Pay]" / "X owes you ₹N" row.
class DebtRow extends StatelessWidget {
  const DebtRow({super.key, required this.debt, this.showTrip = false, this.onPaid});
  final Debt debt;
  final bool showTrip;
  final VoidCallback? onPaid;

  @override
  Widget build(BuildContext context) {
    final other = debt.other;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
      child: Row(
        children: [
          if (other != null)
            MemberAvatar.of(other, size: 34)
          else
            MemberAvatar(id: debt.otherId ?? 0, name: debt.otherName, size: 34),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  debt.iOwe ? 'You owe ${debt.otherName}' : '${debt.otherName} owes you',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    AmountPill(value: debt.iOwe ? -debt.amount : debt.amount, signed: false, fontSize: 11.5),
                    if (showTrip) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          debt.trip.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: muted, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (debt.iOwe)
            FilledButton(
              onPressed: () async {
                if (await payDebt(context, debt)) onPaid?.call();
              },
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Pay', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ),
    );
  }
}
