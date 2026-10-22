import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_fonts.dart';

// --- Palette ------------------------------------------------------------------
// The brand is the logo's orange with deep wine reds. Light: a bright, airy
// look (light grey page, white outlined cards, a burnt-orange accent dark
// enough for text, green / red kept for money only). Dark: the same layout on
// a warm black with a wine undertone, cards lifted a step, the logo's own
// orange as the accent and softer money colours.
// The names below always give the current theme's colour (see AppTheme).

class Palette {
  const Palette({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.line,
    required this.accent,
    required this.accentSoft,
    required this.positive,
    required this.negative,
  });
  final Color paper, surface, ink, muted, line, accent, accentSoft, positive, negative;

  static const light = Palette(
    paper: Color(0xFFF2F3F8),
    surface: Colors.white,
    ink: Color(0xFF0F1222),
    muted: Color(0xFF6B7187),
    line: Color(0xFFE5E7EF),
    accent: Color(0xFFBA4F0C),
    accentSoft: Color(0xFFFCEDE2),
    positive: Color(0xFF0F8A4C),
    negative: Color(0xFFD7344A),
  );

  static const dark = Palette(
    paper: Color(0xFF0F0A0B),
    surface: Color(0xFF1B1315),
    ink: Color(0xFFF6EEEA),
    muted: Color(0xFFA8989A),
    line: Color(0xFF2F2225),
    accent: Color(0xFFF5831F),
    accentSoft: Color(0xFF3A2116),
    positive: Color(0xFF3CCB82),
    negative: Color(0xFFFF6E7B),
  );
}

// The brand's fixed colours, the same in both themes.
const logoOrange = Color(0xFFF5831F);
const wineDeep = Color(0xFF2A0A14);
const wine = Color(0xFF7A1A33);
const wineBright = Color(0xFF9C2A44);

/// The hero surfaces (the trip card, the profile header): deep wine through
/// wine red to the logo's orange.
const brandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [wineDeep, wine, Color(0xFFE0691A)],
  stops: [0, .58, 1],
);

/// Light or dark, remembered on the phone. The first time it follows the
/// phone's own setting. Flipping it redraws every screen in place.
class AppTheme extends ChangeNotifier {
  AppTheme._();
  static final instance = AppTheme._();
  static const _key = 'trip_split.dark_theme.v1';

  bool dark = false;
  Palette get palette => dark ? Palette.dark : Palette.light;

  Future<void> load() async {
    final saved = await SharedPreferencesAsync().getBool(_key).catchError((Object _) => null);
    dark = saved ?? WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
  }

  Future<void> toggle() async {
    dark = !dark;
    notifyListeners();
    await SharedPreferencesAsync().setBool(_key, dark).catchError((Object _) {});
  }
}

/// Material's own theme for the current palette, so dialogs, date pickers,
/// snack bars and switches match the app's colours.
ThemeData appThemeData() {
  final dark = AppTheme.instance.dark;
  final brightness = dark ? Brightness.dark : Brightness.light;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness).copyWith(
    primary: accent,
    surface: surface,
    onSurface: ink,
    outline: line,
    outlineVariant: line,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    canvasColor: paper,
    fontFamily: AppFonts.instance.family,
    dividerColor: line,
    appBarTheme: AppBarTheme(backgroundColor: paper, foregroundColor: ink, surfaceTintColor: paper),
    dialogTheme: DialogThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(color: surface, surfaceTintColor: Colors.transparent),
    datePickerTheme: DatePickerThemeData(backgroundColor: surface, surfaceTintColor: Colors.transparent),
    timePickerTheme: TimePickerThemeData(backgroundColor: surface),
    listTileTheme: ListTileThemeData(textColor: ink, iconColor: muted),
  );
}

/// Marks every widget under [context] for rebuilding, so colours read from
/// the palette update in place (no restart, screens and input kept).
void rebuildEverything(BuildContext context) {
  void mark(Element e) {
    e.markNeedsBuild();
    e.visitChildren(mark);
  }

  (context as Element).visitChildren(mark);
}

Palette get _p => AppTheme.instance.palette;
Color get paper => _p.paper; // page background
Color get surface => _p.surface; // cards, sheets, inputs
Color get ink => _p.ink; // primary text
Color get muted => _p.muted; // secondary text, inactive icons
Color get line => _p.line; // card outlines and dividers
Color get accent => _p.accent; // links, selection, primary actions
Color get accentSoft => _p.accentSoft; // tinted backgrounds behind accent icons
Color get positive => _p.positive; // you are owed / you lent
Color get negative => _p.negative; // you owe / you borrowed
// Text and icons on an [accent] fill: white, or near-black on the brighter dark accent.
Color get onAccent => AppTheme.instance.dark ? Palette.dark.paper : Colors.white;
const accentGlow = Color(0xFFFFC08A); // highlights on dark surfaces (splash, profile header)

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
List<BoxShadow> softShadow([Color? tint, double opacity = .07]) => [
  BoxShadow(color: (tint ?? ink).withValues(alpha: opacity), blurRadius: 16, offset: const Offset(0, 5)),
];

/// The standard card ([surface]): in light mode a hairline outline and a
/// soft, wide shadow for depth; in dark mode the lifted surface does that.
BoxDecoration cardDecoration({Color? color, double radius = cardRadius}) => BoxDecoration(
  color: color ?? surface,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: AppTheme.instance.dark ? line : line.withValues(alpha: .7)),
  boxShadow: AppTheme.instance.dark ? null : _cardShadow,
);

const _cardShadow = [
  BoxShadow(color: Color(0x0D2A0A14), blurRadius: 24, offset: Offset(0, 8)),
  BoxShadow(color: Color(0x082A0A14), blurRadius: 4, offset: Offset(0, 1)),
];

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

final _categoryColors = {
  'Food': const Color(0xFFD9692E),
  'Groceries': const Color(0xFF2E9465),
  'Stay': const Color(0xFF4F74CC),
  'Rent': const Color(0xFF7F5BC8),
  'Transport': const Color(0xFF2585AE),
  'Fuel': const Color(0xFFBA6A1E),
  'Shopping': const Color(0xFFC94F80),
  'Utilities': const Color(0xFFA88A10),
  'Activities': const Color(0xFF6E55CF),
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
  TripKind('trip', 'Trip', Icons.luggage_outlined, Color(0xFFB8364F)),
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
  if (diff.inMinutes < 1) return 'Just Now';
  if (diff.inHours < 1) return '${diff.inMinutes}m Ago';
  if (diff.inDays < 1) return '${diff.inHours}h Ago';
  if (diff.inDays < 7) return '${diff.inDays}d Ago';
  return formatDate(dt);
}

// --- Inputs -----------------------------------------------------------------------

InputDecoration appInputDecoration(String hint, IconData icon) =>
    InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 18, color: muted),
      filled: true,
      fillColor: surface,
      hintStyle: const TextStyle(color: Color(0xFFA9AEBC), fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: accent, width: 1.3),
      ),
    );

Widget fieldLabel(String text) => Text(
  text,
  style: TextStyle(
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
