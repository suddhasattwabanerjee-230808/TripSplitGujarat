import 'package:flutter/material.dart';

// --- Palette ------------------------------------------------------------------
// A bright, airy look: light grey page, white outlined cards, one blue accent,
// and green / red kept for money only.

const paper = Color(0xFFF5F6FA); // page background
const ink = Color(0xFF171A26); // primary text
const muted = Color(0xFF7B8193); // secondary text, inactive icons
const line = Color(0xFFE6E8EF); // card outlines and dividers
const accent = Color(0xFF4C5FE0); // links, selection, primary actions
const accentSoft = Color(0xFFECEEFD); // tinted backgrounds behind accent icons
const positive = Color(0xFF168A4A); // you are owed / you lent
const negative = Color(0xFFD93848); // you owe / you borrowed
const accentGlow = Color(0xFFB4BEFF); // highlights on dark surfaces (splash, profile header)

const cardRadius = 16.0;

const memberPalette = [
  Color(0xFFE1A64B),
  Color(0xFF5FA897),
  Color(0xFF9A7CC4),
  Color(0xFFD1735A),
  Color(0xFF5E8ED1),
  Color(0xFFC77FB4),
  Color(0xFF7DAA5C),
  Color(0xFFD69A57),
];

Color colorForMember(int index) => memberPalette[index % memberPalette.length];

/// A soft shadow for the few surfaces that float (FAB, nav bar, pop-ups);
/// cards use a 1px [line] outline instead.
List<BoxShadow> softShadow([Color tint = ink, double opacity = .07]) => [
  BoxShadow(color: tint.withValues(alpha: opacity), blurRadius: 16, offset: const Offset(0, 5)),
];

/// The standard white card: outlined, no shadow.
BoxDecoration cardDecoration({Color color = Colors.white, double radius = cardRadius}) => BoxDecoration(
  color: color,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: line),
);

// --- Expense categories ---------------------------------------------------------

/// The built-in categories, in the order the pickers show them.
const categoryOrder = [
  'Food',
  'Groceries',
  'Stay',
  'Rent',
  'Transport',
  'Fuel',
  'Shopping',
  'Utilities',
  'Activities',
  'Other',
];

/// Settle-up payments are stored as expenses in this category (one payer, one
/// share), so they move balances but stay out of spending totals and charts.
const settlementCategory = 'Settlement';

const _categoryIcons = {
  'Food': Icons.restaurant_outlined,
  'Groceries': Icons.shopping_basket_outlined,
  'Stay': Icons.hotel_outlined,
  'Rent': Icons.home_outlined,
  'Transport': Icons.directions_car_outlined,
  'Fuel': Icons.local_gas_station_outlined,
  'Shopping': Icons.shopping_bag_outlined,
  'Utilities': Icons.bolt_outlined,
  'Activities': Icons.local_activity_outlined,
  'Other': Icons.more_horiz_rounded,
  settlementCategory: Icons.handshake_outlined,
};

const _categoryColors = {
  'Food': Color(0xFFD9692E),
  'Groceries': Color(0xFF2E9465),
  'Stay': Color(0xFF4F74CC),
  'Rent': Color(0xFF7F5BC8),
  'Transport': Color(0xFF2585AE),
  'Fuel': Color(0xFFBA6A1E),
  'Shopping': Color(0xFFC94F80),
  'Utilities': Color(0xFFA88A10),
  'Activities': Color(0xFF6E55CF),
  'Other': muted,
  settlementCategory: positive,
};

bool isBuiltInCategory(String? category) => _categoryIcons.containsKey(category);

/// Custom categories (anything the user typed) get a tag icon.
IconData iconForCategory(String? category) =>
    _categoryIcons[category] ?? (category == null ? Icons.more_horiz_rounded : Icons.sell_outlined);

Color colorForCategory(String? category) =>
    _categoryColors[category] ??
    (category == null ? muted : memberPalette[category.hashCode.abs() % memberPalette.length]);

// --- Trip kinds -------------------------------------------------------------------

class TripKind {
  const TripKind(this.id, this.label, this.icon, this.color);
  final String id;
  final String label;
  final IconData icon;
  final Color color;
}

const tripKinds = [
  TripKind('trip', 'Trip', Icons.luggage_outlined, Color(0xFF4C5FE0)),
  TripKind('vacation', 'Vacation', Icons.beach_access_outlined, Color(0xFF2585AE)),
  TripKind('roommates', 'Roommates', Icons.groups_outlined, Color(0xFFC94F80)),
  TripKind('friends', 'Friends', Icons.diversity_3_outlined, Color(0xFF2E9465)),
  TripKind('couple', 'Couple', Icons.favorite_border_rounded, Color(0xFFD93848)),
  TripKind('event', 'Event', Icons.celebration_outlined, Color(0xFFD9692E)),
  TripKind('other', 'Other', Icons.category_outlined, Color(0xFF7F5BC8)),
];

/// Trips made before kinds existed (kind == null) count as a plain trip.
TripKind tripKindFor(String? id) =>
    tripKinds.firstWhere((k) => k.id == id, orElse: () => tripKinds.first);

// --- Places -----------------------------------------------------------------------

/// Expense locations are stored as "area, city" (or just "city" if that's
/// all reverse-geocoding returned) — the city is always the last segment.
String? cityFromLocation(String? location) {
  if (location == null || location.trim().isEmpty) return null;
  final parts = location.split(',');
  final city = parts.last.trim();
  return city.isEmpty ? null : city;
}

Color colorForCity(String city) => memberPalette[city.hashCode.abs() % memberPalette.length];

// --- Formatting ---------------------------------------------------------------------

String money(double value) =>
    '₹${value.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')}';

/// "+₹50" / "-₹50" for balance pills.
String signedMoney(double value) => '${value < 0 ? '-' : '+'}${money(value.abs())}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String shortMonth(int month) => _months[month - 1];

String _time(DateTime dt) {
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  return '$hour12:$minute ${dt.hour >= 12 ? 'PM' : 'AM'}';
}

String formatDateTime(DateTime dt) {
  final now = DateTime.now();
  final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final yesterday = now.subtract(const Duration(days: 1));
  final isYesterday =
      dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day;
  if (isToday) return 'Today, ${_time(dt)}';
  if (isYesterday) return 'Yesterday, ${_time(dt)}';
  return '${dt.day} ${_months[dt.month - 1]}, ${_time(dt)}';
}

/// "Sep 19, 2024"
String formatDate(DateTime dt) => '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';

/// "19/09/2024 · 8:50 PM"
String formatDateAndTime(DateTime dt) =>
    '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} · ${_time(dt)}';

/// "just now", "5m ago", "3h ago", "2d ago", then a date.
String timeAgo(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return formatDate(dt);
}

// --- Inputs -----------------------------------------------------------------------

InputDecoration appInputDecoration(String hint, IconData icon) =>
    InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 18, color: muted),
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: Color(0xFFA9AEBC), fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: accent, width: 1.3),
      ),
    );

Widget fieldLabel(String text) => Text(
  text,
  style: const TextStyle(
    color: muted,
    fontSize: 10,
    letterSpacing: 1,
    fontWeight: FontWeight.w700,
  ),
);

/// A member's colour from their id (stable across launches and devices).
Color colorForId(String id) {
  var hash = 0x811c9dc5;
  for (final unit in id.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
  }
  return colorForMember(hash);
}
