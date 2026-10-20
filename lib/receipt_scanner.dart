import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'category_guess.dart';

/// What could be read off a bill photo; any field may be missing.
class ReceiptScan {
  const ReceiptScan({this.title, this.amount, this.date, this.category});
  final String? title;
  final double? amount;
  final DateTime? date;
  final String? category;

  bool get isEmpty => title == null && amount == null && date == null;
}

class ReceiptScanner {
  static const _channel = MethodChannel('tripsplit/ocr');

  /// Takes (or picks) a photo and reads it on the device. Returns null if the
  /// user backs out; throws [PlatformException] if recognition fails.
  static Future<ReceiptScan?> scan({required bool fromCamera}) async {
    final photo = await ImagePicker().pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 90,
    );
    if (photo == null) return null;
    final text = await _channel.invokeMethod<String>('recognize', {'path': photo.path}) ?? '';
    return parse(text);
  }

  static final _amountPattern = RegExp(r'(?:rs\.?|inr|₹)?\s*(\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)', caseSensitive: false);
  static final _totalLine = RegExp(r'\b(grand\s*total|net\s*(amount|payable|total)|total\s*(amount|payable|due)?|amount\s*(payable|due)|to\s*pay|balance\s*due)\b', caseSensitive: false);
  static final _skipLine = RegExp(r'\b(sub\s*-?\s*total|discount|savings|you\s*saved|tax|gst|cgst|sgst|change|cash\s*tendered|qty|items?)\b', caseSensitive: false);

  /// Picks the bill total, the shop name and the date out of OCR text.
  static ReceiptScan parse(String text) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    return ReceiptScan(
      title: _title(lines),
      amount: _amount(lines),
      date: _date(text),
      category: lines.isEmpty ? null : guessCategory(lines.take(6).join(' ')),
    );
  }

  static double? _lastAmount(String line) {
    double? found;
    for (final m in _amountPattern.allMatches(line)) {
      final value = double.tryParse(m.group(1)!.replaceAll(',', ''));
      // Skip things that look like years, phone numbers or bill numbers.
      if (value != null && value > 0 && value < 1000000 && !(value >= 1900 && value <= 2100 && !m.group(1)!.contains('.'))) {
        found = value;
      }
    }
    return found;
  }

  static double? _amount(List<String> lines) {
    // 1. The last "total"-type line with a number on it (or on the next line).
    for (var i = lines.length - 1; i >= 0; i--) {
      if (!_totalLine.hasMatch(lines[i]) || _skipLine.hasMatch(lines[i])) continue;
      final here = _lastAmount(lines[i].replaceFirst(_totalLine, ''));
      if (here != null) return here;
      if (i + 1 < lines.length) {
        final next = _lastAmount(lines[i + 1]);
        if (next != null) return next;
      }
    }
    // 2. Otherwise the biggest money-looking number (with decimals or a ₹ sign).
    double? best;
    for (final line in lines) {
      if (_skipLine.hasMatch(line)) continue;
      if (!RegExp(r'(₹|rs\.?|inr|\d\.\d{2}\b)', caseSensitive: false).hasMatch(line)) continue;
      final v = _lastAmount(line);
      if (v != null && (best == null || v > best)) best = v;
    }
    return best;
  }

  static String? _title(List<String> lines) {
    // The shop name is usually the first line with real words on it.
    for (final line in lines.take(5)) {
      final letters = line.replaceAll(RegExp(r'[^A-Za-z ]'), '').trim();
      if (letters.length < 3 || RegExp(r'\b(tax|invoice|bill|receipt|gst|tel|phone|date)\b', caseSensitive: false).hasMatch(line)) {
        continue;
      }
      final clean = line.replaceAll(RegExp(r'\s+'), ' ');
      final cased = clean == clean.toUpperCase()
          ? clean.toLowerCase().split(' ').map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1)).join(' ')
          : clean;
      return cased.length > 40 ? cased.substring(0, 40) : cased;
    }
    return null;
  }

  static DateTime? _date(String text) {
    final m = RegExp(r'\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b').firstMatch(text);
    if (m == null) return null;
    final day = int.parse(m.group(1)!), month = int.parse(m.group(2)!);
    var year = int.parse(m.group(3)!);
    if (year < 100) year += 2000;
    if (month < 1 || month > 12 || day < 1 || day > 31) return null;
    final date = DateTime(year, month, day, DateTime.now().hour, DateTime.now().minute);
    final now = DateTime.now();
    // Ignore misreads that land far from today.
    return date.isAfter(now.add(const Duration(days: 1))) || date.isBefore(now.subtract(const Duration(days: 400)))
        ? null
        : date;
  }
}
