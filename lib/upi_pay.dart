import 'package:flutter/services.dart';

enum UpiPayStatus { success, failed, unknown, noApp }

/// An installed app that takes UPI payments (Google Pay, PhonePe, ...).
class UpiApp {
  const UpiApp({required this.package, required this.label, required this.icon, this.canPay = true});
  final String package;
  final String label;

  /// Takes a filled-in upi://pay link. False for an app found by name whose
  /// link handler is off (not set up yet): it can still be opened to scan.
  final bool canPay;

  /// PNG bytes of its launcher icon.
  final Uint8List icon;
}

/// Hands a payment to an installed UPI app (GPay, PhonePe, Paytm, ...).
class UpiPay {
  static const _channel = MethodChannel('tripsplit/upi_pay');

  static String link({required String upiId, required String name, required double amount, String? note}) {
    return Uri(
      scheme: 'upi',
      host: 'pay',
      queryParameters: {
        'pa': upiId,
        'pn': name,
        'am': amount.toStringAsFixed(2),
        'cu': 'INR',
        if (note != null) 'tn': note,
      },
    ).toString();
  }

  /// The installed UPI apps, Google Pay and PhonePe first.
  static Future<List<UpiApp>> apps() async {
    try {
      final list = await _channel.invokeListMethod<Map<Object?, Object?>>('apps') ?? const [];
      return [
        for (final a in list)
          UpiApp(
            package: a['package'] as String,
            label: a['label'] as String,
            icon: a['icon'] as Uint8List,
            canPay: a['canPay'] as bool? ?? true,
          ),
      ];
    } on PlatformException {
      return const [];
    }
  }

  /// Opens [package] on its QR scanner (Google Pay, PhonePe), or on its
  /// home screen for apps we can't take straight there.
  static Future<bool> scan(String package) async {
    try {
      return await _channel.invokeMethod<bool>('scan', {'package': package}) ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens the payment in [package] (or the system chooser when null).
  /// [unknown] means the app returned without saying (many do), so the caller
  /// should ask the user whether the money went through.
  static Future<UpiPayStatus> pay({
    required String upiId,
    required String name,
    required double amount,
    String? note,
    String? package,
  }) async {
    final String response;
    try {
      response = await _channel.invokeMethod<String>(
            'pay',
            {'uri': link(upiId: upiId, name: name, amount: amount, note: note), if (package != null) 'package': package},
          ) ??
          '';
    } on PlatformException catch (e) {
      return e.code == 'no_upi_app' ? UpiPayStatus.noApp : UpiPayStatus.unknown;
    }
    final status = RegExp(r'status=([a-z]+)', caseSensitive: false).firstMatch(response)?.group(1)?.toLowerCase();
    return switch (status) {
      'success' => UpiPayStatus.success,
      'failure' || 'failed' => UpiPayStatus.failed,
      _ => UpiPayStatus.unknown,
    };
  }
}
