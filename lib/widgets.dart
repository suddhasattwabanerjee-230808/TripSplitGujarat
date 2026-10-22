import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_fonts.dart';
import 'api_client.dart';
import 'expense_notifier.dart';
import 'models.dart';
import 'theme.dart';
import 'trip_store.dart';
import 'screens/trip_people.dart';
import 'settle_watch.dart';
import 'upi_pay.dart';
import 'upi_qr.dart';

/// Google serves profile photos at any size; ask for one sharp at [size].
String? sizedPhoto(String? url, double size) {
  if (url == null) return null;
  final px = (size * 3).round();
  return url.contains(RegExp(r'=s\d+-c$')) ? url.replaceFirst(RegExp(r'=s\d+-c$'), '=s$px-c') : url;
}

/// The light/dark switch at the top of every screen: a sun or a moon that
/// turns as it flips.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key, this.color});

  /// Defaults to [ink]; white over the dark profile header.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.instance.dark;
    return IconButton(
      tooltip: dark ? 'Light Theme' : 'Dark Theme',
      onPressed: AppTheme.instance.toggle,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, animation) => RotationTransition(
          turns: Tween(begin: .6, end: 1.0).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutBack)),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          key: ValueKey(dark),
          color: color ?? ink,
          size: 22,
        ),
      ),
    );
  }
}

final _embedded = <String, Uint8List>{};

/// A profile photo: a web address (Google's), or a `data:` URI for one the user
/// picked themselves (stored in Firestore, as the free plan has no Storage).
/// Shows [fallback] while it can't be drawn.
Widget profilePhoto(String url, Widget fallback) {
  Widget fade(BuildContext _, Widget child, int? frame, bool sync) => AnimatedOpacity(
    opacity: sync || frame != null ? 1 : 0,
    duration: const Duration(milliseconds: 250),
    child: child,
  );
  if (url.startsWith('data:')) {
    // Decoded once per photo, so every rebuild reuses the same bytes.
    final bytes = _embedded[url] ??= () {
      if (_embedded.length > 64) _embedded.clear();
      try {
        return base64Decode(url.substring(url.indexOf(',') + 1));
      } catch (_) {
        return Uint8List(0);
      }
    }();
    if (bytes.isEmpty) return fallback;
    return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => fallback);
  }
  return Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback, frameBuilder: fade);
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
    this.ringColor,
    this.tripId,
  });

  MemberAvatar.of(TripMember member, {Key? key, double size = 32, double ring = 0, Color? ringColor, String? tripId})
    : this(
        key: key,
        id: member.id,
        name: member.name,
        photoUrl: member.photoUrl,
        size: size,
        ring: ring,
        ringColor: ringColor,
        tripId: tripId,
      );

  /// When set, tapping the face opens this person's page on that trip.
  final String? tripId;

  final String id;
  final String name;
  final String? photoUrl;
  final double size;

  /// A white ring around the photo, so overlapping stacks read as separate faces.
  final double ring;

  /// The ring's colour; defaults to [surface].
  final Color? ringColor;

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
      color: colorForId(id),
      child: Text(
        _initials,
        style: TextStyle(color: Colors.white, fontSize: size * (size < 30 ? .44 : .36), fontWeight: FontWeight.w700),
      ),
    );
    final photo = sizedPhoto(photoUrl, size);
    final avatar = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: photo == null ? fallback : profilePhoto(photo, fallback),
      ),
    );
    final face = ring == 0
        ? avatar
        : Container(
            padding: EdgeInsets.all(ring),
            decoration: BoxDecoration(color: ringColor ?? surface, shape: BoxShape.circle),
            child: avatar,
          );
    final trip = tripId;
    if (trip == null || id.isEmpty) return face;
    return GestureDetector(onTap: () => openMember(context, trip, id), child: face);
  }
}

/// Overlapping faces, with a "+N" disc when there are more than [max].
class AvatarStack extends StatelessWidget {
  const AvatarStack({
    super.key,
    required this.members,
    this.size = 26,
    this.max = 4,
    this.ringColor,
    this.extraColor,
    this.extraTextColor,
  });
  final List<TripMember> members;
  final double size;
  final int max;

  /// For stacks on a coloured surface (the trip card): the rings, and the
  /// "+N" disc's fill and text. Default to [surface], [accentSoft], [accent].
  final Color? ringColor, extraColor, extraTextColor;

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
            Positioned(left: step * i, child: MemberAvatar.of(shown[i], size: size, ring: 2, ringColor: ringColor)),
          if (extra > 0)
            Positioned(
              left: step * shown.length,
              child: Container(
                width: outer,
                height: outer,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: extraColor ?? accentSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor ?? surface, width: 2),
                ),
                child: Text(
                  '+$extra',
                  style: TextStyle(color: extraTextColor ?? accent, fontSize: size * .36, fontWeight: FontWeight.w700),
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
  const IconCircle({super.key, required this.icon, this.color, this.size = 40, this.outlined = false});
  final IconData icon;

  /// Defaults to [accent].
  final Color? color;
  final double size;

  /// An outlined ring instead of a tinted fill (used for expense categories).
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: outlined ? surface : color.withValues(alpha: .12),
        shape: BoxShape.circle,
        border: outlined ? Border.all(color: color.withValues(alpha: .35), width: 1.2) : null,
      ),
      child: Icon(icon, color: color, size: size * .48),
    );
  }
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
        child: Text(title, style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w700)),
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
                Text(action!, style: TextStyle(color: accent, fontSize: 12.5, fontWeight: FontWeight.w600)),
                const SizedBox(width: 2),
                Icon(Icons.north_east_rounded, color: accent, size: 14),
              ],
            ),
          ),
        ),
    ],
  );
}

/// A white outlined card that ripples when tapped.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.all(14),
    this.selected = false,
  });
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;

  /// Outlined in the accent colour (e.g. the trip currently shown).
  final bool selected;

  @override
  Widget build(BuildContext context) => Material(
    color: surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(cardRadius),
      side: selected ? BorderSide(color: accent, width: 1.5) : BorderSide(color: line),
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
    decoration: BoxDecoration(
      color: paper,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
            Text(title, style: TextStyle(color: ink, fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -.3)),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(subtitle, style: TextStyle(color: muted, fontSize: 12.5)),
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
      decoration: BoxDecoration(color: muted.withValues(alpha: .35), borderRadius: BorderRadius.circular(4)),
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
  foregroundColor: onAccent,
  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
  textStyle: TextStyle(fontFamily: AppFonts.instance.family, fontWeight: FontWeight.w700, fontSize: 14),
);

ButtonStyle secondaryButton({Color? color, double radius = 14}) => OutlinedButton.styleFrom(
  foregroundColor: color ?? ink,
  backgroundColor: surface,
  side: BorderSide(color: line),
  padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 16),
  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
  textStyle: TextStyle(fontFamily: AppFonts.instance.family, fontWeight: FontWeight.w700, fontSize: 14),
);

// --- Pay now ------------------------------------------------------------------

/// Pays [debt] through a UPI app when the other person has a UPI ID, then
/// records it as a settle-up payment so the balances update. Returns true if
/// a payment was recorded.
/// Pay what you owe: a sheet with the UPI apps on the phone, cash, another
/// way, or a reminder for later. True once a payment was recorded.
Future<bool> payDebt(BuildContext context, Debt debt) async {
  if (debt.otherId == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Refresh and try again — the server is still updating.')),
    );
    return false;
  }
  final choice = await showAppSheet<(String, double)>(
    context,
    title: 'Pay ${debt.otherName}',
    subtitle: debt.other?.upiId == null
        ? '${debt.otherName} hasn’t added a UPI ID: pick your UPI app and scan their QR.'
        : 'Pick your UPI app: it opens on the payment to ${debt.otherName}, amount filled in.',
    children: (ctx) => [
      _payAmountCard(debt),
      const SizedBox(height: 16),
      SettleOptions(debt: debt, onChoose: (c, amount) => Navigator.pop(ctx, (c, amount))),
    ],
  );
  if (choice == null || !context.mounted) return false;
  return settleDebt(context, debt, choice.$1, amount: choice.$2);
}

/// The ways to settle [debt], as [onChoose] values: `app:<package>` (pay in
/// a UPI app), `scan:<package>` (open a UPI app's scanner on their QR),
/// `cash`, `other` (paid some other way) and `remind`, with the amount being
/// paid: all of it, or part (typed in). Shown in the Pay sheet and on a
/// balance's settle-up page.
class SettleOptions extends StatefulWidget {
  const SettleOptions({super.key, required this.debt, required this.onChoose});
  final Debt debt;
  final void Function(String choice, double amount) onChoose;

  @override
  State<SettleOptions> createState() => _SettleOptionsState();
}

class _SettleOptionsState extends State<SettleOptions> {
  Debt get debt => widget.debt;
  late final _amount = TextEditingController(text: _plain(debt.amount));

  static String _plain(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  double? get _entered => double.tryParse(_amount.text.trim().replaceAll(',', ''));

  bool get _part {
    final v = _entered;
    return v != null && v > 0 && v < debt.amount - 0.5;
  }

  /// The amount typed in, if it's a valid one (else says so, and null).
  double? _valid() {
    final v = _entered;
    if (v == null || v <= 0 || v > debt.amount + 0.5) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enter an amount up to ${money(debt.amount)}.')),
      );
      return null;
    }
    return v > debt.amount ? debt.amount : v;
  }

  /// Hands [choice] on with the amount typed in.
  void _choose(String choice) {
    if (choice == 'remind') return widget.onChoose(choice, debt.amount);
    final v = _valid();
    if (v != null) widget.onChoose(choice, v);
  }

  /// With their UPI ID the app opens on the payment, filled in; without it,
  /// on its scanner.
  String _choiceFor(UpiApp app) => debt.other?.upiId != null ? 'app:${app.package}' : 'scan:${app.package}';

  Future<void> _scan(BuildContext context) async {
    final amount = _valid();
    if (amount == null) return;
    final package = await pickUpiAppToScan(context, debt, amount);
    if (package != null) widget.onChoose('scan:$package', amount);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (debt.iOwe) ...[
        fieldLabel('AMOUNT TO PAY'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w700),
                decoration: appInputDecoration('₹  0', Icons.currency_rupee_rounded),
              ),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text('Full ${money(debt.amount)}'),
              selected: !_part,
              onSelected: (_) => setState(() => _amount.text = _plain(debt.amount)),
              selectedColor: accentSoft,
              backgroundColor: surface,
              side: BorderSide(color: !_part ? accent : line),
              labelStyle: TextStyle(color: !_part ? accent : ink, fontWeight: FontWeight.w700, fontSize: 12),
              showCheckmark: false,
            ),
          ],
        ),
        const SizedBox(height: 6),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: _part
              ? Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    'Part Payment · ${money(debt.amount - _entered!)} Stays Owed',
                    style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        const SizedBox(height: 16),
        fieldLabel('PAY WITH UPI'),
        const SizedBox(height: 10),
        FutureBuilder<List<UpiApp>>(
          future: UpiPay.apps(),
          builder: (context, snap) {
            final apps = snap.data;
            if (apps == null) {
              return SizedBox(height: 76, child: Center(child: CircularProgressIndicator(color: accent)));
            }
            if (apps.isEmpty) {
              return Text('No UPI App Found On This Phone', style: TextStyle(color: muted, fontSize: 12.5));
            }
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [for (final app in apps.take(8)) _UpiAppButton(app: app, onTap: () => _choose(_choiceFor(app)))],
            );
          },
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => _scan(context),
          icon: const Icon(Icons.qr_code_scanner_rounded, size: 18),
          label: const Text('Scan Their QR Code'),
          style: primaryButton(),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _choose('cash'),
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: const Text('I Paid In Cash'),
          style: secondaryButton(),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => _choose('other'),
          icon: const Icon(Icons.task_alt_rounded, size: 18),
          label: const Text('I Already Paid Another Way'),
          style: secondaryButton(),
        ),
        const SizedBox(height: 8),
      ],
      OutlinedButton.icon(
        onPressed: () => _choose('remind'),
        icon: const Icon(Icons.alarm_add_outlined, size: 18),
        label: Text(debt.iOwe ? 'Remind Me To Settle Later' : 'Remind Me To Follow Up'),
        style: secondaryButton(),
      ),
    ],
  );
}

/// "Scan their QR": which UPI app to open on its scanner. Google Pay and
/// PhonePe come first. The package, or null if dismissed.
Future<String?> pickUpiAppToScan(BuildContext context, Debt debt, double amount) => showAppSheet<String>(
  context,
  title: 'Scan With',
  subtitle: 'The app opens on its scanner. Point it at ${debt.otherName}’s UPI QR and pay ${money(amount)}.',
  children: (ctx) => [
    FutureBuilder<List<UpiApp>>(
      future: UpiPay.apps(),
      builder: (context, snap) {
        final apps = snap.data;
        if (apps == null) {
          return SizedBox(height: 120, child: Center(child: CircularProgressIndicator(color: accent)));
        }
        if (apps.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No UPI App Found On This Phone', style: TextStyle(color: muted, fontSize: 13))),
          );
        }
        return groupedCard([
          for (final app in apps)
            InkWell(
              onTap: () => Navigator.pop(ctx, app.package),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.memory(app.icon, width: 38, height: 38, gaplessPlayback: true),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(app.label, style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    Icon(Icons.qr_code_scanner_rounded, size: 20, color: accent),
                  ],
                ),
              ),
            ),
        ], indent: 66);
      },
    ),
  ],
);

class _UpiAppButton extends StatelessWidget {
  const _UpiAppButton({required this.app, required this.onTap});
  final UpiApp app;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(16),
    child: Container(
      width: 76,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      decoration: cardDecoration(radius: 16),
      child: Column(
        children: [
          Image.memory(app.icon, width: 36, height: 36, gaplessPlayback: true),
          const SizedBox(height: 6),
          Text(
            app.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(color: ink, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    ),
  );
}

/// Carries out a [SettleOptions] choice for [debt]. True once a payment was
/// recorded (a reminder isn't one). A payment made in a UPI app is confirmed
/// from the bank's SMS by [SettleWatch], not asked.
Future<bool> settleDebt(BuildContext context, Debt debt, String choice, {double? amount}) async {
  final messenger = ScaffoldMessenger.of(context);
  final watch = SettleWatch.instance;
  // All of it, or the part typed in.
  final paying = amount ?? debt.amount;
  if (choice == 'remind') {
    await pickSettleReminder(context, debt);
    return false;
  }
  String method = choice == 'cash' ? 'Cash' : 'UPI';
  // Nothing to fill a payment in with: scan their QR in that app instead.
  if (choice.startsWith('app:') && debt.other?.upiId == null) choice = 'scan:${choice.substring(4)}';
  if (choice.startsWith('app:')) {
    // Their UPI ID and the amount, as a QR the app reads like a scanned one:
    // it opens on the payment, filled in. (A filled-in payment link from
    // another app to a personal UPI ID is often declined; a scanned QR
    // isn't.) The bank's SMS then confirms it.
    final package = choice.substring(4);
    final upiId = debt.other!.upiId!;
    final link = UpiPay.link(
      upiId: upiId,
      name: debt.otherName,
      amount: paying,
      // Plain ASCII: some UPI apps refuse anything else in the note.
      note: 'TripSplit ${debt.trip.name}'.replaceAll(RegExp(r'[^A-Za-z0-9 ]'), '').trim(),
    );
    await watch.start(debt, paying);
    if (await UpiPay.shareQr(package, await upiQrPng(link))) return false;
    // The app didn't take the QR: copy the UPI ID to paste there instead.
    await Clipboard.setData(ClipboardData(text: upiId));
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 6),
        content: Text('$upiId copied — in the app, choose Pay UPI ID, paste it and pay ${money(paying)}.'),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!await UpiPay.payTo(package)) {
      await watch.cancel();
      messenger.showSnackBar(SnackBar(content: Text('Couldn’t open that app. $upiId is copied — pay from any app.')));
    }
    return false;
  } else if (choice.startsWith('scan:')) {
    // Their QR: the app opens on its scanner; the bank's SMS confirms it.
    await watch.start(debt, paying);
    if (!await UpiPay.scan(choice.substring(5))) {
      await watch.cancel();
      messenger.showSnackBar(const SnackBar(content: Text('Couldn’t open that app.')));
      return false;
    }
    return false;
  }
  try {
    await ApiClient.instance.recordPayment(
      tripId: debt.trip.id,
      trip: debt.trip,
      toUserId: debt.otherId!,
      amount: paying,
      method: method,
    );
    messenger.showSnackBar(SnackBar(content: Text('Paid ${money(paying)} to ${debt.otherName} — balances updated.')));
    await TripStore.instance.refresh();
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
    return false;
  }
}

/// Asks when to be reminded about [debt] and sets the reminder. True if set.
Future<bool> pickSettleReminder(BuildContext context, Debt debt) async {
  final other = debt.other;
  if (other == null) return false;
  final now = DateTime.now();
  final day = await showDatePicker(
    context: context,
    helpText: 'Remind Me On',
    initialDate: now.add(const Duration(days: 1)),
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (day == null || !context.mounted) return false;
  final time = await showTimePicker(
    context: context,
    helpText: 'At',
    initialTime: const TimeOfDay(hour: 10, minute: 0),
  );
  if (time == null || !context.mounted) return false;
  final when = DateTime(day.year, day.month, day.day, time.hour, time.minute);
  final messenger = ScaffoldMessenger.of(context);
  if (!when.isAfter(DateTime.now())) {
    messenger.showSnackBar(const SnackBar(content: Text('Pick a time that’s still to come.')));
    return false;
  }
  try {
    await ExpenseNotifier.remindToSettle(trip: debt.trip, other: other, amount: debt.amount, iOwe: debt.iOwe, when: when);
  } on StateError {
    messenger.showSnackBar(const SnackBar(content: Text('Notifications are off. Turn on All Notifications in your profile first.')));
    return false;
  } catch (_) {
    messenger.showSnackBar(const SnackBar(content: Text('Couldn’t set the reminder. Allow notifications for TripSplit.')));
    return false;
  }
  messenger.showSnackBar(
    SnackBar(content: Text('Reminder set for ${formatDateAndTime(when)}. Tapping it opens this balance.')),
  );
  return true;
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
            Text(debt.otherName, style: TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w700)),
            Text(debt.trip.name, style: TextStyle(color: muted, fontSize: 12)),
          ],
        ),
      ),
      Text(money(debt.amount), style: TextStyle(color: ink, fontSize: 18, fontWeight: FontWeight.w700)),
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
            MemberAvatar.of(other, size: 34, tripId: debt.trip.id)
          else
            MemberAvatar(id: debt.otherId ?? '', name: debt.otherName, size: 34),
          const SizedBox(width: 12),
          Expanded(
            // The name opens their page too.
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: debt.otherId == null ? null : () => openMember(context, debt.trip.id, debt.otherId!),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  debt.iOwe ? 'You Owe ${debt.otherName}' : '${debt.otherName} Owes You',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: ink, fontSize: 13.5, fontWeight: FontWeight.w600),
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
                          style: TextStyle(color: muted, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              ),
            ),
          ),
          if (debt.iOwe)
            FilledButton(
              onPressed: () async {
                if (await payDebt(context, debt)) onPaid?.call();
              },
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: onAccent,
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Pay', style: TextStyle(fontWeight: FontWeight.w700)),
            )
          else
            // They owe you: set a reminder to follow it up.
            IconButton(
              tooltip: 'Remind Me',
              onPressed: () => pickSettleReminder(context, debt),
              icon: Icon(Icons.alarm_add_outlined, color: accent, size: 22),
            ),
        ],
      ),
    );
  }
}
