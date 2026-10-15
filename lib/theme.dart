import 'package:flutter/material.dart';

const ink = Color(0xFF182A3A);
const muted = Color(0xFF788692);
const paper = Color(0xFFFFF9DB);
const teal = Color(0xFF087E78);
const lime = Color(0xFFD9F078);

const memberPalette = [
  Color(0xFFE1B764),
  Color(0xFF88B8AD),
  Color(0xFFB49BC8),
  Color(0xFFD1805C),
  Color(0xFF7FA8D1),
  Color(0xFFC8A2C8),
  Color(0xFFA3C585),
  Color(0xFFE0A96D),
];

Color colorForMember(int index) => memberPalette[index % memberPalette.length];

/// A soft, background-tinted shadow for elevated cards — used in place of a
/// hard border so white/colored surfaces read as "lifted" rather than flat.
List<BoxShadow> softShadow([Color tint = ink, double opacity = .07]) => [
  BoxShadow(color: tint.withValues(alpha: opacity), blurRadius: 16, offset: const Offset(0, 5)),
];

const categoryOrder = ['Food', 'Stay', 'Transport', 'Activities', 'Other'];

const _categoryIcons = {
  'Food': Icons.restaurant_rounded,
  'Stay': Icons.hotel_rounded,
  'Transport': Icons.directions_car_rounded,
  'Activities': Icons.local_activity_rounded,
  'Other': Icons.more_horiz_rounded,
};

const _categoryColors = {
  'Food': Color(0xFFD1805C),
  'Stay': Color(0xFF7FA8D1),
  'Transport': teal,
  'Activities': Color(0xFFB49BC8),
  'Other': muted,
};

IconData iconForCategory(String? category) =>
    _categoryIcons[category] ?? Icons.more_horiz_rounded;

Color colorForCategory(String? category) => _categoryColors[category] ?? muted;

/// Expense locations are stored as "area, city" (or just "city" if that's
/// all reverse-geocoding returned) — the city is always the last segment.
String? cityFromLocation(String? location) {
  if (location == null || location.trim().isEmpty) return null;
  final parts = location.split(',');
  final city = parts.last.trim();
  return city.isEmpty ? null : city;
}

Color colorForCity(String city) => memberPalette[city.hashCode.abs() % memberPalette.length];

String money(double value) =>
    '₹${value.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')}';

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatDateTime(DateTime dt) {
  final now = DateTime.now();
  final isToday = dt.year == now.year && dt.month == now.month && dt.day == now.day;
  final yesterday = now.subtract(const Duration(days: 1));
  final isYesterday =
      dt.year == yesterday.year && dt.month == yesterday.month && dt.day == yesterday.day;
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  final time = '$hour12:$minute $period';
  if (isToday) return 'Today, $time';
  if (isYesterday) return 'Yesterday, $time';
  return '${dt.day} ${_months[dt.month - 1]}, $time';
}

InputDecoration appInputDecoration(String hint, IconData icon) =>
    InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, size: 18, color: muted),
      filled: true,
      fillColor: Colors.white,
      hintStyle: const TextStyle(color: Color(0xFFAAB3B5), fontSize: 13),
      contentPadding: const EdgeInsets.symmetric(vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: teal, width: 1.3),
      ),
    );

Widget fieldLabel(String text) => Text(
  text,
  style: const TextStyle(
    color: muted,
    fontSize: 9,
    letterSpacing: 1.2,
    fontWeight: FontWeight.w800,
  ),
);
