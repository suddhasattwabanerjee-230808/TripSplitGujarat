import 'package:flutter/services.dart';

enum UpiPayStatus { success, failed, unknown, noApp }

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

  /// [unknown] means the app returned without saying (many do), so the caller
  /// should ask the user whether the money went through.
  static Future<UpiPayStatus> pay({
    required String upiId,
    required String name,
    required double amount,
    String? note,
  }) async {
    final String response;
    try {
      response = await _channel.invokeMethod<String>(
            'pay',
            {'uri': link(upiId: upiId, name: name, amount: amount, note: note)},
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
