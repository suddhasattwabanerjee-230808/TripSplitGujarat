import 'package:flutter/material.dart';

const ink = Color(0xFF182A3A);
const muted = Color(0xFF788692);
const paper = Color(0xFFF6F5F0);
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

String money(double value) =>
    '₹${value.toStringAsFixed(0).replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (match) => ',')}';

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
